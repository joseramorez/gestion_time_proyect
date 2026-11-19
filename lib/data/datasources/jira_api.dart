import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/errors/jira_exceptions.dart';
import 'package:gestion_time_proyect/data/models/jira_timestamp.dart';

/// Consulta de issues de Jira Cloud con un token OAuth.
class JiraApi {
  JiraApi({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// Tareas y subtareas asignadas al usuario dueño del token, sin terminar.
  /// `currentUser()` lo resuelve Jira con el token, así que solo devuelve lo
  /// del usuario que inició sesión.
  static const jql =
      'assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC';

  Future<List<JiraIssue>> assignedToMe({
    required String accessToken,
    required JiraSite site,
  }) async {
    final issues = <JiraIssue>[];
    String? pageToken;
    for (var page = 0; page < 50; page++) {
      final res = await _http.get(
        Uri.https(
          'api.atlassian.com',
          '/ex/jira/${site.id}/rest/api/3/search/jql',
          {
            'jql': jql,
            'fields':
                'summary,description,issuetype,parent,status,timetracking',
            'maxResults': '100',
            'nextPageToken': ?pageToken,
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 401) throw const JiraUnauthorized();
      if (res.statusCode != 200) {
        throw JiraApiException(
          'Jira respondió ${res.statusCode}: ${_errorDetail(res.body)}',
        );
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      for (final raw in (json['issues'] as List? ?? const [])) {
        issues.add(_parseIssue(raw as Map<String, dynamic>, site));
      }
      pageToken = json['nextPageToken'] as String?;
      if (pageToken == null || json['isLast'] == true) break;
    }
    return issues;
  }

  /// Registra tiempo (worklog) en un issue. El comentario, si existe, va en
  /// ADF, que es lo que exige la API v3.
  Future<void> addWorklog({
    required String accessToken,
    required JiraSite site,
    required String issueKey,
    required int seconds,
    required DateTime started,
    String comment = '',
  }) async {
    final text = comment.trim();
    final res = await _http.post(
      Uri.https(
        'api.atlassian.com',
        '/ex/jira/${site.id}/rest/api/3/issue/$issueKey/worklog',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'timeSpentSeconds': seconds,
        'started': jiraTimestamp(started),
        if (text.isNotEmpty)
          'comment': {
            'type': 'doc',
            'version': 1,
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {'type': 'text', 'text': text},
                ],
              },
            ],
          },
      }),
    );
    switch (res.statusCode) {
      case 200 || 201:
        return;
      case 401:
        throw const JiraUnauthorized();
      case 403:
        throw JiraApiException(
          'No tienes permiso para registrar tiempo en $issueKey, o la sesión '
          'no tiene permiso de escritura. Cierra sesión e inicia de nuevo.',
        );
      case 404:
        throw JiraApiException('$issueKey no existe o no tienes acceso a él.');
      default:
        throw JiraApiException(
          'Jira respondió ${res.statusCode}: ${_errorDetail(res.body)}',
        );
    }
  }

  /// Cambios de estado que Jira permite ahora a este issue (según su flujo de trabajo).
  Future<List<JiraTransition>> transitionsFor({
    required String accessToken,
    required JiraSite site,
    required String issueKey,
  }) async {
    final res = await _http.get(
      Uri.https(
        'api.atlassian.com',
        '/ex/jira/${site.id}/rest/api/3/issue/$issueKey/transitions',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    switch (res.statusCode) {
      case 200:
        final list =
            (jsonDecode(res.body) as Map<String, dynamic>)['transitions']
                as List? ??
            const [];
        return [
          for (final raw in list.whereType<Map>())
            if (raw['id'] != null && (raw['to'] as Map?)?['name'] != null)
              JiraTransition(
                id: raw['id'].toString(),
                name: (raw['name'] ?? (raw['to'] as Map)['name']).toString(),
                toStatus: (raw['to'] as Map)['name'] as String,
                toCategory:
                    ((raw['to'] as Map)['statusCategory'] as Map?)?['key']
                        as String?,
              ),
        ];
      case 401:
        throw const JiraUnauthorized();
      case 403:
        throw JiraApiException(
          'No tienes permiso para ver los estados de $issueKey, o la sesión no '
          'tiene permiso de escritura. Cierra sesión e inicia de nuevo.',
        );
      case 404:
        throw JiraApiException('$issueKey no existe o no tienes acceso a él.');
      default:
        throw JiraApiException(
          'Jira respondió ${res.statusCode}: ${_errorDetail(res.body)}',
        );
    }
  }

  /// Ejecuta una transición (cambia el estado del issue).
  Future<void> transition({
    required String accessToken,
    required JiraSite site,
    required String issueKey,
    required String transitionId,
  }) async {
    final res = await _http.post(
      Uri.https(
        'api.atlassian.com',
        '/ex/jira/${site.id}/rest/api/3/issue/$issueKey/transitions',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'transition': {'id': transitionId},
      }),
    );
    switch (res.statusCode) {
      case 200 || 204:
        return;
      case 401:
        throw const JiraUnauthorized();
      case 403:
        throw JiraApiException(
          'No tienes permiso para cambiar el estado de $issueKey, o la sesión '
          'no tiene permiso de escritura. Cierra sesión e inicia de nuevo.',
        );
      case 404:
        throw JiraApiException('$issueKey no existe o no tienes acceso a él.');
      case 400:
        final detail = _errorDetail(res.body);
        throw JiraApiException(
          'Jira pide datos adicionales para este cambio de estado'
          '${detail.isEmpty ? '' : ' ($detail)'}. Hazlo desde Jira.',
        );
      default:
        throw JiraApiException(
          'Jira respondió ${res.statusCode}: ${_errorDetail(res.body)}',
        );
    }
  }

  static JiraIssue _parseIssue(Map<String, dynamic> raw, JiraSite site) {
    final key = raw['key'] as String;
    final fields = (raw['fields'] as Map<String, dynamic>?) ?? const {};
    final isSubtask = (fields['issuetype'] as Map?)?['subtask'] == true;
    final parent = fields['parent'];
    final parentKey = isSubtask && parent is Map
        ? parent['key'] as String?
        : null;
    final status = _parseStatus(fields['status']);
    final tracking = _parseTracking(fields['timetracking']);
    return JiraIssue(
      key: key,
      summary: (fields['summary'] as String?) ?? '',
      description: adfToText(fields['description']),
      url: '${site.url}/browse/$key',
      parentKey: parentKey,
      status: status?.status,
      statusCategory: status?.category,
      estimateSeconds: tracking.estimate,
      remainingSeconds: tracking.remaining,
      spentSeconds: tracking.spent,
    );
  }

  /// `fields.timetracking` → segundos. El campo falta si el seguimiento de tiempo
  /// está desactivado en el proyecto; los valores faltan si no hay estimación o
  /// aún no se registró nada. Se conserva esa diferencia (`null`, no 0).
  static ({int? estimate, int? remaining, int? spent}) _parseTracking(
    Object? raw,
  ) {
    if (raw is! Map) return (estimate: null, remaining: null, spent: null);
    int? secs(String key) => (raw[key] as num?)?.toInt();
    return (
      estimate: secs('originalEstimateSeconds'),
      remaining: secs('remainingEstimateSeconds'),
      spent: secs('timeSpentSeconds'),
    );
  }

  /// `fields.status` → nombre y categoría (`statusCategory.key`).
  static ({String status, String? category})? _parseStatus(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    final category = raw['statusCategory'];
    return (
      status: name,
      category: category is Map ? category['key'] as String? : null,
    );
  }

  /// Claves con forma de issue de Jira (`ABC-12`). Se valida antes de armar el
  /// JQL para no interpolar texto arbitrario.
  static final _issueKey = RegExp(r'^[A-Za-z][A-Za-z0-9_]*-\d+$');

  /// Estado y seguimiento de tiempo actuales de varios issues por clave, aunque ya
  /// no estén asignados al usuario ni sean pendientes. Si una clave ya no existe
  /// (o no hay acceso), Jira rechaza toda la consulta con 400: se divide el grupo
  /// a la mitad hasta aislarla, y esa clave simplemente no aparece en el resultado.
  Future<Map<String, JiraLive>> liveInfoFor({
    required String accessToken,
    required JiraSite site,
    required Iterable<String> keys,
  }) async {
    final result = <String, JiraLive>{};

    Future<void> fetch(List<String> chunk) async {
      if (chunk.isEmpty) return;
      final res = await _http.get(
        Uri.https(
          'api.atlassian.com',
          '/ex/jira/${site.id}/rest/api/3/search/jql',
          {
            'jql': 'key in (${chunk.join(',')})',
            'fields': 'status,timetracking',
            'maxResults': '100',
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 401) throw const JiraUnauthorized();
      if (res.statusCode == 400 && chunk.length > 1) {
        final mid = chunk.length ~/ 2;
        await fetch(chunk.sublist(0, mid));
        await fetch(chunk.sublist(mid));
        return;
      }
      if (res.statusCode == 400) return; // clave inexistente o sin acceso
      if (res.statusCode != 200) {
        throw JiraApiException(
          'Jira respondió ${res.statusCode}: ${_errorDetail(res.body)}',
          statusCode: res.statusCode,
        );
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      for (final raw in (json['issues'] as List? ?? const [])) {
        final issue = raw as Map<String, dynamic>;
        final fields = issue['fields'] as Map<String, dynamic>?;
        final status = _parseStatus(fields?['status']);
        if (status == null) continue;
        final t = _parseTracking(fields?['timetracking']);
        result[issue['key'] as String] = JiraLive(
          status: status.status,
          category: status.category,
          estimateSeconds: t.estimate,
          remainingSeconds: t.remaining,
          spentSeconds: t.spent,
        );
      }
    }

    final valid = keys.where(_issueKey.hasMatch).toSet().toList();
    for (var i = 0; i < valid.length; i += 50) {
      await fetch(
        valid.sublist(i, i + 50 > valid.length ? valid.length : i + 50),
      );
    }
    return result;
  }

  static String _errorDetail(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final msgs = [
        ...?(j['errorMessages'] as List?),
        ...?(j['errors'] as Map?)?.values,
      ].join('; ');
      return msgs.isNotEmpty ? msgs : (j['message']?.toString() ?? '');
    } catch (_) {
      return '';
    }
  }
}

/// Convierte la descripción de Jira (Atlassian Document Format) a texto plano.
String adfToText(Object? node) {
  if (node == null) return '';
  if (node is String) return node.trim();
  final buffer = StringBuffer();
  _adf(node, buffer);
  return buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

const _blockTypes = {
  'paragraph',
  'heading',
  'codeBlock',
  'blockquote',
  'listItem',
  'tableRow',
  'panel',
  'rule',
};

void _adf(Object? node, StringBuffer out) {
  if (node is! Map) return;
  final type = node['type'];
  final attrs = (node['attrs'] as Map?) ?? const {};
  switch (type) {
    case 'text':
      out.write(node['text'] ?? '');
      return;
    case 'hardBreak':
      out.write('\n');
      return;
    case 'mention':
      out.write(attrs['text'] ?? '');
      return;
    case 'emoji':
      out.write(attrs['text'] ?? attrs['shortName'] ?? '');
      return;
    case 'inlineCard':
      out.write(attrs['url'] ?? '');
      return;
  }
  if (type == 'listItem') out.write('• ');
  for (final child in (node['content'] as List? ?? const [])) {
    _adf(child, out);
  }
  // Un salto por bloque, sin duplicar (p. ej. párrafo dentro de un listItem).
  if (_blockTypes.contains(type) && !out.toString().endsWith('\n')) {
    out.write('\n');
  }
}
