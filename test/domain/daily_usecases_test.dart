import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/domain/entities/day_key.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/usecases/apply_jira_cut.dart';
import 'package:gestion_time_proyect/domain/usecases/clear_project.dart';
import 'package:gestion_time_proyect/domain/usecases/evaluate_goal.dart';
import 'package:gestion_time_proyect/domain/usecases/split_minutes.dart';
import 'package:gestion_time_proyect/domain/usecases/start_project.dart';

/// Reglas del corte del día: estado frente a la meta, horas y minutos sin segundos
/// y reinicio del cronómetro al subir.
void main() {
  group('EvaluateGoal', () {
    const eval = EvaluateGoal();
    const goal = Duration(hours: 8);
    const min = Duration(hours: 7);
    GoalStatus at(Duration total) => eval(total: total, goal: goal, minimum: min);

    test('menos del mínimo: short', () {
      expect(at(Duration.zero), GoalStatus.short);
      expect(at(const Duration(hours: 6, minutes: 59)), GoalStatus.short);
    });

    test('del mínimo a la meta sin llegar: acceptable', () {
      expect(at(const Duration(hours: 7)), GoalStatus.acceptable);
      expect(at(const Duration(hours: 7, minutes: 59)), GoalStatus.acceptable);
    });

    test('justo la meta: met; más: over (permitido)', () {
      expect(at(const Duration(hours: 8)), GoalStatus.met);
      expect(at(const Duration(hours: 8, minutes: 1)), GoalStatus.over);
      expect(at(const Duration(hours: 12)), GoalStatus.over);
    });

    test('se compara en minutos redondeados: 7 h 59 m 40 s cuenta como 8 h', () {
      expect(at(const Duration(hours: 7, minutes: 59, seconds: 40)), GoalStatus.met);
    });

    test('el mínimo nunca pasa de la meta', () {
      final s = eval(
          total: const Duration(hours: 5),
          goal: const Duration(hours: 5),
          minimum: const Duration(hours: 7));
      expect(s, GoalStatus.met);
    });

    test('difference es siempre positivo', () {
      expect(eval.difference(total: const Duration(hours: 5), goal: goal),
          const Duration(hours: 3));
      expect(eval.difference(total: const Duration(hours: 9), goal: goal),
          const Duration(hours: 1));
    });
  });

  group('SplitMinutes', () {
    test('trunca los segundos', () {
      final hm = const SplitMinutes()(const Duration(hours: 1, minutes: 23, seconds: 40));
      expect(hm.hours, 1);
      expect(hm.minutes, 23);
      expect(SplitMinutes.wholeMinutes(const Duration(minutes: 5, seconds: 59)), 5);
    });

    test('segundos a partir de horas y minutos: siempre múltiplo de 60', () {
      expect(SplitMinutes.seconds(1, 23), 4980);
      expect(SplitMinutes.seconds(0, 0), 0);
    });
  });

  group('ApplyJiraCut con reset', () {
    final now = DateTime(2026, 11, 12, 15);
    Project p({int acc = 0, int? startedAgoMs}) => Project(
          id: 1,
          name: 'P',
          accumulatedMs: acc,
          startedAtMs: startedAgoMs == null ? null : now.millisecondsSinceEpoch - startedAgoMs,
        );

    test('sin reset se conserva lo que sobra', () {
      final cut = const ApplyJiraCut()(p(acc: 5020000), 4980000, now);
      expect(cut.accumulatedMs, 40000);
      expect(cut.jiraLoggedMs, 4980000);
    });

    test('con reset queda en cero y solo cuenta lo subido como enviado', () {
      final cut = const ApplyJiraCut()(p(acc: 5020000), 4980000, now, reset: true);
      expect(cut.accumulatedMs, 0);
      expect(cut.jiraLoggedMs, 4980000);
    });

    test('con reset un cronómetro en marcha sigue corriendo desde cero', () {
      final cut = const ApplyJiraCut()(p(startedAgoMs: 125000), 120000, now, reset: true);
      expect(cut.isRunning, isTrue);
      expect(cut.elapsed(now), Duration.zero);
    });
  });

  group('previousWorkday', () {
    test('entre semana es el día de antes', () {
      expect(previousWorkday('2026-11-12'), '2026-11-11'); // jueves -> miércoles
      expect(previousWorkday('2026-11-10'), '2026-11-09'); // martes -> lunes
    });

    test('el lunes (y el fin de semana) es el viernes', () {
      expect(previousWorkday('2026-11-16'), '2026-11-13'); // lunes -> viernes
      expect(previousWorkday('2026-11-15'), '2026-11-13'); // domingo -> viernes
      expect(previousWorkday('2026-11-14'), '2026-11-13'); // sábado -> viernes
    });

    test('cruza el cambio de mes y de año', () {
      expect(previousWorkday('2026-12-01'), '2026-11-30');
      expect(previousWorkday('2027-01-01'), '2026-12-31');
    });
  });

  group('desde cuándo viene el tiempo (timeSinceMs)', () {
    final now = DateTime(2026, 11, 12, 15);
    final nowMs = now.millisecondsSinceEpoch;
    final yesterdayMs = DateTime(2026, 11, 11, 23, 59).millisecondsSinceEpoch;

    test('al iniciar desde cero empieza ahora', () {
      final changed = const StartProject()([
        const Project(id: 1, name: 'A'),
      ], 1, now);
      expect(changed.single.timeSinceMs, nowMs);
    });

    test('al reanudar con tiempo se conserva desde cuándo venía', () {
      final changed = const StartProject()([
        Project(id: 1, name: 'A', accumulatedMs: 5000, timeSinceMs: yesterdayMs),
      ], 1, now);
      expect(changed.single.timeSinceMs, yesterdayMs);
    });

    test('con tiempo de antes y sin saber desde cuándo, sigue sin saberse', () {
      final changed = const StartProject()([
        const Project(id: 1, name: 'A', accumulatedMs: 5000),
      ], 1, now);
      expect(changed.single.timeSinceMs, isNull);
    });

    test('limpiar lo borra', () {
      final cleared = const ClearProject()(
        Project(id: 1, name: 'A', accumulatedMs: 5000, timeSinceMs: yesterdayMs),
      );
      expect(cleared.timeSinceMs, isNull);
    });

    test('subir todo con reinicio lo borra; si sigue corriendo, empieza ahora', () {
      final paused = const ApplyJiraCut()(
        Project(id: 1, name: 'A', accumulatedMs: 120000, timeSinceMs: yesterdayMs),
        120000,
        now,
        reset: true,
      );
      expect(paused.timeSinceMs, isNull);
      final running = const ApplyJiraCut()(
        Project(
          id: 1,
          name: 'A',
          startedAtMs: nowMs - 120000,
          timeSinceMs: yesterdayMs,
        ),
        120000,
        now,
        reset: true,
      );
      expect(running.timeSinceMs, nowMs);
    });

    test('subir solo una parte conserva desde cuándo', () {
      final cut = const ApplyJiraCut()(
        Project(id: 1, name: 'A', accumulatedMs: 600000, timeSinceMs: yesterdayMs),
        120000,
        now,
      );
      expect(cut.timeSinceMs, yesterdayMs);
    });

    test('carriesTimeBefore: solo con tiempo y sabiendo que es de un día anterior', () {
      Project p({int acc = 120000, int? since}) =>
          Project(id: 1, name: 'A', accumulatedMs: acc, timeSinceMs: since);
      expect(p(since: yesterdayMs).carriesTimeBefore('2026-11-12'), isTrue);
      expect(p(since: yesterdayMs).timeSinceDay, '2026-11-11');
      expect(p(since: nowMs).carriesTimeBefore('2026-11-12'), isFalse);
      expect(p(acc: 0, since: yesterdayMs).carriesTimeBefore('2026-11-12'), isFalse);
      expect(p().carriesTimeBefore('2026-11-12'), isFalse);
      // menos de 1 minuto no se puede subir: no cuenta como tiempo anterior
      expect(
        p(acc: 30000, since: yesterdayMs).carriesTimeBefore('2026-11-12'),
        isFalse,
      );
    });
  });
}
