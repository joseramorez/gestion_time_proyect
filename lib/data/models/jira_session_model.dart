import 'dart:convert';

import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';

/// JSON de un sitio de Jira (así lo devuelve Atlassian y así se guarda).
abstract final class JiraSiteModel {
  static Map<String, Object?> toJson(JiraSite s) => {
    'id': s.id,
    'name': s.name,
    'url': s.url,
  };

  static JiraSite fromJson(Map<String, dynamic> j) => JiraSite(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? (j['url'] as String? ?? ''),
    url: (j['url'] as String).replaceAll(RegExp(r'/+$'), ''),
  );
}

/// Cómo se guarda la sesión de Jira en el almacén seguro.
abstract final class JiraSessionModel {
  static String toJson(JiraSession s) => jsonEncode({
    'access_token': s.tokens.accessToken,
    'refresh_token': s.tokens.refreshToken,
    'expires_at_ms': s.tokens.expiresAt.millisecondsSinceEpoch,
    'scope': s.tokens.scope,
    'sites': s.sites.map(JiraSiteModel.toJson).toList(),
    'site_id': s.siteId,
  });

  /// `null` si el texto no existe o no es una sesión válida.
  static JiraSession? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final sites = (j['sites'] as List)
          .map((s) => JiraSiteModel.fromJson(s as Map<String, dynamic>))
          .toList();
      if (sites.isEmpty) return null;
      return JiraSession(
        tokens: TokenSet(
          accessToken: j['access_token'] as String,
          refreshToken: j['refresh_token'] as String?,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            j['expires_at_ms'] as int,
          ),
          scope: j['scope'] as String?,
        ),
        sites: sites,
        siteId: j['site_id'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
