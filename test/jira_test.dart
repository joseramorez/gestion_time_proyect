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
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const testPort = 53690;
const testRedirect = 'http://localhost:$testPort/callback';

const site = JiraSite(id: 'cloud-1', name: 'Acme', url: 'https://acme.atlassian.net');

Map<String, Object?> issue(String key, String summary,
        {String? parent, Object? description}) =>
    {
      'key': key,
      'fields': {
        'summary': summary,
        'description': description,
        'issuetype': {'subtask': parent != null},
        if (parent != null) 'parent': {'key': parent},
      },
    };

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('adfToText', () {
    test('convierte párrafos, listas y menciones', () {
      final adf = {
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {'type': 'text', 'text': 'Hola '},
              {'type': 'mention', 'attrs': {'text': '@ana'}},
            ],
          },
          {
            'type': 'bulletList',
            'content': [
              {
                'type': 'listItem',
                'content': [
                  {'type': 'paragraph', 'content': [{'type': 'text', 'text': 'uno'}]},
                ],
              },
              {
                'type': 'listItem',
                'content': [
                  {'type': 'paragraph', 'content': [{'type': 'text', 'text': 'dos'}]},
                ],
              },
            ],
          },
        ],
      };
      expect(adfToText(adf), 'Hola @ana\n• uno\n• dos');
    });

    test('null y texto plano', () {
      expect(adfToText(null), '');
      expect(adfToText(' hola '), 'hola');
    });
  });

  group('JiraApi', () {
    test('pagina, usa el token y distingue subtareas', () async {
      final requests = <Uri>[];
      final api = JiraApi(client: MockClient((req) async {
        requests.add(req.url);
        expect(req.headers['Authorization'], 'Bearer tok');
        if (req.url.queryParameters['nextPageToken'] == null) {
          return json({
            'issues': [issue('A-1', 'Tarea')],
            'nextPageToken': 'p2',
            'isLast': false,
          });
        }
        return json({
          'issues': [issue('A-2', 'Sub', parent: 'A-1')],
          'isLast': true,
        });
      }));

      final issues = await api.assignedToMe(accessToken: 'tok', site: site);

      expect(issues.map((i) => i.key), ['A-1', 'A-2']);
      expect(issues[1].isSubtask, isTrue);
      expect(issues[1].parentKey, 'A-1');
      expect(issues[0].url, 'https://acme.atlassian.net/browse/A-1');
      expect(requests.first.path, '/ex/jira/cloud-1/rest/api/3/search/jql');
      expect(requests.first.queryParameters['jql'], contains('currentUser()'));
    });

    test('401 lanza JiraUnauthorized', () async {
      final api = JiraApi(client: MockClient((_) async => json({}, 401)));
      expect(api.assignedToMe(accessToken: 't', site: site),
          throwsA(isA<JiraUnauthorized>()));
    });

    test('otros errores incluyen el mensaje de Jira', () async {
      final api = JiraApi(
          client: MockClient((_) async => json({'errorMessages': ['JQL mala']}, 400)));
      expect(
          api.assignedToMe(accessToken: 't', site: site),
          throwsA(isA<JiraApiException>()
              .having((e) => e.message, 'message', contains('JQL mala'))));
    });
  });

  group('JiraOAuth', () {
    test('authorizeUri lleva audience, scope, callback y state', () {
      final u = JiraOAuth.authorizeUri('cid', 'st');
      expect(u.host, 'auth.atlassian.com');
      expect(u.queryParameters['audience'], 'api.atlassian.com');
      expect(u.queryParameters['client_id'], 'cid');
      expect(u.queryParameters['redirect_uri'], JiraOAuth.defaultRedirectUri);
      expect(u.queryParameters['scope'], contains('read:jira-work'));
      expect(u.queryParameters['scope'], contains('offline_access'));
      expect(u.queryParameters['state'], 'st');
    });

    test('authorize devuelve el código e ignora peticiones sin el state correcto',
        () async {
      final oauth = JiraOAuth(port: testPort, openBrowser: (url) async {
        final state = url.queryParameters['state']!;
        final http1 = HttpClient();
        // Petición ajena con state falso: no debe aceptarse ni abortar el flujo.
        final bad = await (await http1.getUrl(Uri.parse(
                '$testRedirect?code=EVIL&state=otro')))
            .close();
        expect(bad.statusCode, 400);
        await bad.drain<void>();
        final ok = await (await http1.getUrl(
                Uri.parse('$testRedirect?code=ABC&state=$state')))
            .close();
        expect(ok.statusCode, 200);
        await ok.drain<void>();
        http1.close();
        return true;
      });
      expect(await oauth.authorize('cid'), 'ABC');
    });

    test('authorize falla si el usuario rechaza el acceso', () async {
      final oauth = JiraOAuth(port: testPort, openBrowser: (url) async {
        final state = url.queryParameters['state']!;
        final c = HttpClient();
        final r = await (await c.getUrl(Uri.parse(
                '$testRedirect?error=access_denied&state=$state')))
            .close();
        await r.drain<void>();
        c.close();
        return true;
      });
      expect(oauth.authorize('cid'), throwsA(isA<JiraAuthException>()));
    });

    test('exchangeCode envía client_secret y devuelve los tokens', () async {
      late Map<String, dynamic> sent;
      final oauth = JiraOAuth(port: testPort, 
        openBrowser: (_) async => true,
        client: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return json({'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600});
        }),
      );
      final t = await oauth.exchangeCode(
          clientId: 'cid', clientSecret: 'sec', code: 'c');
      expect(sent['grant_type'], 'authorization_code');
      expect(sent['client_secret'], 'sec');
      expect(sent['redirect_uri'], testRedirect);
      expect(t.accessToken, 'a');
      expect(t.refreshToken, 'r');
      expect(t.isExpired, isFalse);
    });

    test('un rechazo de Atlassian se convierte en JiraAuthException', () async {
      final oauth = JiraOAuth(port: testPort, 
        openBrowser: (_) async => true,
        client: MockClient((_) async => json({'error': 'invalid_client'}, 403)),
      );
      expect(
          oauth.exchangeCode(clientId: 'x', clientSecret: 'y', code: 'z'),
          throwsA(isA<JiraAuthException>()
              .having((e) => e.message, 'message', contains('invalid_client'))));
    });
  });

  group('JiraController', () {
    late AppDatabase db;
    late ProjectsController projects;
    late MemorySecretStore store;

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      projects = ProjectsController(ProjectsRepositoryImpl(db));
      await projects.load();
      store = MemorySecretStore();
    });

    tearDown(() async {
      projects.dispose();
      await db.close();
    });

    /// Controlador con Atlassian simulado. `search` responde a la búsqueda.
    JiraController build({
      required Future<http.Response> Function(http.Request) search,
      int expiresIn = 3600,
      void Function(String grantType)? onToken,
    }) {
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/oauth/token') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          onToken?.call(body['grant_type'] as String);
          return json({
            'access_token': 'access-${body['grant_type']}',
            'refresh_token': 'refresh-new',
            'expires_in': expiresIn,
          });
        }
        if (path == '/oauth/token/accessible-resources') {
          return json([
            {'id': site.id, 'name': site.name, 'url': site.url}
          ]);
        }
        return search(req);
      });
      return JiraController(
        store: store,
        oauth: JiraOAuth(port: testPort, 
          client: mock,
          openBrowser: (url) async {
            final state = url.queryParameters['state']!;
            final c = HttpClient();
            final r = await (await c.getUrl(
                    Uri.parse('$testRedirect?code=CODE&state=$state')))
                .close();
            await r.drain<void>();
            c.close();
            return true;
          },
        ),
        api: JiraApi(client: mock),
      );
    }

    test('inicio de sesión, sincronización y que no pierda el tiempo medido',
        () async {
      final jira = build(search: (req) async {
        return json({
          'issues': [
            issue('A-1', 'Tarea', description: 'detalle'),
            issue('A-2', 'Sub', parent: 'A-1'),
          ],
          'isLast': true,
        });
      });
      await jira.load();
      await jira.saveCredentials('cid', 'sec');
      expect(jira.configured, isTrue);

      await jira.signIn();
      expect(jira.error, isNull);
      expect(jira.signedIn, isTrue);
      expect(jira.session!.site.name, 'Acme');

      await jira.sync(projects);
      expect(jira.error, isNull);
      expect(projects.projects.map((p) => p.name), ['A-1 Tarea', 'A-2 Sub']);
      expect(projects.projects[1].description, startsWith('Subtarea de A-1'));
      expect(projects.projects[0].link, 'https://acme.atlassian.net/browse/A-1');

      // Mide tiempo en A-1 y vuelve a sincronizar: el tiempo se conserva y no
      // se duplican las entradas.
      await projects.start(projects.projects[0]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await projects.pause(projects.projects[0]);
      final measured = projects.projects[0].accumulatedMs;
      expect(measured, greaterThan(0));

      await jira.sync(projects);
      expect(projects.projects.length, 2);
      expect(projects.projects[0].accumulatedMs, measured);
      expect(jira.message, contains('0 nuevas, 2 actualizadas'));
    });

    test('el secreto y la sesión se guardan en el almacén seguro, no en SQLite',
        () async {
      final jira = build(search: (_) async => json({'issues': [], 'isLast': true}));
      await jira.saveCredentials('cid', 'sec-super-secreto');
      await jira.signIn();
      expect(store.data['jira_client_secret'], 'sec-super-secreto');
      expect(store.data['jira_session'], contains('access-authorization_code'));
      final rows = await db.projects();
      expect(rows, isEmpty);
    });

    test('con el token vencido lo refresca antes de consultar', () async {
      final grants = <String>[];
      final jira = build(
        expiresIn: 0, // el token nace vencido
        onToken: grants.add,
        search: (req) async {
          expect(req.headers['Authorization'], 'Bearer access-refresh_token');
          return json({'issues': [], 'isLast': true});
        },
      );
      await jira.saveCredentials('cid', 'sec');
      await jira.signIn();
      await jira.sync(projects);
      expect(jira.error, isNull);
      expect(grants, ['authorization_code', 'refresh_token']);
      expect(jira.message, contains('No tienes tareas'));
    });

    test('si Jira responde 401 refresca y reintenta una vez', () async {
      var calls = 0;
      final jira = build(search: (req) async {
        calls++;
        if (calls == 1) return json({}, 401);
        expect(req.headers['Authorization'], 'Bearer access-refresh_token');
        return json({'issues': [issue('A-1', 'x')], 'isLast': true});
      });
      await jira.saveCredentials('cid', 'sec');
      await jira.signIn();
      await jira.sync(projects);
      expect(jira.error, isNull);
      expect(calls, 2);
      expect(projects.projects.single.jiraKey, 'A-1');
    });

    test('si sigue el 401 cierra la sesión y pide iniciar de nuevo', () async {
      final jira = build(search: (_) async => json({}, 401));
      await jira.saveCredentials('cid', 'sec');
      await jira.signIn();
      await jira.sync(projects);
      expect(jira.signedIn, isFalse);
      expect(jira.error, contains('Inicia sesión de nuevo'));
      expect(store.data.containsKey('jira_session'), isFalse);
    });

    test('con credenciales compiladas basta iniciar sesión en el navegador',
        () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/oauth/token') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['client_id'], 'build-id');
          expect(body['client_secret'], 'build-secret');
          return json({'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600});
        }
        return json([
          {'id': site.id, 'name': site.name, 'url': site.url}
        ]);
      });
      final jira = JiraController(
        store: store,
        defaultClientId: 'build-id',
        defaultClientSecret: 'build-secret',
        oauth: JiraOAuth(port: testPort, 
          client: mock,
          openBrowser: (url) async {
            expect(url.queryParameters['client_id'], 'build-id');
            final c = HttpClient();
            final r = await (await c.getUrl(Uri.parse(
                    '$testRedirect?code=C&state=${url.queryParameters['state']}')))
                .close();
            await r.drain<void>();
            c.close();
            return true;
          },
        ),
        api: JiraApi(client: mock),
      );
      await jira.load();
      expect(jira.configured, isTrue); // sin pegar nada
      await jira.signIn();
      expect(jira.error, isNull);
      expect(jira.signedIn, isTrue);
      expect(store.data.containsKey('jira_client_secret'), isFalse);
    });

    test('cambiar el Client ID cierra la sesión; secreto vacío conserva el actual',
        () async {
      final jira = build(search: (_) async => json({'issues': [], 'isLast': true}));
      await jira.saveCredentials('cid', 'sec');
      await jira.signIn();
      expect(jira.signedIn, isTrue);

      await jira.saveCredentials('cid', ''); // mismo id, sin secreto nuevo
      expect(jira.signedIn, isTrue);
      expect(store.data['jira_client_secret'], 'sec');

      await jira.saveCredentials('otra-app', '');
      expect(jira.signedIn, isFalse);
      expect(store.data['jira_client_secret'], 'sec');
    });
  });

  test('upsert por clave de Jira no duplica y la migración conserva datos', () async {
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    final c = ProjectsController(ProjectsRepositoryImpl(db));
    await c.load();
    await c.add('Manual', '', '');
    final r1 = await c.importJira([
      const JiraIssue(key: 'K-1', summary: 'a', description: '', url: 'u').toProject()
    ]);
    final r2 = await c.importJira([
      const JiraIssue(key: 'K-1', summary: 'b', description: '', url: 'u').toProject()
    ]);
    expect((r1.added, r1.updated), (1, 0));
    expect((r2.added, r2.updated), (0, 1));
    expect(c.projects.map((p) => p.name), ['Manual', 'K-1 b']);
    expect(c.projects.first.jiraKey, isNull);
    c.dispose();
    await db.close();
  });
}
