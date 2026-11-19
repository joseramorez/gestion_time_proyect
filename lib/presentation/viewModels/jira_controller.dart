import 'package:flutter/foundation.dart';
import 'package:gestion_time_proyect/domain/usecases/find_stale_jira_keys.dart';
import 'package:gestion_time_proyect/domain/usecases/prepare_worklog.dart';

import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/errors/jira_exceptions.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';

/// Estado de la integración con Jira: credenciales de la app OAuth del
/// usuario, sesión iniciada y sincronización de sus tareas asignadas.
class JiraController extends ChangeNotifier {
  JiraController({
    required this._store,
    required this._oauth,
    required this._api,
    this.defaultClientId = '',
    this.defaultClientSecret = '',
  });

  /// Credenciales de la app OAuth **compiladas** en el binario, que salen del archivo
  /// `.env` (`JIRA_CLIENT_ID` y `JIRA_CLIENT_SECRET`, vía `--dart-define-from-file`;
  /// ver `docs/jira.md`). Ojo: quien tenga el binario puede extraer ese secreto.
  final String defaultClientId;
  final String defaultClientSecret;

  /// ¿La compilación trae las dos credenciales? Si es así **mandan** sobre lo que haya
  /// guardado, el usuario no tiene que escribir nada (solo inicia sesión en el
  /// navegador) y la app no ofrece cambiarlas. Si falta alguna de las dos, se
  /// considera que no hay y la app pide las credenciales y las guarda en el almacén
  /// seguro del sistema.
  bool get hasBuildCredentials =>
      defaultClientId.isNotEmpty && defaultClientSecret.isNotEmpty;

  static const _kClientId = 'jira_client_id';
  static const _kClientSecret = 'jira_client_secret';
  static const _kSession = 'jira_session';

  final SecretStore _store;
  final JiraOAuth _oauth;
  final JiraApi _api;

  // Reglas de negocio (dominio): qué registro se envía y qué tickets refrescar.
  final _prepareWorklog = const PrepareWorklog();
  final _findStaleKeys = const FindStaleJiraKeys();

  String _clientId = '';
  bool _hasSecret = false;
  JiraSession? _session;
  bool _busy = false;
  String? _error;
  String? _message;

  String get clientId => _clientId;
  bool get configured => _clientId.isNotEmpty && _hasSecret;
  bool get signedIn => _session != null;
  JiraSession? get session => _session;
  bool get busy => _busy;
  String? get error => _error;
  String? get message => _message;

  Future<void> load() async {
    if (hasBuildCredentials) {
      await _dropStoredCredentialsOfAnotherApp();
      _clientId = defaultClientId;
    } else {
      final storedId = (await _store.read(_kClientId)) ?? '';
      _clientId = storedId.isNotEmpty ? storedId : defaultClientId;
    }
    _hasSecret = (await _secret()).isNotEmpty;
    _session = JiraSessionModel.tryParse(await _store.read(_kSession));
    notifyListeners();
  }

  /// Si antes se guardaron a mano credenciales de OTRA app de Atlassian, ya no valen
  /// (la compilación trae las suyas) y la sesión que se hizo con ellas tampoco: se
  /// borran, para no intentar renovar un token con un cliente que no es el suyo.
  Future<void> _dropStoredCredentialsOfAnotherApp() async {
    final storedId = (await _store.read(_kClientId)) ?? '';
    if (storedId.isEmpty || storedId == defaultClientId) return;
    await _store.delete(_kClientId);
    await _store.delete(_kClientSecret);
    await _store.delete(_kSession);
  }

  /// Guarda las credenciales de la app OAuth en el **almacén seguro** del sistema
  /// (nunca en SQLite). Un secreto vacío conserva el anterior (no se le muestra al
  /// usuario). Cambiar de app cierra la sesión.
  ///
  /// Se ignora si la compilación ya trae credenciales (`hasBuildCredentials`): esas
  /// mandan y no se cambian desde la app.
  Future<void> saveCredentials(String clientId, String clientSecret) async {
    if (hasBuildCredentials) return;
    final id = clientId.trim();
    final secret = clientSecret.trim();
    final changed = id != _clientId || secret.isNotEmpty;
    await _store.write(_kClientId, id);
    if (secret.isNotEmpty) await _store.write(_kClientSecret, secret);
    _clientId = id;
    _hasSecret = secret.isNotEmpty || _hasSecret;
    if (changed) await _clearSession();
    _error = null;
    _message = null;
    notifyListeners();
  }

