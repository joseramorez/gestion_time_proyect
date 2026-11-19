import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';

/// De dónde salen el Client ID y el Secret: del `.env` compilado en la app, o de lo que
/// el usuario escribe y se guarda en el almacén seguro.
void main() {
  late MemorySecretStore store;

  setUp(() => store = MemorySecretStore());

  JiraController build({String buildId = '', String buildSecret = ''}) => JiraController(
        store: store,
        oauth: JiraOAuth(openBrowser: (_) async => false),
        api: JiraApi(),
        defaultClientId: buildId,
        defaultClientSecret: buildSecret,
      );

  String sessionJson() => JiraSessionModel.toJson(JiraSession(
        tokens: TokenSet(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scope: 'read:jira-work write:jira-work',
        ),
        sites: const [JiraSite(id: 's', name: 'Acme', url: 'https://acme.atlassian.net')],
        siteId: 's',
      ));

  group('credenciales compiladas desde .env', () {
    test('solo cuentan si vienen las dos (ID y Secret)', () {
      expect(build(buildId: 'id', buildSecret: 'sec').hasBuildCredentials, isTrue);
      expect(build(buildId: 'id').hasBuildCredentials, isFalse);
      expect(build(buildSecret: 'sec').hasBuildCredentials, isFalse);
      expect(build().hasBuildCredentials, isFalse);
    });

    test('con las dos, la app queda configurada sin que el usuario escriba nada', () async {
      final jira = build(buildId: 'id-env', buildSecret: 'sec-env');
      await jira.load();

      expect(jira.configured, isTrue);
      expect(jira.clientId, 'id-env');
      // y no se copian al almacén: ya están en el binario, duplicarlas no aporta nada
      expect(store.data.containsKey('jira_client_secret'), isFalse);
      expect(store.data.containsKey('jira_client_id'), isFalse);
    });

    test('mandan sobre lo guardado de la misma app y conservan su sesión', () async {
      store.data['jira_client_id'] = 'id-env';
      store.data['jira_client_secret'] = 'otro-secreto-guardado';
      store.data['jira_session'] = sessionJson();
      final jira = build(buildId: 'id-env', buildSecret: 'sec-env');
      await jira.load();

      expect(jira.clientId, 'id-env');
      expect(jira.signedIn, isTrue); // misma app: la sesión sigue valiendo
    });

    test('si lo guardado era de OTRA app, se descarta con su sesión', () async {
      store.data['jira_client_id'] = 'app-vieja';
      store.data['jira_client_secret'] = 'secreto-viejo';
      store.data['jira_session'] = sessionJson();
      final jira = build(buildId: 'id-env', buildSecret: 'sec-env');
      await jira.load();

      expect(jira.clientId, 'id-env');
      expect(jira.signedIn, isFalse); // esa sesión no sirve con otro cliente
      expect(store.data.containsKey('jira_client_id'), isFalse);
      expect(store.data.containsKey('jira_client_secret'), isFalse);
      expect(store.data.containsKey('jira_session'), isFalse);
    });

    test('desde la app no se pueden cambiar: guardar se ignora', () async {
      final jira = build(buildId: 'id-env', buildSecret: 'sec-env');
      await jira.load();

      await jira.saveCredentials('intruso', 'otro');

      expect(jira.clientId, 'id-env');
      expect(store.data, isEmpty);
    });
  });

  group('sin .env: se piden y se guardan en el almacén seguro', () {
    test('sin nada, la app no está configurada y hay que pedirlas', () async {
      final jira = build();
      await jira.load();

      expect(jira.configured, isFalse);
      expect(jira.hasBuildCredentials, isFalse);
    });

    test('lo que se escribe va al almacén seguro (ID y Secret)', () async {
      final jira = build();
      await jira.load();

      await jira.saveCredentials('  mi-id  ', '  mi-secreto  ');

      expect(store.data['jira_client_id'], 'mi-id'); // sin espacios sobrantes
      expect(store.data['jira_client_secret'], 'mi-secreto');
      expect(jira.configured, isTrue);
    });

    test('al arrancar otra vez, usa lo guardado', () async {
      final first = build();
      await first.load();
      await first.saveCredentials('mi-id', 'mi-secreto');

      final second = build();
      await second.load();

      expect(second.configured, isTrue);
      expect(second.clientId, 'mi-id');
    });

    test('cambiar de app cierra la sesión; dejar el secreto vacío conserva el anterior',
        () async {
      store.data['jira_client_id'] = 'id-a';
      store.data['jira_client_secret'] = 'sec-a';
      store.data['jira_session'] = sessionJson();
      final jira = build();
      await jira.load();
      expect(jira.signedIn, isTrue);

      await jira.saveCredentials('id-a', ''); // mismo ID, sin secreto nuevo
      expect(jira.signedIn, isTrue);
      expect(store.data['jira_client_secret'], 'sec-a');

      await jira.saveCredentials('id-b', ''); // otra app
      expect(jira.signedIn, isFalse);
      expect(store.data['jira_client_secret'], 'sec-a');
    });

    test('un .env incompleto (solo el ID) se trata como sin credenciales, con el ID de ayuda',
        () async {
      final jira = build(buildId: 'id-env');
      await jira.load();

      expect(jira.hasBuildCredentials, isFalse);
      expect(jira.clientId, 'id-env'); // viene rellenado en el formulario
      expect(jira.configured, isFalse); // pero falta el secreto: hay que pedirlo

      await jira.saveCredentials('id-env', 'el-secreto');
      expect(store.data['jira_client_secret'], 'el-secreto');
      expect(jira.configured, isTrue);
    });

    test('un .env incompleto (solo el Secret) tampoco cuenta', () async {
      final jira = build(buildSecret: 'sec-env');
      await jira.load();

      expect(jira.hasBuildCredentials, isFalse);
      expect(jira.configured, isFalse); // falta el ID
    });
  });
}
