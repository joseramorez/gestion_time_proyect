import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

/// El progreso del día (suma de los cronómetros actuales) y la subida a Jira por
/// ticket o en conjunto, con horas y minutos.
void main() {
  late FakeProjectsRepository repo;
  late FakeWorkLogRepository log;
  late ProjectsController projects;
  late DailyController daily;
  var now = DateTime(2026, 11, 12, 10);
  var canPost = true;
  final posted = <({String key, int seconds, DateTime started})>[];
  final failFor = <String>{};

  Future<String?> post({
    required String issueKey,
    required int seconds,
    required DateTime started,
    String comment = '',
  }) async {
    if (failFor.contains(issueKey)) return 'Jira rechazó $issueKey';
    posted.add((key: issueKey, seconds: seconds, started: started));
    return null;
  }

  setUp(() async {
    now = DateTime(2026, 11, 12, 10);
    canPost = true;
    posted.clear();
    failFor.clear();
    repo = FakeProjectsRepository();
    log = FakeWorkLogRepository();
    // A: 1 h 23 m 40 s (Jira) · B: 40 m (Jira) · C: 30 m (manual)
    await repo.insert(const Project(name: 'A', jiraKey: 'ABC-1', accumulatedMs: 5020000));
    await repo.insert(const Project(name: 'B', jiraKey: 'ABC-2', accumulatedMs: 2400000));
    await repo.insert(const Project(name: 'C', accumulatedMs: 1800000));
    projects = ProjectsController(repo, work: log, clock: () => now);
    await projects.load();
    daily = DailyController(
      projects,
      log,
      goal: const Duration(hours: 8),
      clock: () => now,
      post: post,
      canPost: () => canPost,
    );
    await daily.load();
  });

  tearDown(() {
    daily.dispose();
    projects.dispose();
  });

  Project byName(String n) => projects.projects.firstWhere((p) => p.name == n);

  group('progreso del día', () {
    test('es la suma de lo que marcan ahora los cronómetros de todos los tickets', () {
      expect(daily.ticketsTotal, const Duration(hours: 2, minutes: 33, seconds: 40));
      expect(daily.ticketsProgress, closeTo(2.5611 / 8, 0.001));
    });

    test('un ticket en marcha cuenta en vivo', () async {
      await projects.start(byName('B'));
      now = now.add(const Duration(minutes: 20));
      expect(daily.ticketsTotal, const Duration(hours: 2, minutes: 53, seconds: 40));
    });

    test('limpiar un ticket lo quita del total (no queda tiempo fantasma)', () async {
      await projects.clear(byName('A'));
      await projects.clear(byName('B'));
      await projects.clear(byName('C'));
      expect(daily.ticketsTotal, Duration.zero);
      expect(daily.ticketsProgress, 0);
    });

    test('nada bloquea: se puede iniciar aunque haya días anteriores con tiempo subido',
        () async {
      log.sent['2026-11-01'] = {1: 3600};
      await daily.load();
      await projects.start(byName('A'));
      expect(byName('A').isRunning, isTrue);
    });
  });

  group('subir un ticket', () {
    test('con reinicio sube horas y minutos, deja el reloj en cero y lo anota hoy', () async {
      final error = await daily.upload(byName('A'), 83); // 1 h 23 m
      expect(error, isNull);
      expect(posted.single.key, 'ABC-1');
      expect(posted.single.seconds, 83 * 60);
      expect(posted.single.started, now.subtract(const Duration(minutes: 83)));
      expect(byName('A').elapsed(now), Duration.zero); // los 40 s sobrantes se descartan
      expect(byName('A').jiraLoggedMs, 83 * 60 * 1000);
      expect(daily.sentToday, const Duration(minutes: 83));
      expect(log.sent['2026-11-12'], {1: 83 * 60});
      // lo subido no cuenta como tiempo de los tickets
      expect(daily.ticketsTotal, const Duration(minutes: 70));
    });

    test('sin reinicio conserva lo que sobra en el cronómetro', () async {
      await daily.upload(byName('A'), 83, reset: false);
      expect(byName('A').elapsed(now), const Duration(seconds: 40));
      expect(daily.sentToday, const Duration(minutes: 83));
    });

    test('si Jira lo rechaza no cambia nada', () async {
      failFor.add('ABC-1');
      final error = await daily.upload(byName('A'), 83);
      expect(error, 'Jira rechazó ABC-1');
      expect(byName('A').elapsed(now), const Duration(hours: 1, minutes: 23, seconds: 40));
      expect(daily.sentToday, Duration.zero);
      expect(log.sent, isEmpty);
    });

    test('valida: mínimo 1 minuto, máximo 24 h, solo tickets de Jira', () async {
      expect(await daily.upload(byName('A'), 0), contains('Mínimo 1 minuto'));
      expect(await daily.upload(byName('A'), 24 * 60 + 1), contains('Máximo 24 horas'));
      expect(await daily.upload(byName('C'), 10), contains('no es de Jira'));
      expect(posted, isEmpty);
    });

    test('sin sesión con permiso de escritura no envía nada', () async {
      canPost = false;
      expect(daily.canSend, isFalse);
      expect(await daily.upload(byName('A'), 10), contains('Inicia sesión'));
      expect(posted, isEmpty);
    });

    test('si falla el guardado de lo subido, el cronómetro ya bajó y se ve como subido',
        () async {
      log.failAddSent = true;
      expect(await daily.upload(byName('A'), 83), isNull);
      expect(byName('A').elapsed(now), Duration.zero);
      expect(daily.sentToday, const Duration(minutes: 83));
    });

    test('un segundo envío mientras hay uno en curso se rechaza', () async {
      final gate = Completer<String?>();
      final slow = DailyController(projects, log,
          goal: const Duration(hours: 8),
          clock: () => now,
          post: ({required issueKey, required seconds, required started, comment = ''}) =>
              gate.future,
          canPost: () => true);
      final first = slow.upload(byName('A'), 10);
      expect(slow.sending, isTrue);
      expect(await slow.upload(byName('B'), 10), contains('Ya se está subiendo'));
      gate.complete(null);
      expect(await first, isNull);
      expect(slow.sending, isFalse);
      slow.dispose();
    });
  });

  group('subir todos', () {
    test('sube cada ticket por separado con sus horas y minutos', () async {
      final errors = await daily.uploadAll([
        const UploadRequest(1, 83),
        const UploadRequest(2, 40),
      ]);
      expect(errors, isEmpty);
      expect(posted.map((p) => (p.key, p.seconds)), [('ABC-1', 4980), ('ABC-2', 2400)]);
      expect(daily.sentToday, const Duration(minutes: 123));
      expect(byName('A').elapsed(now), Duration.zero);
      expect(byName('B').elapsed(now), Duration.zero);
      expect(byName('C').elapsed(now), const Duration(minutes: 30)); // manual: intacto
    });

    test('un fallo no detiene los demás y un reintento no repite lo ya subido', () async {
      failFor.add('ABC-2');
      var errors = await daily.uploadAll([
        const UploadRequest(1, 83),
        const UploadRequest(2, 40),
      ]);
      expect(errors.keys, [2]);
      expect(posted.map((p) => p.key), ['ABC-1']);
      expect(byName('B').elapsed(now), const Duration(minutes: 40));

      failFor.clear();
      errors = await daily.uploadAll([
        const UploadRequest(2, 40),
      ]); // solo lo que falló
      expect(errors, isEmpty);
      expect(posted.map((p) => p.key), ['ABC-1', 'ABC-2']);
      expect(daily.sentToday, const Duration(minutes: 123));
    });
  });

  group('subido hoy', () {
    test('un corte por ticket (recordSent) cuenta como subido hoy', () async {
      await daily.recordSent(byName('B'), 25 * 60 * 1000);
      expect(daily.sentToday, const Duration(minutes: 25));
      expect(daily.sentTodayByProject, {2: 25 * 60});
      expect(log.sent['2026-11-12'], {2: 25 * 60});
    });

    test('al abrir la app recupera lo subido hoy y no lo de otros días', () async {
      log.sent['2026-11-12'] = {1: 600};
      log.sent['2026-11-11'] = {1: 9999};
      await daily.load();
      expect(daily.sentToday, const Duration(minutes: 10));
    });

    test('al cambiar el día vuelve a cero', () async {
      final d = DailyController(projects, log,
          goal: const Duration(hours: 8),
          clock: () => now,
          post: post,
          canPost: () => true,
          rolloverCheck: const Duration(milliseconds: 10));
      await d.load();
      await d.recordSent(byName('A'), 3600 * 1000);
      expect(d.sentToday, const Duration(hours: 1));

      now = DateTime(2026, 11, 13, 9);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(d.today, '2026-11-13');
      expect(d.sentToday, Duration.zero);
      d.dispose();
    });
  });

  group('día trabajado', () {
    test('subir a ayer lo anota ayer, no cuenta como subido hoy y a Jira solo va el tiempo', () async {
      expect(await daily.upload(byName('A'), 83, day: '2026-11-11'), isNull);
      // la fecha no viaja: siempre ahora menos la duración
      expect(posted.single.started, now.subtract(const Duration(minutes: 83)));
      expect(posted.single.seconds, 83 * 60);
      expect(daily.sentToday, Duration.zero);
      expect(log.sent['2026-11-11'], {1: 83 * 60});
      expect(log.sent['2026-11-12'], isNull);
      // el cronómetro baja igual
      expect(byName('A').elapsed(now), Duration.zero);
    });

    test('lo anotado en un día anterior se suma a lo que ya tenía ese día', () async {
      log.sent['2026-11-11'] = {2: 3600};
      await daily.upload(byName('B'), 40, day: '2026-11-11');
      expect(log.sent['2026-11-11'], {2: 3600 + 40 * 60});
    });

    test('hoy: ahora menos la duración y cuenta como subido hoy', () async {
      await daily.upload(byName('B'), 40, day: '2026-11-12');
      expect(posted.single.started, now.subtract(const Duration(minutes: 40)));
      expect(daily.sentToday, const Duration(minutes: 40));
    });

    test('un día futuro se rechaza y no cambia nada', () async {
      expect(
        await daily.upload(byName('A'), 10, day: '2026-11-13'),
        contains('futuro'),
      );
      expect(posted, isEmpty);
      expect(byName('A').elapsed(now), const Duration(hours: 1, minutes: 23, seconds: 40));
    });

    test('subir todos respeta el día de cada ticket', () async {
      final errors = await daily.uploadAll([
        const UploadRequest(1, 83, '2026-11-11'),
        const UploadRequest(2, 40),
      ]);
      expect(errors, isEmpty);
      expect(log.sent['2026-11-11'], {1: 83 * 60});
      expect(log.sent['2026-11-12'], {2: 40 * 60});
      expect(daily.sentToday, const Duration(minutes: 40));
    });

    test('aviso: carriedOver y suggestedDay según desde cuándo viene el tiempo', () async {
      await repo.update(
        byName('A').copyWith(
          timeSinceMs: () => DateTime(2026, 11, 11, 15).millisecondsSinceEpoch,
        ),
      );
      await projects.load();
      expect(daily.carriedOver.map((p) => p.name), ['A']);
      expect(daily.suggestedDay(byName('A')), '2026-11-11');
      expect(daily.suggestedDay(byName('B')), '2026-11-12');
    });

    test('el registro anterior: desde cuándo viene el tiempo, o el día hábil previo', () async {
      // sin saber desde cuándo: el día hábil anterior (hoy es jueves 12 -> miércoles 11)
      expect(daily.previousDayFor(byName('A')), '2026-11-11');
      // viniendo de varios días atrás (no se registró desde la última vez que se usó)
      await repo.update(
        byName('A').copyWith(
          timeSinceMs: () => DateTime(2026, 11, 6, 15).millisecondsSinceEpoch,
        ),
      );
      await projects.load();
      expect(daily.previousDayFor(byName('A')), '2026-11-06');
      expect(daily.suggestedDay(byName('A')), '2026-11-06');
    });

    test('limpiar un ticket quita el aviso', () async {
      await repo.update(
        byName('A').copyWith(
          timeSinceMs: () => DateTime(2026, 11, 11, 15).millisecondsSinceEpoch,
        ),
      );
      await projects.load();
      await projects.clear(byName('A'));
      expect(daily.carriedOver, isEmpty);
    });
  });

  group('bloqueo de iniciar con tiempo de otro día', () {
    late ProjectsController pc;
    late DailyController dc;
    final yesterdayMs = DateTime(2026, 11, 11, 15).millisecondsSinceEpoch;

    setUp(() async {
      // A trae tiempo de ayer; B es de hoy; C es manual
      await repo.update(
        repo.rows.firstWhere((p) => p.name == 'A').copyWith(timeSinceMs: () => yesterdayMs),
      );
      await repo.update(
        repo.rows.firstWhere((p) => p.name == 'C').copyWith(timeSinceMs: () => yesterdayMs),
      );
      pc = ProjectsController(
        repo,
        work: log,
        clock: () => now,
        canStart: (p) => !dc.isStartBlocked(p),
      );
      dc = DailyController(
        pc,
        log,
        goal: const Duration(hours: 8),
        clock: () => now,
        post: post,
        canPost: () => canPost,
      );
      await pc.load();
      await dc.load();
    });

    tearDown(() {
      dc.dispose();
      pc.dispose();
    });

    Project of(String n) => pc.projects.firstWhere((p) => p.name == n);

    test('solo se bloquea el ticket que trae tiempo anterior', () async {
      expect(dc.isStartBlocked(of('A')), isTrue);
      expect(dc.isStartBlocked(of('B')), isFalse);
      await pc.start(of('A'));
      expect(of('A').isRunning, isFalse);
      await pc.start(of('B'));
      expect(of('B').isRunning, isTrue);
    });

    test('el manual con tiempo anterior también se bloquea (se resuelve limpiándolo)', () async {
      expect(dc.isStartBlocked(of('C')), isTrue);
      await pc.clear(of('C'));
      expect(dc.isStartBlocked(of('C')), isFalse);
      await pc.start(of('C'));
      expect(of('C').isRunning, isTrue);
    });

    test('iniciar uno bloqueado no pausa el que está corriendo', () async {
      await pc.start(of('B'));
      await pc.start(of('A'));
      expect(of('B').isRunning, isTrue);
      expect(of('A').isRunning, isFalse);
    });

    test('subir todo su tiempo (con reinicio) lo desbloquea', () async {
      expect(await dc.upload(of('A'), 83, day: '2026-11-11'), isNull);
      expect(dc.isStartBlocked(of('A')), isFalse);
      await pc.start(of('A'));
      expect(of('A').isRunning, isTrue);
    });

    test('subir solo una parte sin reiniciar lo mantiene bloqueado si queda 1 minuto o más', () async {
      expect(await dc.upload(of('A'), 60, reset: false, day: '2026-11-11'), isNull);
      // quedan 23 m 40 s
      expect(dc.isStartBlocked(of('A')), isTrue);
    });

    test('si solo sobran segundos (menos de 1 minuto) ya no bloquea', () async {
      expect(await dc.upload(of('A'), 83, reset: false, day: '2026-11-11'), isNull);
      // sobran 40 s: no se pueden subir
      expect(dc.isStartBlocked(of('A')), isFalse);
    });

    test('un cronómetro que ya corría no se bloquea ni se detiene; al pausarlo sí queda bloqueado', () async {
      await repo.update(
        repo.rows
            .firstWhere((p) => p.name == 'A')
            .copyWith(
              accumulatedMs: 0,
              startedAtMs: () => DateTime(2026, 11, 11, 15).millisecondsSinceEpoch,
            ),
      );
      await pc.load();
      expect(of('A').isRunning, isTrue);
      expect(dc.carriesOlderTime(of('A')), isTrue);
      expect(dc.isStartBlocked(of('A')), isFalse); // ya corre: no se detiene
      await pc.pause(of('A')); // pausar siempre se puede
      expect(of('A').isRunning, isFalse);
      expect(dc.isStartBlocked(of('A')), isTrue); // y reanudar exige subirlo antes
    });

    test('al cambiar el día, el tiempo de ayer bloquea su ticket', () async {
      await pc.clear(of('A'));
      await pc.start(of('A')); // empieza hoy (jueves 12, 10:00)
      now = now.add(const Duration(minutes: 30));
      await pc.pause(of('A'));
      expect(dc.isStartBlocked(of('A')), isFalse); // es tiempo de hoy
      now = DateTime(2026, 11, 13, 9); // llega el viernes
      await dc.load();
      expect(dc.isStartBlocked(of('A')), isTrue);
    });
  });
}
