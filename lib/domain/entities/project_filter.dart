/// De dónde viene una entrada de la lista.
enum ProjectOrigin { all, jira, manual }

/// Si el cronómetro de la entrada corre o no.
enum ProjectActivity { all, running, paused }

/// Orden de la lista. `original` es el de siempre (el de inserción).
enum ProjectSort { original, name, mostTime, status, runningFirst }

/// Lo que el usuario pidió ver de la lista: búsqueda, estados, origen, actividad,
/// atajos y orden. Es solo un valor; las reglas están en `FilterProjects`.
class ProjectFilter {
  const ProjectFilter({
    this.query = '',
    this.statuses = const {},
    this.origin = ProjectOrigin.all,
    this.activity = ProjectActivity.all,
    this.onlyUploadable = false,
    this.onlyCarried = false,
    this.hideDone = true,
    this.sort = ProjectSort.original,
  });

  /// Nombre con el que se agrupan las entradas sin estado de Jira (manuales o aún sin
  /// sincronizar) en el filtro de estados.
  static const noStatus = 'Sin estado';

  static const initial = ProjectFilter();

  /// Texto a buscar en nombre, clave y descripción.
  final String query;

  /// Estados de Jira a mostrar; vacío = todos.
  final Set<String> statuses;
  final ProjectOrigin origin;
  final ProjectActivity activity;

  /// Solo entradas de Jira con al menos 1 minuto medido (lo que se puede subir).
  final bool onlyUploadable;

  /// Solo entradas que arrastran tiempo de un día anterior sin subir.
  final bool onlyCarried;

  /// Oculta las entradas cuyo estado de Jira es de categoría "terminado". Es lo normal
  /// (viene activado): no cuenta como filtro; lo que sí cuenta es mostrarlas. Nunca oculta
  /// una entrada que corre ahora ni una con tiempo por subir (ver `FilterProjects`).
  final bool hideDone;
  final ProjectSort sort;

  /// Cuántos filtros hay activos, es decir, cuánto se aparta de lo normal (el orden no
  /// cuenta; ocultar finalizados tampoco, porque viene activado: cuenta mostrarlos).
  int get activeCount =>
      (query.trim().isEmpty ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (origin == ProjectOrigin.all ? 0 : 1) +
      (activity == ProjectActivity.all ? 0 : 1) +
      (onlyUploadable ? 1 : 0) +
      (onlyCarried ? 1 : 0) +
      (hideDone ? 0 : 1);

  bool get isActive => activeCount > 0;

  /// Igual pero sin búsqueda ni filtros, conservando el orden elegido.
  ProjectFilter get cleared => ProjectFilter(sort: sort);

  ProjectFilter copyWith({
    String? query,
    Set<String>? statuses,
    ProjectOrigin? origin,
    ProjectActivity? activity,
    bool? onlyUploadable,
    bool? onlyCarried,
    bool? hideDone,
    ProjectSort? sort,
  }) => ProjectFilter(
    query: query ?? this.query,
    statuses: statuses ?? this.statuses,
    origin: origin ?? this.origin,
    activity: activity ?? this.activity,
    onlyUploadable: onlyUploadable ?? this.onlyUploadable,
    onlyCarried: onlyCarried ?? this.onlyCarried,
    hideDone: hideDone ?? this.hideDone,
    sort: sort ?? this.sort,
  );
}
