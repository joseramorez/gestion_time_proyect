import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/errors/jira_exceptions.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_status_menu.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

// Sin servidor OAuth: la sesión se precarga en un almacén en memoria, así que este archivo
// puede mezclar pruebas de API, de controlador y de widgets.
const site = JiraSite(id: 'cloud-1', name: 'Acme', url: 'https://acme.atlassian.net');

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

final transitionsBody = {
  'transitions': [
    {
      'id': '11',
      'name': 'Empezar',
      'to': {
        'name': 'En curso',
        'statusCategory': {'key': 'indeterminate'},
      },
    },
    {
      'id': '31',
      'name': 'Terminar',
      'to': {
        'name': 'Listo',
        'statusCategory': {'key': 'done'},
      },
    },
  ],
};

void main() {
  group('JiraApi: transiciones', () {
    test('transitionsFor lee id, estado destino y categoría', () async {
      late Uri sent;
      final api = JiraApi(client: MockClient((req) async {
        sent = req.url;
        return json(transitionsBody);
      }));
      final list = await api.transitionsFor(accessToken: 't', site: site, issueKey: 'A-1');

      expect(sent.path, '/ex/jira/cloud-1/rest/api/3/issue/A-1/transitions');
      expect(list.map((t) => (t.id, t.toStatus, t.toCategory)), [
        ('11', 'En curso', 'indeterminate'),
        ('31', 'Listo', 'done'),
      ]);
    });

    test('transition envía el id elegido y acepta 204', () async {
      late http.Request sent;
      final api = JiraApi(client: MockClient((req) async {
        sent = req;
        return http.Response('', 204);
      }));
      await api.transition(accessToken: 't', site: site, issueKey: 'A-1', transitionId: '31');

      expect(sent.method, 'POST');
      expect(sent.url.path, '/ex/jira/cloud-1/rest/api/3/issue/A-1/transitions');
      expect(jsonDecode(sent.body), {
        'transition': {'id': '31'},
      });
    });

    Future<Object?> failWith(int status, [Object body = const {}]) async {
      final api = JiraApi(client: MockClient((_) async => json(body, status)));
      try {
        await api.transition(accessToken: 't', site: site, issueKey: 'A-1', transitionId: '1');
        return null;
      } catch (e) {
        return e;
      }
    }

    test('401 pide refrescar el token; 403/404/400 dan un mensaje claro', () async {
      expect(await failWith(401), isA<JiraUnauthorized>());
      expect(((await failWith(403)) as JiraApiException).message, contains('permiso'));
      expect(((await failWith(404)) as JiraApiException).message, contains('no existe'));
      final bad = await failWith(400, {
        'errorMessages': ['Campo obligatorio'],
      }) as JiraApiException;
      expect(bad.message, contains('datos adicionales'));
      expect(bad.message, contains('Campo obligatorio'));
    });
  });

  group('JiraController: cambiar el estado', () {
    late ProjectsController projects;
    late FakeProjectsRepository repo;
    late MemorySecretStore store;
    late List<http.Request> calls;
    var postStatus = 204;
    var liveStatus = 'Listo';
    var liveFails = false;

    JiraController build({String scope = 'read:jira-work write:jira-work'}) {
      store = MemorySecretStore();
      store.data['jira_client_id'] = 'cid';
      store.data['jira_client_secret'] = 'sec';
      store.data['jira_session'] = JiraSessionModel.toJson(JiraSession(
        tokens: TokenSet(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scope: scope,
        ),
        sites: const [site],
        siteId: site.id,
      ));
      final mock = MockClient((req) async {
        calls.add(req);
        if (req.url.path.endsWith('/transitions')) {
          return req.method == 'GET' ? json(transitionsBody) : http.Response('', postStatus);
        }
        // relectura del ticket (search/jql)
        if (liveFails) return json({'errorMessages': ['boom']}, 500);
        return json({
          'issues': [
            {
              'key': 'A-1',
              'fields': {
                'summary': 's',
                'timetracking': {'originalEstimateSeconds': 3600},
                'status': {
                  'name': liveStatus,
                  'statusCategory': {'key': 'done'},
                },
              },
            },
          ],
          'isLast': true,
        });
      });
      return JiraController(
        store: store,
        oauth: JiraOAuth(openBrowser: (_) async => false),
        api: JiraApi(client: mock),
      );
    }

    setUp(() async {
      calls = [];
      postStatus = 204;
      liveStatus = 'Listo';
      liveFails = false;
      repo = FakeProjectsRepository();
      await repo.insert(const Project(
        name: 'A-1 cosa',
        jiraKey: 'A-1',
        jiraStatus: 'Por hacer',
        jiraStatusCategory: 'new',
        jiraEstimateSeconds: 3600,
      ));
      projects = ProjectsController(repo);
      await projects.load();
    });

    tearDown(() => projects.dispose());

    const done = JiraTransition(id: '31', name: 'Terminar', toStatus: 'Listo', toCategory: 'done');

    test('si Jira acepta, el estado guardado cambia y se conserva el seguimiento', () async {
      final jira = build();
      await jira.load();
      final error = await jira.changeStatus(projects.projects.single, done, projects);

      expect(error, isNull);
      final p = projects.projects.single;
      expect(p.jiraStatus, 'Listo');
      expect(p.jiraStatusCategory, 'done');
      expect(p.jiraEstimateSeconds, 3600);
      expect(calls.any((c) => c.method == 'POST' && c.url.path.endsWith('/transitions')), isTrue);
    });

    test('si la relectura falla, el estado nuevo igual se guarda y el seguimiento no se pierde', () async {
      liveFails = true;
      final jira = build();
      await jira.load();
      expect(await jira.changeStatus(projects.projects.single, done, projects), isNull);

      final p = projects.projects.single;
      expect(p.jiraStatus, 'Listo');
      expect(p.jiraEstimateSeconds, 3600); // lo que ya había, no null ni 0
    });

    test('si Jira rechaza, NO cambia nada localmente', () async {
      postStatus = 400;
      final jira = build();
      await jira.load();
      final error = await jira.changeStatus(projects.projects.single, done, projects);

      expect(error, contains('datos adicionales'));
      expect(projects.projects.single.jiraStatus, 'Por hacer');
    });

    test('sin sesión o con sesión de solo lectura no llama a Jira', () async {
      final readOnly = build(scope: 'read:jira-work');
      await readOnly.load();
      expect(await readOnly.changeStatus(projects.projects.single, done, projects),
          contains('permiso de escritura'));
      final res = await readOnly.transitionsFor(projects.projects.single);
      expect(res.error, contains('permiso de escritura'));
      expect(calls, isEmpty);

      final none = build();
      store.data.remove('jira_session');
      await none.load();
      expect(await none.changeStatus(projects.projects.single, done, projects),
          contains('Inicia sesión'));
    });

    testWidgets('tocar un estado del menú lo cambia y cierra el menú', (tester) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // `showFittedDialog` consulta el tamaño de la ventana nativa: aquí no existe.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'getBounds'
            ? {'x': 0.0, 'y': 0.0, 'width': 700.0, 'height': 2000.0}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), null));
      final jira = build();
      await tester.runAsync(jira.load);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showJiraStatusMenu(context, jira, projects, projects.projects.single),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      // un menú desplegable (no un diálogo) con los dos destinos del flujo
      expect(find.widgetWithText(JiraStatusChip, 'En curso'), findsOneWidget);
      expect(find.widgetWithText(JiraStatusChip, 'Listo'), findsOneWidget);
      // el estado vigente aparece marcado con un check
      expect(find.widgetWithText(JiraStatusChip, 'Por hacer'), findsOneWidget);
      expect(find.byIcon(AppIcons.current), findsOneWidget);

      await tester.tap(find.widgetWithText(JiraStatusChip, 'Listo'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(projects.projects.single.jiraStatus, 'Listo');
      expect(find.widgetWithText(JiraStatusChip, 'En curso'), findsNothing);
      expect(find.textContaining('estado cambiado a Listo'), findsOneWidget);
    });
  });
}
