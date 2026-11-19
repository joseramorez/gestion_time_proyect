import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_dialog.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

/// El diálogo de Jira siempre ofrece una salida evidente: el botón "Cerrar".
void main() {
  late ProjectsController projects;
  late MemorySecretStore store;
  late JiraController jira;

  setUp(() async {
    projects = ProjectsController(FakeProjectsRepository());
    await projects.load();
    store = MemorySecretStore();
  });

  tearDown(() => projects.dispose());

  Future<void> signedInStore() async {
    store.data['jira_client_id'] = 'cid';
    store.data['jira_client_secret'] = 'sec';
    store.data['jira_session'] = JiraSessionModel.toJson(JiraSession(
      tokens: TokenSet(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        scope: 'read:jira-work write:jira-work',
      ),
      sites: const [JiraSite(id: 's', name: 'Acme', url: 'https://acme.atlassian.net')],
      siteId: 's',
    ));
  }

  Future<void> openDialog(
    WidgetTester tester, {
    String buildId = '',
    String buildSecret = '',
  }) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    jira = JiraController(
      store: store,
      oauth: JiraOAuth(openBrowser: (_) async => false),
      api: JiraApi(),
      defaultClientId: buildId,
      defaultClientSecret: buildSecret,
    );
    await jira.load();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showJiraDialog(context, jira, projects),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  /// El botón "Cerrar" del pie (texto exacto: "Cerrar sesión" es otro botón).
  Finder closeButton() => find.widgetWithText(TextButton, 'Cerrar');

  Future<void> expectClosable(WidgetTester tester) async {
    expect(closeButton(), findsOneWidget, reason: 'falta el botón Cerrar');
    expect(tester.widget<TextButton>(closeButton()).onPressed, isNotNull);
    await tester.tap(closeButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'Cerrar no cerró el diálogo');
  }

  testWidgets('sin credenciales (primer uso) hay botón Cerrar', (tester) async {
    await openDialog(tester);
    expect(find.text('Guardar'), findsOneWidget);
    await expectClosable(tester);
  });

  testWidgets('con credenciales y sin sesión hay botón Cerrar', (tester) async {
    store.data['jira_client_id'] = 'cid';
    store.data['jira_client_secret'] = 'sec';
    await openDialog(tester);

    expect(find.text('Iniciar sesión'), findsOneWidget);
    await expectClosable(tester);
  });

  testWidgets('con la sesión iniciada hay botón Cerrar', (tester) async {
    await signedInStore();
    await openDialog(tester);

    expect(find.text('Sincronizar'), findsOneWidget);
    await expectClosable(tester);
  });

  testWidgets('editando las credenciales hay botón Cerrar además de Cancelar y Guardar',
      (tester) async {
    await signedInStore();
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Credenciales'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    await expectClosable(tester);
  });

  testWidgets('Cerrar es el primer botón del pie, antes de la acción principal', (tester) async {
    await signedInStore();
    await openDialog(tester);

    final close = tester.getTopLeft(closeButton());
    final primary = tester.getTopLeft(find.widgetWithText(FilledButton, 'Sincronizar'));
    expect(close.dx, lessThan(primary.dx));
  });

  testWidgets('las acciones poco frecuentes van en el cuerpo, no entre los botones del pie',
      (tester) async {
    await signedInStore();
    await openDialog(tester);

    final actions = tester.widget<AlertDialog>(find.byType(AlertDialog)).actions!;
    // Pie: solo "Cerrar" y la acción principal (no 4 botones apretados).
    expect(actions.length, 2);
    expect(find.widgetWithText(TextButton, 'Credenciales'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cerrar sesión'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en la ventana mínima no se desborda', (tester) async {
    await signedInStore();
    await openDialog(tester);
    tester.view.physicalSize = const Size(360, 242);
    await tester.pumpAndSettle();

    expect(closeButton(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('credenciales: .env compilado o formulario', () {
    testWidgets('con .env completo no se ofrece escribirlas ni cambiarlas', (tester) async {
      await openDialog(tester, buildId: 'id-env', buildSecret: 'sec-env');

      expect(find.text('Client ID'), findsNothing);
      expect(find.text('Client Secret'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Credenciales'), findsNothing);
      expect(find.textContaining('vienen incluidas en esta compilación'), findsOneWidget);
      // directo a lo que importa: iniciar sesión, y siempre se puede cerrar
      expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
      expect(closeButton(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con .env completo y la sesión iniciada solo queda "Cerrar sesión"',
        (tester) async {
      await signedInStore();
      await openDialog(tester, buildId: 'cid', buildSecret: 'sec');

      expect(find.widgetWithText(TextButton, 'Credenciales'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Cerrar sesión'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sincronizar'), findsOneWidget);
    });

    testWidgets('sin .env se muestra el formulario y dice dónde se guarda', (tester) async {
      await openDialog(tester);

      expect(find.text('Client ID'), findsOneWidget);
      expect(find.text('Client Secret'), findsOneWidget);
      expect(find.textContaining('almacén seguro del sistema operativo'), findsOneWidget);
      expect(find.textContaining('vienen incluidas'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
    });

    testWidgets('lo que se escribe en el formulario va al almacén seguro y abre el inicio de sesión',
        (tester) async {
      await openDialog(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Client ID'), 'mi-id');
      await tester.enterText(find.widgetWithText(TextField, 'Client Secret'), 'mi-secreto');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(store.data['jira_client_id'], 'mi-id');
      expect(store.data['jira_client_secret'], 'mi-secreto');
      // el formulario desaparece y ya se puede iniciar sesión
      expect(find.text('Client ID'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
    });

    testWidgets('sin .env y con credenciales guardadas sí se ofrece cambiarlas', (tester) async {
      store.data['jira_client_id'] = 'cid';
      store.data['jira_client_secret'] = 'sec';
      await openDialog(tester);

      expect(find.widgetWithText(TextButton, 'Credenciales'), findsOneWidget);
      expect(find.textContaining('vienen incluidas'), findsNothing);
    });

    testWidgets('un .env incompleto (solo el ID) muestra el formulario con el ID ya puesto',
        (tester) async {
      await openDialog(tester, buildId: 'id-env');

      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Client ID'));
      expect(field.controller!.text, 'id-env');
      expect(find.text('Client Secret'), findsOneWidget);
    });
  });
}
