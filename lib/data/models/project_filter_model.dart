import 'dart:convert';

import 'package:gestion_time_proyect/domain/entities/project_filter.dart';

/// Serialización de [ProjectFilter] para guardarlo como preferencia. La búsqueda NO se
/// guarda: la app arranca con el cuadro de búsqueda vacío. Tolera datos viejos o dañados
/// (cualquier problema → sin filtros).
abstract final class ProjectFilterModel {
  static String toJson(ProjectFilter f) => jsonEncode({
    'v': 2,
    'statuses': f.statuses.toList()..sort(),
    'origin': f.origin.name,
    'activity': f.activity.name,
    'onlyUploadable': f.onlyUploadable,
    'onlyCarried': f.onlyCarried,
    'hideDone': f.hideDone,
    'sort': f.sort.name,
  });

  static ProjectFilter tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return ProjectFilter.initial;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
        for (final v in values) {
          if (v.name == name) return v;
        }
        return fallback;
      }

      return ProjectFilter(
        statuses: {
          for (final s in (m['statuses'] as List?) ?? const [])
            if (s is String) s,
        },
        origin: pick(ProjectOrigin.values, m['origin'], ProjectOrigin.all),
        activity: pick(ProjectActivity.values, m['activity'], ProjectActivity.all),
        onlyUploadable: m['onlyUploadable'] == true,
        onlyCarried: m['onlyCarried'] == true,
        // Antes de la v2 «ocultar finalizados» venía apagado: lo guardado entonces no
        // era una elección del usuario, así que se aplica el valor normal (activado).
        hideDone: m['v'] == null ? true : m['hideDone'] != false,
        sort: pick(ProjectSort.values, m['sort'], ProjectSort.original),
      );
    } catch (_) {
      return ProjectFilter.initial;
    }
  }
}
