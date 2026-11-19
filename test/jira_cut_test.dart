import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/errors/jira_exceptions.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/data/models/jira_timestamp.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const testPort = 53691;
const testRedirect = 'http://localhost:$testPort/callback';

const site = JiraSite(id: 'cloud-1', name: 'Acme', url: 'https://acme.atlassian.net');

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('utilidades', () {
    test('jiraTimestamp usa UTC con +0000 y milisegundos', () {
      final t = DateTime.utc(2026, 11, 12, 3, 4, 5, 67);
      expect(jiraTimestamp(t), '2026-11-12T03:04:05.067+0000');
      expect(jiraTimestamp(t.toLocal()), '2026-11-12T03:04:05.067+0000');
    });

    test('formatWorkDuration', () {
      expect(formatWorkDuration(const Duration(seconds: 40)), '40 s');
      expect(formatWorkDuration(const Duration(minutes: 12, seconds: 5)), '12 m 05 s');
      expect(formatWorkDuration(const Duration(hours: 1, minutes: 5, seconds: 9)), '1 h 05 m');
    });

    test('canWrite depende del scope; las sesiones antiguas piden iniciar de nuevo', () {
      JiraSession session(String? scope) => JiraSession(
            tokens: TokenSet(
              accessToken: 'a',
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
              scope: scope,
            ),
            sites: const [site],
            siteId: site.id,
          );
      expect(session(null).canWrite, isFalse);
      expect(session('read:jira-work offline_access').canWrite, isFalse);
      expect(session('read:jira-work write:jira-work').canWrite, isTrue);

      final round = JiraSessionModel.tryParse(JiraSessionModel.toJson(session('read:jira-work write:jira-work')));
      expect(round!.canWrite, isTrue);

      // Sesión guardada por la versión anterior: sin clave "scope".
      final legacy = jsonDecode(JiraSessionModel.toJson(session(null))) as Map<String, dynamic>
        ..remove('scope');
      expect(JiraSessionModel.tryParse(jsonEncode(legacy))!.canWrite, isFalse);
    });
  });

  group('JiraApi.addWorklog', () {
    final started = DateTime.utc(2026, 1, 2, 3, 4, 5);

    test('envía segundos, fecha de inicio y comentario en ADF', () async {
      late http.Request sent;
      final api = JiraApi(client: MockClient((req) async {
        sent = req;
        return json({'id': '1'}, 201);
      }));
      await api.addWorklog(
        accessToken: 'tok',
        site: site,
        issueKey: 'A-1',
        seconds: 125,
        started: started,
        comment: '  hecho  ',
      );
      expect(sent.method, 'POST');
      expect(sent.url.path, '/ex/jira/cloud-1/rest/api/3/issue/A-1/worklog');
      expect(sent.headers['Authorization'], 'Bearer tok');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['timeSpentSeconds'], 125);
      expect(body['started'], '2026-01-02T03:04:05.000+0000');
      final comment = body['comment'] as Map<String, dynamic>;
      expect(comment['type'], 'doc');
      expect(comment['version'], 1);
      expect(jsonEncode(comment), contains('"text":"hecho"'));
    });

    test('sin comentario no envía el campo', () async {
      late Map<String, dynamic> body;
      final api = JiraApi(client: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return json({}, 201);
      }));
      await api.addWorklog(
          accessToken: 't', site: site, issueKey: 'A-1', seconds: 60, started: started, comment: '   ');
      expect(body.containsKey('comment'), isFalse);
    });

    Future<Object?> failWith(int status, [Object body = const {}]) async {
      final api = JiraApi(client: MockClient((_) async => json(body, status)));
      try {
        await api.addWorklog(
            accessToken: 't', site: site, issueKey: 'A-1', seconds: 60, started: started);
      } catch (e) {
        return e;
      }
      return null;
    }

    test('401 → JiraUnauthorized', () async {
      expect(await failWith(401), isA<JiraUnauthorized>());
    });

    test('403 y 404 dan mensajes claros', () async {
      expect(await failWith(403), isA<JiraApiException>().having((e) => e.message, 'm', contains('permiso')));
      expect(await failWith(404), isA<JiraApiException>().having((e) => e.message, 'm', contains('A-1')));
    });

    test('otros errores incluyen el detalle de Jira (también el mapa "errors")', () async {
      final e = await failWith(400, {
        'errorMessages': ['mala'],
        'errors': {'timeSpentSeconds': 'inválido'},
      });
      expect(e, isA<JiraApiException>()
          .having((e) => e.message, 'm', allOf(contains('mala'), contains('inválido'))));
    });
  });

  test('migración v2 → v3 conserva los datos y la columna nueva vale 0', () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('gestion_time_mig');
    final file = '${dir.path}${Platform.pathSeparator}old.db';
    try {
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '', link TEXT NOT NULL DEFAULT '',
                accumulated_ms INTEGER NOT NULL DEFAULT 0, started_at_ms INTEGER,
                jira_key TEXT)''');
            await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
            await db.insert('projects', {'name': 'viejo', 'accumulated_ms': 5000, 'jira_key': 'K-1'});
          },
        ),
      );
      await old.close();

      final db = await AppDatabase.open(path: file);
      final rows = await db.projects();
      expect(rows.single.name, 'viejo');
      expect(rows.single.accumulatedMs, 5000);
      expect(rows.single.jiraKey, 'K-1');
      expect(rows.single.jiraLoggedMs, 0);
      await db.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('JiraController.logWork', () {
    late AppDatabase db;
    late ProjectsController projects;
    late MemorySecretStore store;
    late List<http.Request> worklogCalls;
    late http.Response Function(http.Request) worklogReply;
    late List<String> grants;
    late List<Object?> liveIssues; // lo que devuelve la consulta posterior al corte
    late int liveCode;

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      projects = ProjectsController(ProjectsRepositoryImpl(db));
      await projects.load();
      store = MemorySecretStore();
      worklogCalls = [];
      grants = [];
      worklogReply = (_) => json({'id': '1'}, 201);
      liveIssues = [];
      liveCode = 200;
    });

    tearDown(() async {
      projects.dispose();
      await db.close();
    });

    /// `scope` es lo que Atlassian concede al iniciar sesión (el refresco no lo repite).
    JiraController build({String scope = 'read:jira-work write:jira-work offline_access'}) {
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/oauth/token') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final grant = body['grant_type'] as String;
          grants.add(grant);
          return json({
            'access_token': 'access-$grant',
            'refresh_token': 'refresh-new',
            'expires_in': 3600,
            if (grant == 'authorization_code') 'scope': scope,
          });
        }
        if (path == '/oauth/token/accessible-resources') {
          return json([
            {'id': site.id, 'name': site.name, 'url': site.url}
          ]);
        }
        if (path.endsWith('/worklog')) {
          worklogCalls.add(req);
          return worklogReply(req);
        }
        return json({'issues': liveIssues, 'isLast': true}, liveCode);
      });
      return JiraController(
        store: store,
        oauth: JiraOAuth(port: testPort, 
          client: mock,
          openBrowser: (url) async {
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
    }

    Future<JiraController> signedIn({String? scope}) async {
      final jira = scope == null ? build() : build(scope: scope);
      await jira.saveCredentials('cid', 'sec');
      await jira.signIn();
      expect(jira.error, isNull);
      return jira;
    }

    /// Ticket importado con `accumulatedMs`; si `running`, el cronómetro corre.
    Future<Project> ticket({int accumulatedMs = 0, bool running = false, String? key = 'A-1'}) async {
      final id = await db.insert(Project(name: '${key ?? 'Manual'} cosa', jiraKey: key));
      await db.update(Project(
        id: id,
        name: '${key ?? 'Manual'} cosa',
        jiraKey: key,
        accumulatedMs: accumulatedMs,
        startedAtMs: running ? DateTime.now().millisecondsSinceEpoch : null,
      ));
      await projects.load();
      return projects.projects.single;
    }

    test('éxito: envía el worklog, deja el cronómetro en cero y suma lo enviado', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 125000);

      final ok = await jira.logWork(p, 'revisión', projects);

      expect(ok, isTrue);
      expect(jira.error, isNull);
      expect(jira.message, contains('2 m 05 s'));
      final call = worklogCalls.single;
      expect(call.url.path, '/ex/jira/cloud-1/rest/api/3/issue/A-1/worklog');
      final body = jsonDecode(call.body) as Map<String, dynamic>;
      expect(body['timeSpentSeconds'], 125);
      expect(jsonEncode(body['comment']), contains('revisión'));

      final after = projects.projects.single;
      expect(after.accumulatedMs, 0);
      expect(after.isRunning, isFalse);
      expect(after.jiraLoggedMs, 125000);
      expect((await db.projects()).single.jiraLoggedMs, 125000); // persistido
    });

    test('si el cronómetro corría, sigue corriendo desde cero tras el corte', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 130000, running: true);

      expect(await jira.logWork(p, '', projects), isTrue);

      final after = projects.projects.single;
      expect(after.isRunning, isTrue);
      expect(after.elapsed(), lessThan(const Duration(seconds: 5)));
      expect(after.jiraLoggedMs, inInclusiveRange(130000, 135000));
    });

    test('si Jira falla no cambia nada local', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000);
      worklogReply = (_) => json({'errorMessages': ['boom']}, 500);

      expect(await jira.logWork(p, '', projects), isFalse);

      expect(jira.error, allOf(contains('500'), contains('boom')));
      final after = projects.projects.single;
      expect(after.accumulatedMs, 200000);
      expect(after.jiraLoggedMs, 0);
    });

    test('un fallo de red avisa de revisar Jira antes de reintentar', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000);
      worklogReply = (_) => throw const SocketException('sin red');

      expect(await jira.logWork(p, '', projects), isFalse);

      expect(jira.error, contains('Revisa el ticket A-1'));
      expect(projects.projects.single.accumulatedMs, 200000);
    });

    test('menos de 1 minuto no llama a Jira', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 59000);

      expect(await jira.logWork(p, '', projects), isFalse);

      expect(worklogCalls, isEmpty);
      expect(jira.error, contains('menos de 1 minuto'));
      expect(projects.projects.single.accumulatedMs, 59000);
    });

    test('una sesión sin permiso de escritura no llama a Jira', () async {
      final jira = await signedIn(scope: 'read:jira-work offline_access');
      expect(jira.session!.canWrite, isFalse);
      final p = await ticket(accumulatedMs: 200000);

      expect(await jira.logWork(p, '', projects), isFalse);

      expect(worklogCalls, isEmpty);
      expect(jira.error, contains('permiso de escritura'));
    });

    test('una entrada manual (sin clave de Jira) no se envía', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000, key: null);

      expect(await jira.logWork(p, '', projects), isFalse);
      expect(worklogCalls, isEmpty);
    });

    test('con tiempo editado menor: envía lo editado y conserva el resto', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000);

      final ok = await jira.logWork(p, '', projects, duration: const Duration(seconds: 90));

      expect(ok, isTrue);
      final body = jsonDecode(worklogCalls.single.body) as Map<String, dynamic>;
      expect(body['timeSpentSeconds'], 90);
      final after = projects.projects.single;
      expect(after.accumulatedMs, inInclusiveRange(110000, 112000)); // 200 s - 90 s
      expect(after.jiraLoggedMs, 90000);
      expect(jira.message, contains('1 m 30 s'));
    });

    test('con tiempo editado mayor al medido: el reloj queda en cero y se suma lo enviado',
        () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 100000);

      expect(await jira.logWork(p, '', projects, duration: const Duration(minutes: 5)),
          isTrue);

      expect((jsonDecode(worklogCalls.single.body) as Map)['timeSpentSeconds'], 300);
      final after = projects.projects.single;
      expect(after.accumulatedMs, 0);
      expect(after.jiraLoggedMs, 300000);
    });

    test('un tiempo editado fuera de rango no llama a Jira', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000);

      expect(await jira.logWork(p, '', projects, duration: const Duration(seconds: 30)),
          isFalse);
      expect(jira.error, contains('menos de 1 minuto'));

      expect(await jira.logWork(p, '', projects, duration: const Duration(hours: 25)),
          isFalse);
      expect(jira.error, contains('24 horas'));

      expect(worklogCalls, isEmpty);
      expect(projects.projects.single.accumulatedMs, 200000);
    });

    test('tras el corte vuelve a leer el seguimiento de tiempo de Jira', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 125000);
      // Jira ajusta solo "registrado" y "restante" al crear el worklog.
      liveIssues = [
        {
          'key': 'A-1',
          'fields': {
            'status': {'name': 'En curso', 'statusCategory': {'key': 'indeterminate'}},
            'timetracking': {
              'originalEstimateSeconds': 10800,
              'remainingEstimateSeconds': 3475,
              'timeSpentSeconds': 7325,
            },
          },
        },
      ];

      expect(await jira.logWork(p, '', projects), isTrue);

      final after = projects.projects.single;
      expect(after.jiraEstimateSeconds, 10800);
      expect(after.jiraRemainingSeconds, 3475);
      expect(after.jiraSpentSeconds, 7325);
      expect(after.jiraStatus, 'En curso');
    });

    test('si falla esa relectura, el corte igual cuenta como hecho y sin error', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 125000);
      liveCode = 500;

      expect(await jira.logWork(p, '', projects), isTrue);

      expect(jira.error, isNull);
      expect(projects.projects.single.jiraLoggedMs, 125000);
      expect(projects.projects.single.accumulatedMs, 0);
    });

    test('con 401 refresca, conserva el permiso de escritura y reintenta una vez', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000);
      var calls = 0;
      worklogReply = (req) {
        calls++;
        if (calls == 1) return json({}, 401);
        expect(req.headers['Authorization'], 'Bearer access-refresh_token');
        return json({'id': '1'}, 201);
      };

      expect(await jira.logWork(p, '', projects), isTrue);

      expect(grants, ['authorization_code', 'refresh_token']);
      expect(jira.session!.canWrite, isTrue); // el refresco no devolvió `scope`
      expect(projects.projects.single.jiraLoggedMs, 200000);
    });

    test('si sigue el 401 cierra la sesión y no cambia nada', () async {
      final jira = await signedIn();
      final p = await ticket(accumulatedMs: 200000);
      worklogReply = (_) => json({}, 401);

      expect(await jira.logWork(p, '', projects), isFalse);

      expect(jira.signedIn, isFalse);
      expect(jira.error, contains('Inicia sesión de nuevo'));
      expect(projects.projects.single.accumulatedMs, 200000);
    });
  });
}