  Future<void> signIn() => _run(() async {
    final secret = await _secret();
    final code = await _oauth.authorize(_clientId);
    final tokens = await _oauth.exchangeCode(
      clientId: _clientId,
      clientSecret: secret,
      code: code,
    );
    final sites = await _oauth.accessibleSites(tokens.accessToken);
    if (sites.isEmpty) {
      throw JiraAuthException(
        'La cuenta no tiene sitios de Jira accesibles para esta app. '
        'Revisa que la app tenga el scope read:jira-work.',
      );
    }
    await _saveSession(
      JiraSession(tokens: tokens, sites: sites, siteId: sites.first.id),
    );
    _message = 'Sesión iniciada en ${_session!.site.name}.';
  });

  Future<void> signOut() async {
    await _clearSession();
    _error = null;
    _message = null;
    notifyListeners();
  }

  Future<void> selectSite(String siteId) async {
    final s = _session;
    if (s == null) return;
    await _saveSession(s.copyWith(siteId: siteId));
    notifyListeners();
  }

  /// Trae las tareas y subtareas asignadas al usuario e incorpora a la lista.
  Future<void> sync(ProjectsController projects) => _run(() async {
    final issues = await _withToken(
      (s) => _api.assignedToMe(accessToken: s.tokens.accessToken, site: s.site),
    );

    final result = await projects.importJira([
      for (final i in issues) i.toProject(),
    ]);

    // La consulta solo trae pendientes asignados a ti. Los ya importados que
    // dejaron de aparecer (p. ej. pasaron a "Listo") se quedarían con el estado
    // y el seguimiento de tiempo viejos, así que se refrescan aparte.
    final stale = _findStaleKeys(projects.projects, {
      for (final i in issues) i.key,
    });
    var refreshed = 0;
    var refreshFailed = false;
    if (stale.isNotEmpty) {
      try {
        final live = await _withToken(
          (s) => _api.liveInfoFor(
            accessToken: s.tokens.accessToken,
            site: s.site,
            keys: stale,
          ),
        );
        await projects.updateJiraLive(live);
        refreshed = live.length;
      } on JiraApiException {
        refreshFailed = true; // lo importado ya está guardado; no se aborta
      }
    }

    _message = [
      if (issues.isEmpty)
        'No tienes tareas pendientes asignadas.'
      else
        '${result.added} nuevas, ${result.updated} actualizadas '
            '(${issues.length} en total).',
      if (refreshed == 1) '1 ticket refrescado.',
      if (refreshed > 1) '$refreshed tickets refrescados.',
      if (refreshFailed)
        'No se pudo refrescar el estado de tickets anteriores.',
    ].join(' ');
  });

  /// Límites del tiempo de un corte (reglas en `PrepareWorklog`).
  static const minLogSeconds = PrepareWorklog.minSeconds;
  static const maxLogSeconds = PrepareWorklog.maxSeconds;

