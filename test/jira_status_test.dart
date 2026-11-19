import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/errors/jira_exceptions.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const testPort = 53692;
const site = JiraSite(id: 'cloud-1', name: 'Acme', url: 'https://acme.atlassian.net');

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> issue(String key,
        {String? status,
        String? category,
        String summary = 's',
        Map<String, Object?>? tracking}) =>
    {
      'key': key,
      'fields': {
        'summary': summary,
        'issuetype': {'subtask': false},
        if (status != null)
          'status': {
            'name': status,
            if (category != null) 'statusCategory': {'key': category},
          },
        'timetracking': ?tracking,
      },
    };

void main() {
  group('JiraApi: estado de los issues', () {
    test('assignedToMe lee el nombre y la categoría del estado', () async {
      late Uri sent;
      final api = JiraApi(client: MockClient((req) async {
        sent = req.url;
        return json({
          'issues': [
            issue('A-1', status: 'En curso', category: 'indeterminate'),
            issue('A-2'), // sin estado
          ],
          'isLast': true,
        });
      }));
      final issues = await api.assignedToMe(accessToken: 't', site: site);

      expect(sent.queryParameters['fields'], contains('status'));
      expect(issues[0].status, 'En curso');
      expect(issues[0].statusCategory, 'indeterminate');
      expect(issues[1].status, isNull);
      expect(issues[0].toProject().jiraStatus, 'En curso');
      expect(issues[0].toProject().jiraStatusCategory, 'indeterminate');
    });

    test('liveInfoFor consulta por clave y devuelve el estado de cada una', () async {
      late Uri sent;
      final api = JiraApi(client: MockClient((req) async {
        sent = req.url;
        return json({
          'issues': [
            issue('A-1', status: 'Listo', category: 'done'),
            issue('B-2', status: 'Por hacer', category: 'new'),
          ],
        });
      }));
      final r = await api.liveInfoFor(accessToken: 't', site: site, keys: ['A-1', 'B-2']);

      expect(sent.queryParameters['jql'], 'key in (A-1,B-2)');
      expect(sent.queryParameters['fields'], 'status,timetracking');
      expect(r['A-1']!.status, 'Listo');
      expect(r['A-1']!.category, 'done');
      expect(r['B-2']!.status, 'Por hacer');
      expect(r['B-2']!.category, 'new');
      expect(r['A-1']!.estimateSeconds, isNull); // sin seguimiento de tiempo
    });

    test('assignedToMe lee el seguimiento de tiempo (en segundos)', () async {
      late Uri sent;
      final api = JiraApi(client: MockClient((req) async {
        sent = req.url;
        return json({
          'issues': [
            issue('A-1', status: 'En curso', category: 'indeterminate', tracking: {
              'originalEstimate': '3h',
              'originalEstimateSeconds': 10800,
              'remainingEstimateSeconds': 3600,
              'timeSpentSeconds': 7200,
            }),
            // Solo hay tiempo registrado: sin estimación ni restante.
            issue('A-2', status: 'En curso', tracking: {'timeSpentSeconds': 900}),
            // Seguimiento de tiempo desactivado: no existe el campo.
            issue('A-3', status: 'En curso'),
          ],
          'isLast': true,
        });
      }));
      final issues = await api.assignedToMe(accessToken: 't', site: site);

      expect(sent.queryParameters['fields'], contains('timetracking'));
      expect(issues[0].estimateSeconds, 10800);
      expect(issues[0].remainingSeconds, 3600);
      expect(issues[0].spentSeconds, 7200);
      expect(issues[1].estimateSeconds, isNull); // null, no 0
      expect(issues[1].remainingSeconds, isNull);
      expect(issues[1].spentSeconds, 900);
      expect(issues[2].estimateSeconds, isNull);
      expect(issues[2].spentSeconds, isNull);

      final p = issues[0].toProject();
      expect(p.jiraEstimateSeconds, 10800);
      expect(p.jiraRemainingSeconds, 3600);
      expect(p.jiraSpentSeconds, 7200);
      expect(p.hasJiraTracking, isTrue);
      expect(issues[2].toProject().hasJiraTracking, isFalse);
    });

    test('liveInfoFor devuelve también el seguimiento de tiempo', () async {
      final api = JiraApi(client: MockClient((_) async => json({
            'issues': [
              issue('A-1', status: 'Listo', category: 'done', tracking: {
                'originalEstimateSeconds': 3600,
                'remainingEstimateSeconds': 0,
                'timeSpentSeconds': 5400,
              }),
            ],
          })));
      final r = await api.liveInfoFor(accessToken: 't', site: site, keys: ['A-1']);

      expect(r['A-1']!.estimateSeconds, 3600);
      expect(r['A-1']!.remainingSeconds, 0); // 0 informado es distinto de null
      expect(r['A-1']!.spentSeconds, 5400);
    });

    test('liveInfoFor descarta claves que no parecen de Jira (no se arma JQL con texto libre)',
        () async {
      final jqls = <String>[];
      final api = JiraApi(client: MockClient((req) async {
        jqls.add(req.url.queryParameters['jql']!);
        return json({'issues': []});
      }));
      await api.liveInfoFor(
        accessToken: 't',
        site: site,
        keys: ['A-1', 'A-1) OR (project = X', 'sin guion', ''],
      );
      expect(jqls, ['key in (A-1)']);
    });

    test('liveInfoFor parte las consultas en grupos de 50', () async {
      final sizes = <int>[];
      final api = JiraApi(client: MockClient((req) async {
        final jql = req.url.queryParameters['jql']!;
        sizes.add(RegExp(r'\(([^)]*)\)').firstMatch(jql)!.group(1)!.split(',').length);
        return json({'issues': []});
      }));
      await api.liveInfoFor(
        accessToken: 't',
        site: site,
        keys: [for (var i = 1; i <= 120; i++) 'A-$i'],
      );
      expect(sizes, [50, 50, 20]);
    });

    test('una clave inexistente (400) se aísla y no impide ver las demás', () async {
      final api = JiraApi(client: MockClient((req) async {
        final jql = req.url.queryParameters['jql']!;
        if (jql.contains('A-3')) return json({'errorMessages': ['no existe']}, 400);
        final keys = RegExp(r'[A-Z]-\d+').allMatches(jql).map((m) => m.group(0)!);
        return json({
          'issues': [for (final k in keys) issue(k, status: 'Listo', category: 'done')],
        });
      }));
      final r = await api.liveInfoFor(
          accessToken: 't', site: site, keys: ['A-1', 'A-2', 'A-3', 'A-4']);
      expect(r.keys.toSet(), {'A-1', 'A-2', 'A-4'});
    });

    test('401 → JiraUnauthorized; otros errores incluyen el código HTTP', () async {
      final unauthorized =
          JiraApi(client: MockClient((_) async => json({}, 401)));
      expect(unauthorized.liveInfoFor(accessToken: 't', site: site, keys: ['A-1']),
          throwsA(isA<JiraUnauthorized>()));

      final broken = JiraApi(client: MockClient((_) async => json({}, 500)));
      expect(
          broken.liveInfoFor(accessToken: 't', site: site, keys: ['A-1']),
          throwsA(isA<JiraApiException>().having((e) => e.statusCode, 'statusCode', 500)));
    });
  });

  group('base de datos', () {
    test('migración v3 → versión actual conserva los datos y deja lo de Jira vacío', () async {
      sqfliteFfiInit();
      final dir = Directory.systemTemp.createTempSync('gestion_time_mig4');
      final file = '${dir.path}${Platform.pathSeparator}v3.db';
      try {
        final old = await databaseFactoryFfi.openDatabase(
          file,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, _) async {
              await db.execute('''
                CREATE TABLE projects (
                  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                  description TEXT NOT NULL DEFAULT '', link TEXT NOT NULL DEFAULT '',
                  accumulated_ms INTEGER NOT NULL DEFAULT 0, started_at_ms INTEGER,
                  jira_key TEXT, jira_logged_ms INTEGER NOT NULL DEFAULT 0)''');
              await db.execute(
                  'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
              await db.insert('projects', {
                'name': 'viejo',
                'accumulated_ms': 7000,
                'jira_key': 'K-1',
                'jira_logged_ms': 3000,
              });
            },
          ),
        );
        await old.close();

        final db = await AppDatabase.open(path: file);
        final row = (await db.projects()).single;
        expect(row.name, 'viejo');
        expect(row.accumulatedMs, 7000);
        expect(row.jiraLoggedMs, 3000);
        expect(row.jiraStatus, isNull);
        expect(row.jiraStatusCategory, isNull);
        expect(row.jiraEstimateSeconds, isNull);
        expect(row.jiraRemainingSeconds, isNull);
        expect(row.jiraSpentSeconds, isNull);
        await db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('al re-sincronizar se actualiza el estado sin tocar el tiempo medido', () async {
      final db = await AppDatabase.open(path: inMemoryDatabasePath);
      final c = ProjectsController(ProjectsRepositoryImpl(db));
      await c.load();
      await c.importJira([
        const JiraIssue(
                key: 'K-1', summary: 'a', description: '', url: 'u',
                status: 'Por hacer', statusCategory: 'new')
            .toProject()
      ]);
      await db.update(c.projects.single.copyWith(accumulatedMs: 5000));
      await c.load();

      await c.importJira([
        const JiraIssue(
                key: 'K-1', summary: 'a', description: '', url: 'u',
                status: 'En curso', statusCategory: 'indeterminate')
            .toProject()
      ]);

      final p = c.projects.single;
      expect(p.jiraStatus, 'En curso');
      expect(p.jiraStatusCategory, 'indeterminate');
      expect(p.accumulatedMs, 5000);
      c.dispose();
      await db.close();
    });
  });

  group('JiraController.sync', () {
    late AppDatabase db;
    late ProjectsController projects;
    late MemorySecretStore store;
    late List<String> assigned; // claves que devuelve la búsqueda "asignados a mí"
    late Map<String, (String, String)> statuses; // lo que dice Jira de cada clave
    late int statusReplyCode;
    late int statusCalls;
    late Map<String, Map<String, Object?>> tracking; // seguimiento de tiempo por clave

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      projects = ProjectsController(ProjectsRepositoryImpl(db));
      await projects.load();
      store = MemorySecretStore();
      statusReplyCode = 200;
      statusCalls = 0;
      tracking = {};
    });

    tearDown(() async {
      projects.dispose();
      await db.close();
    });

    JiraController build() {
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/oauth/token') {
          return json({
            'access_token': 'a',
            'refresh_token': 'r',
            'expires_in': 3600,
            'scope': 'read:jira-work write:jira-work offline_access',
          });
        }
        if (path == '/oauth/token/accessible-resources') {
          return json([
            {'id': site.id, 'name': site.name, 'url': site.url}
          ]);
        }
        final jql = req.url.queryParameters['jql']!;
        if (jql.startsWith('assignee')) {
          return json({
            'issues': [
              for (final k in assigned)
                issue(k, status: statuses[k]!.$1, category: statuses[k]!.$2, tracking: tracking[k]),
            ],
            'isLast': true,
          });
        }
        statusCalls++;
        if (statusReplyCode != 200) return json({}, statusReplyCode);
        final keys = RegExp(r'[A-Z]-\d+').allMatches(jql).map((m) => m.group(0)!);
        return json({
          'issues': [
            for (final k in keys)
              if (statuses.containsKey(k))
                issue(k, status: statuses[k]!.$1, category: statuses[k]!.$2, tracking: tracking[k]),
          ],
        });
      });
      return JiraController(
        store: store,
        oauth: JiraOAuth(
          port: testPort,
          client: mock,
          openBrowser: (url) async {
            final c = HttpClient();
            final r = await (await c.getUrl(Uri.parse(
                    'http://localhost:$testPort/callback?code=C&state=${url.queryParameters['state']}')))
                .close();
            await r.drain<void>();
            c.close();
            return true;
          },
        ),
        api: JiraApi(client: mock),
      );
    }

    Future<JiraController> signedIn() async {
      final jira = build();
      await jira.saveCredentials('cid', 'sec');
      await jira.signIn();
      expect(jira.error, isNull);
      return jira;
    }

    Project byKey(String k) => projects.projects.firstWhere((p) => p.jiraKey == k);

    test('importa el estado de cada ticket', () async {
      assigned = ['A-1', 'A-2'];
      statuses = {
        'A-1': ('En curso', 'indeterminate'),
        'A-2': ('Por hacer', 'new'),
      };
      final jira = await signedIn();

      await jira.sync(projects);

      expect(jira.error, isNull);
      expect(byKey('A-1').jiraStatus, 'En curso');
      expect(byKey('A-1').jiraStatusCategory, 'indeterminate');
      expect(byKey('A-2').jiraStatus, 'Por hacer');
      expect(statusCalls, 0); // nadie quedó fuera: no hace falta la 2.ª consulta
    });

    test('refresca el estado de un ticket ya importado que dejó de aparecer (terminó)',
        () async {
      assigned = ['A-1', 'A-2'];
      statuses = {
        'A-1': ('En curso', 'indeterminate'),
        'A-2': ('Por hacer', 'new'),
      };
      final jira = await signedIn();
      await jira.sync(projects);
      await db.update(byKey('A-1').copyWith(accumulatedMs: 9000));
      await projects.load();

      // A-1 pasa a "Listo": la búsqueda de pendientes ya no lo devuelve.
      assigned = ['A-2'];
      statuses['A-1'] = ('Listo', 'done');
      await jira.sync(projects);

      expect(jira.error, isNull);
      expect(statusCalls, 1);
      expect(byKey('A-1').jiraStatus, 'Listo');
      expect(byKey('A-1').jiraStatusCategory, 'done');
      expect(byKey('A-1').accumulatedMs, 9000); // el tiempo no se toca
      expect(projects.projects.length, 2); // y no se borra
      expect(jira.message, contains('1 ticket refrescado'));
    });

    test('importa el seguimiento de tiempo y lo refresca en los que ya no aparecen',
        () async {
      assigned = ['A-1', 'A-2'];
      statuses = {
        'A-1': ('En curso', 'indeterminate'),
        'A-2': ('En curso', 'indeterminate'),
      };
      tracking = {
        'A-1': {'originalEstimateSeconds': 7200, 'remainingEstimateSeconds': 7200},
        'A-2': {'timeSpentSeconds': 600},
      };
      final jira = await signedIn();
      await jira.sync(projects);

      expect(byKey('A-1').jiraEstimateSeconds, 7200);
      expect(byKey('A-1').jiraRemainingSeconds, 7200);
      expect(byKey('A-1').jiraSpentSeconds, isNull);
      expect(byKey('A-2').jiraSpentSeconds, 600);
      expect(byKey('A-2').jiraEstimateSeconds, isNull);

      // A-1 se termina y Jira le registra tiempo; ya no viene en "mis pendientes".
      assigned = ['A-2'];
      statuses['A-1'] = ('Listo', 'done');
      tracking['A-1'] = {
        'originalEstimateSeconds': 7200,
        'remainingEstimateSeconds': 0,
        'timeSpentSeconds': 8100,
      };
      await jira.sync(projects);

      expect(byKey('A-1').jiraStatus, 'Listo');
      expect(byKey('A-1').jiraSpentSeconds, 8100);
      expect(byKey('A-1').jiraRemainingSeconds, 0);

      // Si Jira deja de informar el seguimiento (p. ej. se desactiva), se borra.
      tracking.remove('A-1');
      await jira.sync(projects);
      expect(byKey('A-1').jiraEstimateSeconds, isNull);
      expect(byKey('A-1').jiraSpentSeconds, isNull);
      expect(byKey('A-1').jiraStatus, 'Listo');
    });

    test('si falla el refresco de estados, lo importado se conserva y se avisa', () async {
      assigned = ['A-1'];
      statuses = {'A-1': ('En curso', 'indeterminate')};
      final jira = await signedIn();
      await jira.sync(projects);

      assigned = ['A-2'];
      statuses['A-2'] = ('Por hacer', 'new');
      statusReplyCode = 500;
      await jira.sync(projects);

      expect(jira.error, isNull);
      expect(jira.message, contains('No se pudo refrescar'));
      expect(byKey('A-2').jiraStatus, 'Por hacer'); // lo nuevo sí se importó
      expect(byKey('A-1').jiraStatus, 'En curso'); // lo viejo queda como estaba
    });

    test('las entradas manuales no disparan la consulta de estados', () async {
      assigned = ['A-1'];
      statuses = {'A-1': ('En curso', 'indeterminate')};
      final jira = await signedIn();
      await projects.add('Reunión', '', '');

      await jira.sync(projects);

      expect(statusCalls, 0);
      expect(projects.projects.firstWhere((p) => p.jiraKey == null).jiraStatus, isNull);
    });
  });
}
