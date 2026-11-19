import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/data/models/project_filter_model.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/entities/project_filter.dart';
import 'package:gestion_time_proyect/domain/repositories/projects_repository.dart';
import 'package:gestion_time_proyect/domain/repositories/work_log_repository.dart';
import 'package:gestion_time_proyect/domain/usecases/apply_jira_cut.dart';
import 'package:gestion_time_proyect/domain/usecases/clear_project.dart';
import 'package:gestion_time_proyect/domain/usecases/filter_projects.dart';
import 'package:gestion_time_proyect/domain/usecases/pause_project.dart';
import 'package:gestion_time_proyect/domain/usecases/start_project.dart';

/// Estado de la lista de proyectos y de las preferencias de ventana.
///
/// Es un view model: guarda el estado que ve la interfaz, notifica los cambios y
/// delega en el dominio las **reglas** (casos de uso: iniciar, pausar, limpiar,
/// corte a Jira) y en el repositorio el **almacenamiento**. Cada cambio se
/// guarda al instante.
class ProjectsController extends ChangeNotifier {
  ProjectsController(
    this._repo, {
    this._work,
    this._canStart = _alwaysTrue,
    this._onJiraSent,
    this._clock = DateTime.now,
    this._startProject = const StartProject(),
    this._pauseProject = const PauseProject(),
    this._clearProject = const ClearProject(),
    this._applyJiraCut = const ApplyJiraCut(),
  });

  static bool _alwaysTrue(Project _) => true;

  final ProjectsRepository _repo;

  /// ¿Se puede iniciar este ticket? Lo decide quien monta la app (hoy: no si trae tiempo
  /// de un día anterior sin subir). Solo bloquea INICIAR; pausar siempre se puede.
  final bool Function(Project project) _canStart;

  /// Registro de lo subido a Jira por día; solo se usa al borrar un ticket.
  final WorkLogRepository? _work;

  /// Se llama tras un corte por ticket, con lo enviado: el progreso del día lo anota
  /// como "subido hoy" (ver `DailyController`).
  final FutureOr<void> Function(Project project, int sentMs)? _onJiraSent;

  final DateTime Function() _clock;
  final StartProject _startProject;
  final PauseProject _pauseProject;
  final ClearProject _clearProject;
  final ApplyJiraCut _applyJiraCut;

  List<Project> _projects = [];
  bool _alwaysOnTop = false;
  Timer? _ticker;

  List<Project> get projects => List.unmodifiable(_projects);

  bool get alwaysOnTop => _alwaysOnTop;

  static const minOpacity = 0.3;
  double _opacity = 1.0;
  double get opacity => _opacity;

  /// Transparencia de la vista simple: se guarda aparte de la de la vista completa.
  double _compactOpacity = 1.0;
  double get compactOpacity => _compactOpacity;

  Future<void> setCompactOpacity(double value, {bool persist = true}) async {
    _compactOpacity = value.clamp(minOpacity, 1.0).toDouble();
    notifyListeners();
    if (persist) {
      await _repo.setSetting('opacity_compact', _compactOpacity.toString());
    }
  }

  /// ¿Se está mostrando la vista simple? No se guarda: la app siempre arranca en
  /// la vista completa (la simple no tiene controles, y si arrancara en ella
  /// tras un cierre habría que saber salir de una ventana que no se ve).
  bool _compactMode = false;
  bool get compactMode => _compactMode;

  /// La vista simple muestra el ticket en curso: sin uno no tiene sentido y no se
  /// permite entrar en ella.
  bool get canUseCompactMode => _projects.any((p) => p.isRunning);

  /// Cambia de vista. Entrar en la simple se ignora si no hay un ticket en curso.
  void setCompactMode(bool value) {
    if (_compactMode == value) return;
    if (value && !canUseCompactMode) return;
    _compactMode = value;
    notifyListeners();
  }

  /// Cambia la transparencia de la ventana (1.0 = opaca). Con `persist: false`
  /// solo actualiza el estado, útil mientras se arrastra el control deslizante.
  Future<void> setOpacity(double value, {bool persist = true}) async {
    _opacity = value.clamp(minOpacity, 1.0).toDouble();
    notifyListeners();
    if (persist) await _repo.setSetting('opacity', _opacity.toString());
  }

  Future<void> load() async {
    _projects = await _repo.projects();
    _alwaysOnTop = (await _repo.setting('always_on_top')) == '1';
    _confirmClose = (await _repo.setting('confirm_close')) != '0';
    _autoSyncJira = (await _repo.setting('jira_auto_sync')) != '0';
    _filter = ProjectFilterModel.tryParse(await _repo.setting('list_filter'));
    final saved = double.tryParse(await _repo.setting('opacity') ?? '');
    if (saved != null) _opacity = saved.clamp(minOpacity, 1.0).toDouble();
    final savedCompact = double.tryParse(
      await _repo.setting('opacity_compact') ?? '',
    );
    if (savedCompact != null) {
      _compactOpacity = savedCompact.clamp(minOpacity, 1.0).toDouble();
    }
    _syncTicker();
    notifyListeners();
  }

  /// ¿Preguntar antes de cerrar la app? Por defecto sí.
  bool _confirmClose = true;
  bool get confirmClose => _confirmClose;

  Future<void> setConfirmClose(bool value) async {
    _confirmClose = value;
    notifyListeners();
    await _repo.setSetting('confirm_close', value ? '1' : '0');
  }

