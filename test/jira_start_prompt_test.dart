import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/usecases/in_progress_rules.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

// Sin servidor OAuth (la sesión se precarga): puede mezclar pruebas puras y de widgets.
const site = JiraSite(id: 'cloud-1', name: 'Acme', url: 'https://acme.atlassian.net');

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> transition(String id, String to, String category) => {
  'id': id,
  'name': 'Ir a $to',
  'to': {
    'name': to,
    'statusCategory': {'key': category},
  },
};

void main() {
  group('reglas', () {
    const offer = ShouldOfferInProgress();

    test('se ofrece en Backlog y Selected for Development (sin importar mayúsculas)', () {
      for (final s in ['Backlog', 'BACKLOG', 'Selected for Development', ' selected for development ']) {
        expect(offer(Project(name: 'x', jiraKey: 'A-1', jiraStatus: s)), isTrue, reason: s);
      }
      expect(offer(const Project(name: 'x', jiraKey: 'A-1', jiraStatus: 'Seleccionado para desarrollo')), isTrue);
    });

    test('no se ofrece en otros estados, sin estado ni en tickets manuales', () {
      for (final s in ['En curso', 'In Progress', 'Por hacer', 'Listo']) {
        expect(offer(Project(name: 'x', jiraKey: 'A-1', jiraStatus: s)), isFalse, reason: s);
      }
      expect(offer(const Project(name: 'x', jiraKey: 'A-1')), isFalse);
      expect(offer(const Project(name: 'x', jiraStatus: 'Backlog')), isFalse);
    });

    JiraTransition t(String id, String to, String? cat) =>
        JiraTransition(id: id, name: to, toStatus: to, toCategory: cat);

    test('elige el «en curso» correcto o ninguno si es ambiguo', () {
      const pick = PickInProgressTransition();
      expect(pick([t('1', 'Backlog', 'new'), t('2', 'In Progress', 'indeterminate')])!.id, '2');
      expect(pick([t('1', 'En revisión', 'indeterminate'), t('2', 'En curso', 'indeterminate')])!.id, '2');
      expect(pick([t('1', 'Desarrollando', 'indeterminate')])!.id, '1'); // el único
      expect(pick([t('1', 'Revisión', 'indeterminate'), t('2', 'QA', 'indeterminate')]), isNull);
      expect(pick([t('1', 'Listo', 'done')]), isNull);
      expect(pick([]), isNull);
    });
  });

  group('al pulsar play', () {
    late FakeProjectsRepository repo;
    late ProjectsController projects;
    late List<http.Request> posts;
    var transitions = <Map<String, Object?>>[];
    var postStatus = 204;

    JiraController build({bool signedIn = true}) {
      final store = MemorySecretStore();
      if (signedIn) {
        store.data['jira_client_id'] = 'cid';
        store.data['jira_client_secret'] = 'sec';
        store.data['jira_session'] = JiraSessionModel.toJson(JiraSession(
          tokens: TokenSet(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            scope: 'read:jira-work write:jira-work',
          ),
          sites: const [site],
          siteId: site.id,
        ));
      }
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/transitions')) {
          if (req.method == 'GET') return json({'transitions': transitions});
          posts.add(req);
          return http.Response('', postStatus);
        }
        // relectura del ticket tras cambiar el estado
        return json({
          'issues': [
            {
              'key': 'A-1',
              'fields': {
                'summary': 's',
                'status': {
                  'name': 'In Progress',
                  'statusCategory': {'key': 'indeterminate'},
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

    void uiTest(
      String name,
      Future<void> Function(WidgetTester tester, JiraController jira) body, {
      String status = 'Backlog',
      bool signedIn = true,
    }) {
      testWidgets(name, (tester) async {
        posts = [];
        postStatus = 204;
        transitions = [transition('21', 'In Progress', 'indeterminate'), transition('31', 'Done', 'done')];
        repo = FakeProjectsRepository();
        await repo.insert(Project(
          name: 'A-1 cosa',
          jiraKey: 'A-1',
          jiraStatus: status,
          jiraStatusCategory: status == 'Backlog' ? 'new' : 'indeterminate',
        ));
        projects = ProjectsController(repo);
        await projects.load();
        final jira = build(signedIn: signedIn);
        await tester.runAsync(jira.load);

        tester.view.physicalSize = const Size(700, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        // `showFittedDialog` consulta el tamaño de la ventana nativa: aquí no existe.
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'getBounds'
              ? {'x': 0.0, 'y': 0.0, 'width': 700.0, 'height': 3000.0}
              : null,
        );
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('window_manager'), null));

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ProjectTile(project: projects.projects.single, controller: projects, jira: jira),
          ),
        ));
        try {
          await body(tester, jira);
        } finally {
          await tester.pumpWidget(const SizedBox());
          projects.dispose();
        }
      }, );
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }

    uiTest('«Poner en curso» inicia el cronómetro y cambia el estado en Jira', (tester, jira) async {
      await tester.tap(find.byTooltip('Iniciar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Poner el ticket en curso?'), findsOneWidget);
      expect(projects.projects.single.isRunning, isFalse); // aún no

      await tester.tap(find.text('Poner en curso'));
      await settle(tester);

      expect(projects.projects.single.isRunning, isTrue);
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body), {
        'transition': {'id': '21'},
      });
      expect(projects.projects.single.jiraStatus, 'In Progress');
      expect(find.textContaining('estado cambiado a In Progress'), findsOneWidget);
    });

    uiTest('«Solo iniciar» arranca el cronómetro sin tocar Jira', (tester, jira) async {
      await tester.tap(find.byTooltip('Iniciar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solo iniciar'));
      await settle(tester);

      expect(projects.projects.single.isRunning, isTrue);
      expect(posts, isEmpty);
      expect(projects.projects.single.jiraStatus, 'Backlog');
    });

    uiTest('«Cancelar» no inicia nada', (tester, jira) async {
      await tester.tap(find.byTooltip('Iniciar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await settle(tester);

      expect(projects.projects.single.isRunning, isFalse);
      expect(posts, isEmpty);
    });

    uiTest('si Jira rechaza el cambio, el cronómetro corre igual y se avisa', (tester, jira) async {
      postStatus = 400;
      await tester.tap(find.byTooltip('Iniciar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poner en curso'));
      await settle(tester);

      expect(projects.projects.single.isRunning, isTrue);
      expect(projects.projects.single.jiraStatus, 'Backlog');
      expect(find.textContaining('pero no se pudo cambiar el estado'), findsOneWidget);
    });

    uiTest('un ticket que ya está en curso inicia sin preguntar', (tester, jira) async {
      await tester.tap(find.byTooltip('Iniciar'));
      await settle(tester);

      expect(find.text('¿Poner el ticket en curso?'), findsNothing);
      expect(projects.projects.single.isRunning, isTrue);
    }, status: 'In Progress');

    uiTest('sin sesión de Jira inicia sin preguntar', (tester, jira) async {
      await tester.tap(find.byTooltip('Iniciar'));
      await settle(tester);

      expect(find.text('¿Poner el ticket en curso?'), findsNothing);
      expect(projects.projects.single.isRunning, isTrue);
    }, signedIn: false);
  });
}
