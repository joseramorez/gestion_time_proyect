import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/env/app_env.dart';
import 'package:gestion_time_proyect/config/router/app_router.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/core/services/startup_service.dart';
import 'package:gestion_time_proyect/core/services/window_service.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/repository/work_log_repository_impl.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_auto_sync.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

/// Punto de entrada. Aquí se arma el árbol de dependencias de las capas:
/// datos (SQLite, Jira, almacén seguro) → repositorio → view models → pantalla.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await AppDatabase.open();
  final workLog = WorkLogRepositoryImpl(db);

  // Un corte por ticket cuenta como "subido hoy" y un ticket con tiempo de un día anterior
  // no se puede iniciar: los dos view models se referencian, así que se enlazan por closure.
  late final DailyController daily;
  final controller = ProjectsController(
    ProjectsRepositoryImpl(db),
    work: workLog,
    canStart: (project) => !daily.isStartBlocked(project),
    onJiraSent: (project, sentMs) => daily.recordSent(project, sentMs),
  );
  await controller.load();

  final jira = JiraController(
    store: const SecureSecretStore(),
    oauth: JiraOAuth(
      openBrowser: (url) =>
          launchUrl(url, mode: LaunchMode.externalApplication),
    ),
    api: JiraApi(),
    defaultClientId: const String.fromEnvironment('JIRA_CLIENT_ID'),
    defaultClientSecret: const String.fromEnvironment('JIRA_CLIENT_SECRET'),
  );
  await jira.load();

  daily = DailyController(
    controller,
    workLog,
    goal: AppEnv.dailyGoal,
    minimum: AppEnv.dailyMinimum,
    canPost: () => jira.signedIn && jira.canWrite,
    post: jira.postWorklog,
  );
  await daily.load();

  // Sincronización automática de Jira (ajuste "Ventana"): solo con sesión iniciada.
  JiraAutoSync(
    interval: AppEnv.jiraAutoSyncInterval,
    canSync: () => controller.autoSyncJira && jira.signedIn && !jira.busy,
    sync: () => jira.sync(controller),
  ).start();

  await windowManager.ensureInitialized();
  // La ventana arranca ocupando un cuarto de la pantalla (ver `WindowLimits.startFor`),
  // centrada; el mínimo sigue siendo `WindowLimits.min` y el usuario puede cambiarla.
  final displays = WidgetsBinding.instance.platformDispatcher.displays;
  final screen = displays.isEmpty
      ? WindowLimits.min
      : displays.first.size / displays.first.devicePixelRatio;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: WindowLimits.startFor(screen),
      minimumSize: WindowLimits.min,
      center: true,
      title: 'my-jira-work-time',
    ),
    () async {
      await windowManager.setAlwaysOnTop(controller.alwaysOnTop);
      await windowManager.setOpacity(controller.opacity);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(
    GestionTimeApp(
      controller: controller,
      jira: jira,
      daily: daily,
      window: ManagedWindowService(),
      startup: OsStartupService(),
    ),
  );
}

class GestionTimeApp extends StatelessWidget {
  const GestionTimeApp({
    super.key,
    required this.controller,
    required this.jira,
    required this.daily,
    required this.window,
    this.startup,
  });

  final ProjectsController controller;
  final JiraController jira;
  final DailyController daily;
  final WindowService window;
  final StartupService? startup;

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(
      homeBuilder: (_) => HomePage(
        controller: controller,
        jira: jira,
        daily: daily,
        window: window,
        startup: startup,
        autoSyncInterval: AppEnv.jiraAutoSyncInterval,
      ),
    );
    return MaterialApp(
      title: 'my-jira-work-time',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialRoute: AppRoutes.home,
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}