  /// Corte: registra en Jira (worklog) el tiempo del ticket y, solo si Jira lo
  /// acepta, lo descuenta del cronómetro. Si falla, nada cambia localmente.
  ///
  /// `duration` es el tiempo que el usuario confirmó (puede haberlo editado);
  /// sin él se usa el medido en este instante. Lo que se envíe se resta del
  /// cronómetro: si se envía menos de lo medido, lo que sobre se conserva; si
  /// se envía más, el cronómetro queda en cero. Con `reset` el cronómetro se reinicia
  /// siempre. Devuelve `true` si se registró.
  Future<bool> logWork(
    Project project,
    String comment,
    ProjectsController projects, {
    Duration? duration,
    bool reset = false,
  }) async {
    var logged = false;
    await _run(() async {
      final key = project.jiraKey;
      if (key == null) throw JiraApiException('Esta entrada no es de Jira.');
      final session = _session;
      if (session == null) throw JiraAuthException('Inicia sesión primero.');
      if (!session.canWrite) {
        throw JiraAuthException(
          'Falta el permiso de escritura en Jira. '
          'Cierra sesión e inicia de nuevo para concederlo.',
        );
      }

      // Sin tiempo confirmado, instantánea del medido al confirmar (el
      // cronómetro puede seguir corriendo mientras dura la llamada).
      final current = projects.projects.firstWhere((p) => p.id == project.id);
      final Worklog worklog;
      try {
        worklog = _prepareWorklog(
          measured: current.elapsed(),
          requested: duration,
          now: DateTime.now(),
        );
      } on InvalidWorklog catch (e) {
        throw JiraApiException(e.message);
      }
      final seconds = worklog.seconds;
      final started = worklog.started;

      await _sendWorklog(key, seconds, started, comment);

      await projects.registerJiraCut(current, seconds * 1000, reset: reset);

      // Jira ajusta solo "registrado" y "restante" al crear el worklog: se vuelve a
      // leer el ticket. Es secundario: el registro ya está hecho, así que un fallo
      // aquí no se muestra (la próxima sincronización lo corrige).
      try {
        final live = await _withToken(
          (s) => _api.liveInfoFor(
            accessToken: s.tokens.accessToken,
            site: s.site,
            keys: [key],
          ),
        );
        await projects.updateJiraLive(live);
      } catch (_) {}
      _message =
          'Registrado ${formatWorkDuration(Duration(seconds: seconds))} en $key.';
      logged = true;
    });
    return logged;
  }

  /// Envía un worklog a Jira (lanza si falla). Un error de red tras el POST es ambiguo
  /// (puede haberse creado): el mensaje manda revisar Jira antes de reintentar.
  Future<void> _sendWorklog(
    String key,
    int seconds,
    DateTime started,
    String comment,
  ) async {
    try {
      await _withToken(
        (s) => _api.addWorklog(
          accessToken: s.tokens.accessToken,
          site: s.site,
          issueKey: key,
          seconds: seconds,
          started: started,
          comment: comment,
        ),
      );
    } on JiraAuthException {
      rethrow;
    } on JiraApiException {
      rethrow;
    } catch (e) {
      throw JiraApiException(
        'No se pudo confirmar el envío ($e). Revisa el '
        'ticket $key en Jira antes de reintentar, para no duplicar el registro.',
      );
    }
  }

  /// ¿Hay sesión con permiso para registrar tiempo?
  bool get canWrite => _session?.canWrite ?? false;

