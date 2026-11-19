import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/env/app_env.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_auto_sync.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

void main() {
  group('JIRA_AUTO_SYNC_HOURS', () {
    test('por defecto y con valores inválidos son 2 horas', () {
      for (final raw in ['', 'abc', '0', '-1', '25']) {
        expect(AppEnv.parseAutoSyncInterval(raw), const Duration(hours: 2), reason: raw);
      }
    });

    test('acepta horas con decimales y respeta el mínimo de 5 minutos', () {
      expect(AppEnv.parseAutoSyncInterval('2'), const Duration(hours: 2));
      expect(AppEnv.parseAutoSyncInterval('0,5'), const Duration(minutes: 30));
      expect(AppEnv.parseAutoSyncInterval('0.01'), const Duration(minutes: 5));
    });
  });

  test('la leyenda dice cada cuánto', () {
    expect(formatEvery(const Duration(hours: 2)), 'cada 2 horas');
    expect(formatEvery(const Duration(hours: 1)), 'cada hora');
    expect(formatEvery(const Duration(minutes: 30)), 'cada 30 minutos');
    expect(formatEvery(const Duration(minutes: 90)), 'cada 1 h 30 min');
  });

  test('el ajuste viene activo y se guarda', () async {
    final repo = FakeProjectsRepository();
    final c = ProjectsController(repo);
    await c.load();
    expect(c.autoSyncJira, isTrue);
    await c.setAutoSyncJira(false);
    expect(repo.settings['jira_auto_sync'], '0');
    final again = ProjectsController(repo);
    await again.load();
    expect(again.autoSyncJira, isFalse);
    c.dispose();
    again.dispose();
  });

  group('JiraAutoSync', () {
    testWidgets('sincroniza en cada intervalo y solo si canSync lo permite', (tester) async {
      var allowed = true;
      var runs = 0;
      final auto = JiraAutoSync(
        interval: const Duration(hours: 2),
        canSync: () => allowed,
        sync: () async => runs++,
      )..start();

      await tester.pump(const Duration(hours: 1, minutes: 59));
      expect(runs, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(runs, 1);

      allowed = false; // ajuste apagado o sin sesión
      await tester.pump(const Duration(hours: 2));
      expect(runs, 1);

      allowed = true;
      await tester.pump(const Duration(hours: 2));
      expect(runs, 2);
      auto.dispose();
    });

    testWidgets('un fallo no detiene el temporizador', (tester) async {
      var runs = 0;
      final auto = JiraAutoSync(
        interval: const Duration(hours: 2),
        canSync: () => true,
        sync: () async {
          runs++;
          throw StateError('sin red');
        },
      )..start();
      await tester.pump(const Duration(hours: 2));
      await tester.pump(const Duration(hours: 2));
      expect(runs, 2);
      auto.dispose();
    });
  });
}