  /// ¿Sincronizar Jira automáticamente cada cierto tiempo? Por defecto sí (solo actúa
  /// con la sesión de Jira iniciada).
  bool _autoSyncJira = true;
  bool get autoSyncJira => _autoSyncJira;

  Future<void> setAutoSyncJira(bool value) async {
    _autoSyncJira = value;
    notifyListeners();
    await _repo.setSetting('jira_auto_sync', value ? '1' : '0');
  }

  // --- Búsqueda, filtros y orden de la lista (solo afectan a lo que se dibuja) ---

  static const _filterProjects = FilterProjects();
  ProjectFilter _filter = ProjectFilter.initial;
  ProjectFilter get filter => _filter;

  /// La lista tal como se ve: con la búsqueda, los filtros y el orden aplicados.
  /// `projects` sigue teniendo todo (totales del día, vista simple, etc.).
  List<Project> get visibleProjects =>
      _filterProjects(_projects, _filter, _clock());

  /// Cuántas entradas oculta el filtro.
  int get hiddenCount => _projects.length - visibleProjects.length;

  /// Estados de Jira presentes en la lista, para ofrecerlos como filtro.
  List<StatusOption> get statusOptions => _filterProjects.statusesIn(_projects);

  /// Cambia la búsqueda, los filtros o el orden. Se guardan al instante, salvo la
  /// búsqueda (cambiarla no escribe nada).
  Future<void> setFilter(ProjectFilter value) async {
    final before = ProjectFilterModel.toJson(_filter);
    _filter = value;
    notifyListeners();
    final after = ProjectFilterModel.toJson(value);
    if (after != before) await _repo.setSetting('list_filter', after);
  }

  /// Quita la búsqueda y los filtros (conserva el orden elegido).
  Future<void> clearFilter() => setFilter(_filter.cleared);

  /// Tickets con el cronómetro en marcha.
  List<Project> get running => [
    for (final p in _projects)
      if (p.isRunning) p,
  ];

  Future<void> setAlwaysOnTop(bool value) async {
    _alwaysOnTop = value;
    notifyListeners();
    await _repo.setSetting('always_on_top', value ? '1' : '0');
  }

  Future<void> add(String name, String description, String link) async {
    final draft = Project(name: name, description: description, link: link);
    final id = await _repo.insert(draft);
    _projects = [..._projects, draft.withId(id)];
    notifyListeners();
  }

  /// Incorpora issues de Jira. Los ya importados se actualizan sin perder su
  /// tiempo; los que dejaron de estar asignados al usuario se conservan.
  Future<({int added, int updated})> importJira(List<Project> issues) async {
    var added = 0, updated = 0;
    for (final issue in issues) {
      if (await _repo.upsertJira(issue)) {
        added++;
      } else {
        updated++;
      }
    }
    _projects = await _repo.projects();
    notifyListeners();
    return (added: added, updated: updated);
  }

  /// Refresca el estado y el seguimiento de tiempo de Jira de entradas ya
  /// importadas (por clave), sin tocar nada más.
  Future<void> updateJiraLive(Map<String, JiraLive> byKey) async {
    if (byKey.isEmpty) return;
    await _repo.setJiraLive(byKey);
    _projects = await _repo.projects();
    notifyListeners();
  }

  Future<void> edit(
    Project project, {
    required String name,
    required String description,
    required String link,
  }) {
    return _replace(
      project.copyWith(name: name, description: description, link: link),
    );
  }

  Future<void> remove(Project project) async {
    await _repo.delete(project.id!);
    await _work?.deleteForProject(project.id!);
    _projects = _projects.where((p) => p.id != project.id).toList();
    _syncTicker();
    notifyListeners();
  }

  /// Inicia o reanuda. Solo un proyecto corre a la vez: pausa los demás.
  Future<void> start(Project project) async {
    // Segunda barrera (la primera es el botón desactivado). Sin permiso no se hace nada,
    // ni siquiera se pausa el ticket que estuviera corriendo.
    if (!_canStart(project)) return;
    final now = _clock();
    final changed = _startProject(_projects, project.id!, now);
    for (final p in changed) {
      await _replace(p);
    }
  }

  Future<void> pause(Project project) async {
    final now = _clock();
    final paused = _pauseProject(_byId(project.id!), now);
    if (paused != null) await _replace(paused);
  }

  /// Limpiar: deja el tiempo en cero y detiene el cronómetro.
  Future<void> clear(Project project) async {
    await _replace(_clearProject(_byId(project.id!)));
  }

  /// Corte hacia Jira: `sentMs` ya quedó registrado como worklog (ver `ApplyJiraCut`).
  ///
  /// `reset: true` reinicia el cronómetro (queda en cero aunque sobrara tiempo, como
  /// los segundos que no se suben). `recordSent: false` lo usa el corte del día, que ya
  /// anota por su cuenta lo subido; sin eso se contaría dos veces.
  Future<void> registerJiraCut(
    Project project,
    int sentMs, {
    bool recordSent = true,
    bool reset = false,
  }) async {
    final now = _clock();
    await _replace(
      _applyJiraCut(_byId(project.id!), sentMs, now, reset: reset),
    );
    if (recordSent) await _onJiraSent?.call(project, sentMs);
  }

  Project _byId(int id) => _projects.firstWhere((p) => p.id == id);

  Future<void> _replace(Project updated) async {
    await _repo.update(updated);
    _projects = [for (final p in _projects) p.id == updated.id ? updated : p];
    _syncTicker();
    notifyListeners();
  }

  void _syncTicker() {
    final running = _projects.any((p) => p.isRunning);
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