  /// Envía un worklog con la duración y el inicio dados (lo usa el corte diario, cuyo
  /// `started` cae en un día pasado). No toca ningún cronómetro ni el estado de
  /// ocupado/mensaje del controlador. Devuelve `null` si Jira lo aceptó o el texto del
  /// error si no.
  Future<String?> postWorklog({
    required String issueKey,
    required int seconds,
    required DateTime started,
    String comment = '',
  }) async {
    if (_session == null) return 'Inicia sesión en Jira primero.';
    if (!canWrite) {
      return 'Falta el permiso de escritura en Jira. '
          'Cierra sesión e inicia de nuevo para concederlo.';
    }
    try {
      await _sendWorklog(issueKey, seconds, started, comment);
      return null;
    } on JiraAuthException catch (e) {
      return e.message;
    } on JiraApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Error de red o inesperado: $e';
    }
  }

  static const _noTransitions = <JiraTransition>[];

  /// Cambios de estado disponibles ahora para el ticket. Devuelve la lista o el texto del
  /// error (sin sesión, sin permiso de escritura, sin red…).
  Future<({List<JiraTransition> transitions, String? error})> transitionsFor(
    Project project,
  ) async {
    final key = project.jiraKey;
    if (key == null) {
      return (transitions: _noTransitions, error: 'Esta entrada no es de Jira.');
    }
    final denied = _writeDenial();
    if (denied != null) return (transitions: _noTransitions, error: denied);
    try {
      final list = await _withToken(
        (s) => _api.transitionsFor(
          accessToken: s.tokens.accessToken,
          site: s.site,
          issueKey: key,
        ),
      );
      return (transitions: list, error: null);
    } on JiraAuthException catch (e) {
      return (transitions: _noTransitions, error: e.message);
    } on JiraApiException catch (e) {
      return (transitions: _noTransitions, error: e.message);
    } catch (e) {
      return (
        transitions: _noTransitions,
        error: 'Error de red o inesperado: $e',
      );
    }
  }

  /// Cambia el estado del ticket en Jira. Solo si Jira lo acepta se actualiza el estado
  /// guardado (y se relee el ticket, best effort, por si Jira ajusta algo más). Devuelve
  /// `null` si se hizo o el texto del error.
  Future<String?> changeStatus(
    Project project,
    JiraTransition transition,
    ProjectsController projects,
  ) async {
    final key = project.jiraKey;
    if (key == null) return 'Esta entrada no es de Jira.';
    final denied = _writeDenial();
    if (denied != null) return denied;
    try {
      await _withToken(
        (s) => _api.transition(
          accessToken: s.tokens.accessToken,
          site: s.site,
          issueKey: key,
          transitionId: transition.id,
        ),
      );
    } on JiraAuthException catch (e) {
      return e.message;
    } on JiraApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'No se pudo confirmar el cambio ($e). Revisa el ticket $key en Jira.';
    }
    // Jira ya lo aceptó: se refleja al instante (conservando el seguimiento de tiempo,
    // que puede ser null = "no informado") y luego se relee para traer lo real.
    await projects.updateJiraLive({
      key: JiraLive(
        status: transition.toStatus,
        category: transition.toCategory,
        estimateSeconds: project.jiraEstimateSeconds,
        remainingSeconds: project.jiraRemainingSeconds,
        spentSeconds: project.jiraSpentSeconds,
      ),
    });
    try {
      final live = await _withToken(
        (s) => _api.liveInfoFor(
          accessToken: s.tokens.accessToken,
          site: s.site,
          keys: [key],
        ),
      );
      await projects.updateJiraLive(live);
    } catch (_) {}
    return null;
  }

  /// Por qué no se puede escribir en Jira ahora (o `null` si se puede).
  String? _writeDenial() {
    if (_session == null) return 'Inicia sesión en Jira primero.';
    if (!canWrite) {
      return 'Falta el permiso de escritura en Jira. '
          'Cierra sesión e inicia de nuevo para concederlo.';
    }
    return null;
  }

  /// Ejecuta `call` con un token válido: refresca si venció y, si Jira responde
  /// 401, refresca y reintenta una vez; un segundo 401 cierra la sesión.
  Future<T> _withToken<T>(Future<T> Function(JiraSession session) call) async {
    var session = _session;
    if (session == null) throw JiraAuthException('Inicia sesión primero.');
    if (session.tokens.isExpired) session = await _refresh(session);
    try {
      return await call(session);
    } on JiraUnauthorized {
      session = await _refresh(session);
      try {
        return await call(session);
      } on JiraUnauthorized {
        await _clearSession();
        throw JiraAuthException(
          'Jira rechazó la sesión. Inicia sesión de nuevo.',
        );
      }
    }
  }

  Future<JiraSession> _refresh(JiraSession session) async {
    final refreshToken = session.tokens.refreshToken;
    if (refreshToken == null) {
      await _clearSession();
      throw JiraAuthException('La sesión caducó. Inicia sesión de nuevo.');
    }
    try {
      final tokens = await _oauth.refresh(
        clientId: _clientId,
        clientSecret: await _secret(),
        refreshToken: refreshToken,
      );
      // La respuesta del refresco puede omitir `scope`: se conserva el anterior.
      final renewed = session.copyWith(
        tokens: TokenSet(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: tokens.expiresAt,
          scope: tokens.scope ?? session.tokens.scope,
        ),
      );
      await _saveSession(renewed);
      return renewed;
    } on JiraAuthException {
      await _clearSession();
      throw JiraAuthException('La sesión caducó. Inicia sesión de nuevo.');
    }
  }

  Future<String> _secret() async {
    if (hasBuildCredentials) return defaultClientSecret; // la compilación manda
    final stored = await _store.read(_kClientSecret);
    return (stored != null && stored.isNotEmpty) ? stored : defaultClientSecret;
  }

  Future<void> _saveSession(JiraSession s) async {
    _session = s;
    await _store.write(_kSession, JiraSessionModel.toJson(s));
  }

  Future<void> _clearSession() async {
    _session = null;
    await _store.delete(_kSession);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _message = null;
    notifyListeners();
    try {
      await action();
    } on JiraAuthException catch (e) {
      _error = e.message;
    } on JiraApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error de red o inesperado: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
