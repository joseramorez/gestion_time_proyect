import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/usecases/apply_jira_cut.dart';
import 'package:gestion_time_proyect/domain/usecases/clear_project.dart';
import 'package:gestion_time_proyect/domain/usecases/find_stale_jira_keys.dart';
import 'package:gestion_time_proyect/domain/usecases/pause_project.dart';
import 'package:gestion_time_proyect/domain/usecases/prepare_worklog.dart';
import 'package:gestion_time_proyect/domain/usecases/start_project.dart';

/// Casos de uso: reglas de negocio puras, sin base de datos, sin Flutter y con el
/// reloj (`now`) como parámetro, así que son deterministas.
void main() {
  final now = DateTime(2026, 11, 12, 15, 0, 0);
  final nowMs = now.millisecondsSinceEpoch;

  Project p(int id, {int acc = 0, bool running = false, int startedAgoMs = 0, int logged = 0}) =>
      Project(
        id: id,
        name: 'P$id',
        accumulatedMs: acc,
        startedAtMs: running ? nowMs - startedAgoMs : null,
        jiraLoggedMs: logged,
      );

  group('PauseProject', () {
    test('congela lo transcurrido en el acumulado y detiene el cronómetro', () {
      final paused = const PauseProject()(p(1, acc: 5000, running: true, startedAgoMs: 3000), now)!;
      expect(paused.isRunning, isFalse);
      expect(paused.accumulatedMs, 8000);
    });

    test('si no corría no hay nada que cambiar (null)', () {
      expect(const PauseProject()(p(1, acc: 5000), now), isNull);
    });
  });

  group('StartProject', () {
    test('inicia el proyecto elegido', () {
      final changed = const StartProject()([p(1), p(2)], 2, now);
      expect(changed.map((x) => x.id), [2]);
      expect(changed.single.startedAtMs, nowMs);
    });

    test('solo uno corre a la vez: pausa al que estaba en marcha, en el mismo instante', () {
      final changed = const StartProject()(
        [p(1, acc: 1000, running: true, startedAgoMs: 4000), p(2)],
        2,
        now,
      );
      final one = changed.firstWhere((x) => x.id == 1);
      final two = changed.firstWhere((x) => x.id == 2);
      expect(one.isRunning, isFalse);
      expect(one.accumulatedMs, 5000);
      expect(two.startedAtMs, nowMs);
    });

    test('si ya corría y no hay otros en marcha, no cambia nada', () {
      expect(const StartProject()([p(1, running: true), p(2)], 1, now), isEmpty);
    });

    test('reanudar conserva el tiempo acumulado', () {
      final changed = const StartProject()([p(1, acc: 7000)], 1, now);
      expect(changed.single.accumulatedMs, 7000);
      expect(changed.single.isRunning, isTrue);
    });
  });

  group('ClearProject', () {
    test('deja el tiempo en cero y detiene el cronómetro', () {
      final c = const ClearProject()(p(1, acc: 9000, running: true));
      expect(c.accumulatedMs, 0);
      expect(c.isRunning, isFalse);
    });

    test('no toca lo ya enviado a Jira', () {
      expect(const ClearProject()(p(1, acc: 9000, logged: 3000)).jiraLoggedMs, 3000);
    });
  });

  group('ApplyJiraCut', () {
    test('pausado: descuenta lo enviado, conserva el resto y suma al total', () {
      final cut = const ApplyJiraCut()(p(1, acc: 200000), 90000, now);
      expect(cut.accumulatedMs, 110000);
      expect(cut.isRunning, isFalse);
      expect(cut.jiraLoggedMs, 90000);
    });

    test('pausado: si se envía más de lo medido queda en cero', () {
      final cut = const ApplyJiraCut()(p(1, acc: 100000), 300000, now);
      expect(cut.accumulatedMs, 0);
      expect(cut.jiraLoggedMs, 300000);
    });

    test('corriendo: sigue corriendo con lo que quede', () {
      // 130 s medidos (acumulado 100 s + 30 s corriendo); se envían 120 s → quedan 10 s.
      final cut = const ApplyJiraCut()(
          p(1, acc: 100000, running: true, startedAgoMs: 30000), 120000, now);
      expect(cut.isRunning, isTrue);
      expect(cut.accumulatedMs, 0);
      expect(cut.elapsed(now), const Duration(seconds: 10));
      expect(cut.jiraLoggedMs, 120000);
    });

    test('los cortes se acumulan en el total enviado', () {
      var cut = const ApplyJiraCut()(p(1, acc: 200000), 60000, now);
      cut = const ApplyJiraCut()(cut, 60000, now);
      expect(cut.jiraLoggedMs, 120000);
      expect(cut.accumulatedMs, 80000);
    });
  });

  group('PrepareWorklog', () {
    test('sin tiempo editado usa el medido y calcula el inicio', () {
      final w = const PrepareWorklog()(measured: const Duration(minutes: 5), now: now);
      expect(w.seconds, 300);
      expect(w.started, now.subtract(const Duration(minutes: 5)));
    });

    test('el tiempo confirmado por el usuario manda sobre el medido', () {
      final w = const PrepareWorklog()(
        measured: const Duration(minutes: 5),
        requested: const Duration(minutes: 2),
        now: now,
      );
      expect(w.seconds, 120);
    });

    test('los límites: 60 s y 24 h son válidos, uno menos / uno más no', () {
      const prepare = PrepareWorklog();
      expect(prepare(measured: const Duration(seconds: 60), now: now).seconds, 60);
      expect(prepare(measured: const Duration(hours: 24), now: now).seconds, 86400);
      expect(() => prepare(measured: const Duration(seconds: 59), now: now),
          throwsA(isA<InvalidWorklog>().having((e) => e.message, 'm', contains('menos de 1 minuto'))));
      expect(() => prepare(measured: const Duration(hours: 24, seconds: 1), now: now),
          throwsA(isA<InvalidWorklog>().having((e) => e.message, 'm', contains('24 horas'))));
    });
  });

  group('FindStaleJiraKeys', () {
    Project jira(String key) => Project(id: 1, name: key, jiraKey: key);

    test('devuelve las claves importadas que no volvieron en la búsqueda', () {
      final stale = const FindStaleJiraKeys()(
        [jira('A-1'), jira('A-2'), jira('A-3')],
        {'A-2'},
      );
      expect(stale, ['A-1', 'A-3']);
    });

    test('ignora las entradas manuales (sin clave de Jira)', () {
      expect(const FindStaleJiraKeys()([p(1), jira('A-1')], <String>{}), ['A-1']);
    });

    test('si todas volvieron, no hay nada que refrescar', () {
      expect(const FindStaleJiraKeys()([jira('A-1')], {'A-1'}), isEmpty);
    });
  });
}
