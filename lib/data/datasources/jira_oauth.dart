import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/errors/jira_exceptions.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';

/// OAuth 2.0 (3LO) de Atlassian con código de autorización.
///
/// El navegador del sistema muestra el inicio de sesión y consentimiento de
/// Atlassian; la app solo recibe un código en un servidor local de un solo uso.
/// Atlassian exige `client_secret` en el intercambio de tokens (no ofrece PKCE
/// para apps Cloud), por eso cada usuario aporta el de su propia app.
class JiraOAuth {
  JiraOAuth({
    http.Client? client,
    required this.openBrowser,
    this.timeout = const Duration(minutes: 3),
    this.port = defaultPort,
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final Future<bool> Function(Uri url) openBrowser;
  final Duration timeout;

  /// Puerto fijo: Atlassian exige que la URL de callback coincida exactamente
  /// con la registrada en la app. Solo las pruebas usan otro, para que varios
  /// archivos de prueba en paralelo no compitan por el mismo puerto.
  static const defaultPort = 53682;
  static const defaultRedirectUri = 'http://localhost:$defaultPort/callback';

  final int port;
  String get redirectUri => 'http://localhost:$port/callback';
  static const scopes = 'read:jira-work write:jira-work offline_access';

  static final _authBase = Uri.https('auth.atlassian.com');

  static Uri authorizeUri(
    String clientId,
    String state, {
    String redirectUri = defaultRedirectUri,
  }) => _authBase.replace(
    path: '/authorize',
    queryParameters: {
      'audience': 'api.atlassian.com',
      'client_id': clientId,
      'scope': scopes,
      'redirect_uri': redirectUri,
      'state': state,
      'response_type': 'code',
      'prompt': 'consent',
    },
  );

  /// Abre el navegador y espera el código de autorización.
  Future<String> authorize(String clientId) async {
    final state = _randomState();
    final server = await _bind();
    try {
      final code = _waitForCode(server, state);
      if (!await openBrowser(
        authorizeUri(clientId, state, redirectUri: redirectUri),
      )) {
        throw JiraAuthException('No se pudo abrir el navegador.');
      }
      return await code.timeout(
        timeout,
        onTimeout: () =>
            throw JiraAuthException('Se agotó el tiempo para iniciar sesión.'),
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<TokenSet> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
  }) => _token({
    'grant_type': 'authorization_code',
    'client_id': clientId,
    'client_secret': clientSecret,
    'code': code,
    'redirect_uri': redirectUri,
  });

  Future<TokenSet> refresh({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) => _token({
    'grant_type': 'refresh_token',
    'client_id': clientId,
    'client_secret': clientSecret,
    'refresh_token': refreshToken,
  });

  /// Sitios Jira a los que el usuario dio acceso a la app.
  Future<List<JiraSite>> accessibleSites(String accessToken) async {
    final res = await _http.get(
      Uri.https('api.atlassian.com', '/oauth/token/accessible-resources'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw JiraAuthException(
        'No se pudieron obtener los sitios de Jira (${res.statusCode}).',
      );
    }
    return (jsonDecode(res.body) as List)
        .map((s) => JiraSiteModel.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<TokenSet> _token(Map<String, String> body) async {
    final res = await _http.post(
      Uri.https('auth.atlassian.com', '/oauth/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = const {};
    }
    if (res.statusCode != 200 || json['access_token'] is! String) {
      final detail =
          json['error_description'] ??
          json['error'] ??
          'HTTP ${res.statusCode}';
      throw JiraAuthException('Atlassian rechazó la autenticación: $detail');
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return TokenSet(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String? ?? body['refresh_token'],
      scope: json['scope'] as String?,
      // Margen de 60 s para no usar un token a punto de caducar.
      expiresAt: DateTime.now().add(Duration(seconds: max(expiresIn - 60, 0))),
    );
  }

  Future<HttpServer> _bind() async {
    try {
      return await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        port,
        v6Only: false,
      );
    } on SocketException {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } on SocketException {
        throw JiraAuthException(
          'El puerto $port está ocupado. Ciérralo e inténtalo de nuevo.',
        );
      }
    }
  }

  Future<String> _waitForCode(HttpServer server, String state) async {
    await for (final req in server) {
      final q = req.uri.queryParameters;
      // Ignora todo lo que no sea el callback con nuestro `state`, para que
      // una petición ajena no pueda abortar ni inyectar un código.
      if (req.uri.path != '/callback' || q['state'] != state) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        continue;
      }
      final error = q['error'];
      final code = q['code'];
      final ok = error == null && code != null;
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><meta charset="utf-8"><title>my-jira-work-time</title>'
          '<body style="font-family:sans-serif;text-align:center;margin-top:20vh">'
          '<h2>${ok ? 'Listo' : 'No se pudo iniciar sesión'}</h2>'
          '<p>Ya puedes cerrar esta pestaña y volver a la app.</p></body>',
        );
      await req.response.close();
      if (!ok) {
        throw JiraAuthException(
          'Inicio de sesión cancelado o rechazado${error == null ? '' : ' ($error)'}.',
        );
      }
      return code;
    }
    throw JiraAuthException('Inicio de sesión cancelado.');
  }

  static String _randomState() {
    final rnd = Random.secure();
    return base64UrlEncode(
      List<int>.generate(24, (_) => rnd.nextInt(256)),
    ).replaceAll('=', '');
  }
}
