import 'package:gestion_time_proyect/domain/entities/day_key.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/entities/project_filter.dart';
import 'package:gestion_time_proyect/domain/usecases/prepare_worklog.dart';

/// Un estado de Jira presente en la lista, con su categoría (`new`, `indeterminate`,
/// `done`), para ofrecerlo como filtro.
typedef StatusOption = ({String status, String? category});

/// Aplica a la lista de entradas la búsqueda, los filtros y el orden de un
/// [ProjectFilter]. Es pura: recibe `now` y no toca nada.
///
/// El orden es **estable**: dos entradas que empatan conservan su orden original.
class FilterProjects {
  const FilterProjects();

  List<Project> call(
    Iterable<Project> projects,
    ProjectFilter filter,
    DateTime now,
  ) {
    final today = dayKey(now);
    final query = normalize(filter.query.trim());
    final kept = <(int, Project)>[];
    var i = 0;
    for (final p in projects) {
      if (_matches(p, filter, query, now, today)) kept.add((i, p));
      i++;
    }
    if (filter.sort != ProjectSort.original) {
      kept.sort((a, b) {
        final c = _compare(a.$2, b.$2, filter.sort, now);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    }
    return [for (final e in kept) e.$2];
  }

  /// Estados distintos presentes en `projects`, por categoría (por hacer → en curso →
  /// terminado) y luego por nombre. «Sin estado» va al final si hay entradas sin estado.
  List<StatusOption> statusesIn(Iterable<Project> projects) {
    final seen = <String, String?>{};
    var anyWithout = false;
    for (final p in projects) {
      final s = p.jiraStatus;
      if (s == null) {
        anyWithout = true;
      } else {
        seen.putIfAbsent(s, () => p.jiraStatusCategory);
      }
    }
    final list = [
      for (final e in seen.entries) (status: e.key, category: e.value),
    ]..sort((a, b) {
        final c = _rank(a.category).compareTo(_rank(b.category));
        return c != 0 ? c : normalize(a.status).compareTo(normalize(b.status));
      });
    if (anyWithout) list.add((status: ProjectFilter.noStatus, category: null));
    return list;
  }

  /// Minúsculas y sin tildes, para buscar sin importar cómo esté escrito.
  static String normalize(String text) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final buffer = StringBuffer();
    for (final ch in text.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      buffer.write(i < 0 ? ch : to[i]);
    }
    return buffer.toString();
  }

  bool _matches(
    Project p,
    ProjectFilter f,
    String query,
    DateTime now,
    String today,
  ) {
    if (query.isNotEmpty) {
      final haystack = normalize('${p.name} ${p.jiraKey ?? ''} ${p.description}');
      if (!haystack.contains(query)) return false;
    }
    if (f.statuses.isNotEmpty &&
        !f.statuses.contains(p.jiraStatus ?? ProjectFilter.noStatus)) {
      return false;
    }
    switch (f.origin) {
      case ProjectOrigin.jira when p.jiraKey == null:
      case ProjectOrigin.manual when p.jiraKey != null:
        return false;
      default:
    }
    switch (f.activity) {
      case ProjectActivity.running when !p.isRunning:
      case ProjectActivity.paused when p.isRunning:
        return false;
      default:
    }
    if (f.onlyUploadable &&
        !(p.jiraKey != null &&
            p.elapsed(now).inSeconds >= PrepareWorklog.minSeconds)) {
      return false;
    }
    if (f.onlyCarried && !p.carriesTimeBefore(today, now)) return false;
    if (f.hideDone && p.jiraStatusCategory == 'done' && !_stillNeeded(p, now)) {
      return false;
    }
    return true;
  }

  /// Un finalizado que corre ahora o que aún tiene tiempo por subir no se esconde: ocultarlo
  /// dejaría tiempo sin enviar fuera de la vista.
  bool _stillNeeded(Project p, DateTime now) =>
      p.isRunning ||
      (p.jiraKey != null &&
          p.elapsed(now).inSeconds >= PrepareWorklog.minSeconds);

  int _compare(Project a, Project b, ProjectSort sort, DateTime now) =>
      switch (sort) {
        ProjectSort.original => 0,
        ProjectSort.name => normalize(a.name).compareTo(normalize(b.name)),
        ProjectSort.mostTime => b.elapsed(now).compareTo(a.elapsed(now)),
        ProjectSort.runningFirst =>
          (b.isRunning ? 1 : 0).compareTo(a.isRunning ? 1 : 0),
        ProjectSort.status => () {
          final c = _rank(a.jiraStatusCategory).compareTo(
            _rank(b.jiraStatusCategory),
          );
          return c != 0
              ? c
              : normalize(a.name).compareTo(normalize(b.name));
        }(),
      };

  /// Posición de una categoría de Jira al ordenar por estado.
  static int _rank(String? category) => switch (category) {
    'new' => 0,
    'indeterminate' => 1,
    'done' => 2,
    _ => 3,
  };
}
