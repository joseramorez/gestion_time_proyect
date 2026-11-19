import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:gestion_time_proyect/core/services/window_service.dart';
import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/repositories/projects_repository.dart';
import 'package:gestion_time_proyect/domain/repositories/work_log_repository.dart';

/// Repositorio en memoria. Sirve para probar los view models sin SQLite, y es la
/// prueba de que dependen del contrato (`ProjectsRepository`) y no de la base.
class FakeProjectsRepository implements ProjectsRepository {
  final List<Project> rows = [];
  final Map<String, String> settings = {};
  int _nextId = 1;

  /// Cuántas veces se escribió cada preferencia (para comprobar "no se guarda").
  final Map<String, int> settingWrites = {};

  @override
  Future<List<Project>> projects() async => List.of(rows);

  @override
  Future<int> insert(Project project) async {
    final id = _nextId++;
    rows.add(project.withId(id));
    return id;
  }

  @override
  Future<void> update(Project project) async {
    final i = rows.indexWhere((p) => p.id == project.id);
    if (i >= 0) rows[i] = project;
  }

  @override
  Future<void> delete(int id) async => rows.removeWhere((p) => p.id == id);

  @override
  Future<bool> upsertJira(Project issue) async {
    final i = rows.indexWhere((p) => p.jiraKey == issue.jiraKey);
    if (i < 0) {
      rows.add(issue.withId(_nextId++));
      return true;
    }
    final old = rows[i];
    // Igual que la implementación real: no se toca el tiempo ni el cronómetro.
    rows[i] = Project(
      id: old.id,
      name: issue.name,
      description: issue.description,
      link: issue.link,
      accumulatedMs: old.accumulatedMs,
      startedAtMs: old.startedAtMs,
      timeSinceMs: old.timeSinceMs,
      jiraKey: old.jiraKey,
      jiraLoggedMs: old.jiraLoggedMs,
      jiraStatus: issue.jiraStatus,
      jiraStatusCategory: issue.jiraStatusCategory,
      jiraEstimateSeconds: issue.jiraEstimateSeconds,
      jiraRemainingSeconds: issue.jiraRemainingSeconds,
      jiraSpentSeconds: issue.jiraSpentSeconds,
    );
    return false;
  }

  @override
  Future<void> setJiraLive(Map<String, JiraLive> byKey) async {
    byKey.forEach((key, v) {
      final i = rows.indexWhere((p) => p.jiraKey == key);
      if (i < 0) return;
      final old = rows[i];
      rows[i] = Project(
        id: old.id,
        name: old.name,
        description: old.description,
        link: old.link,
        accumulatedMs: old.accumulatedMs,
        startedAtMs: old.startedAtMs,
        timeSinceMs: old.timeSinceMs,
        jiraKey: old.jiraKey,
        jiraLoggedMs: old.jiraLoggedMs,
        jiraStatus: v.status,
        jiraStatusCategory: v.category,
        jiraEstimateSeconds: v.estimateSeconds,
        jiraRemainingSeconds: v.remainingSeconds,
        jiraSpentSeconds: v.spentSeconds,
      );
    });
  }

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
    settingWrites[key] = (settingWrites[key] ?? 0) + 1;
  }
}

/// Registro de lo subido por día en memoria (mismas reglas que la versión con SQLite).
class FakeWorkLogRepository implements WorkLogRepository {
  /// día → ticket → segundos.
  final Map<String, Map<int, int>> sent = {};

  /// Si es `true`, `addSent` falla: simula un fallo de disco al anotar lo subido.
  bool failAddSent = false;

  @override
  Future<Map<int, int>> sentOn(String day) async => Map.of(sent[day] ?? {});

  @override
  Future<void> addSent(String day, int projectId, int seconds) async {
    if (failAddSent) throw StateError('no se pudo anotar');
    final perProject = sent.putIfAbsent(day, () => {});
    perProject[projectId] = (perProject[projectId] ?? 0) + seconds;
  }

  @override
  Future<void> deleteForProject(int projectId) async {
    for (final perProject in sent.values) {
      perProject.remove(projectId);
    }
  }
}

/// Servicio de ventana falso: anota lo que se le pide.
class FakeWindowService implements WindowService {
  final List<String> calls = [];
  double? lastOpacity;
  bool? lastAlwaysOnTop;

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    lastAlwaysOnTop = value;
    calls.add('alwaysOnTop:$value');
  }

  @override
  Future<void> setOpacity(double value) async {
    lastOpacity = value;
    calls.add('opacity:${value.toStringAsFixed(2)}');
  }

  @override
  Future<void> enterCompact({required double opacity}) async {
    lastOpacity = opacity;
    calls.add('enterCompact:${opacity.toStringAsFixed(2)}');
  }

  /// Última petición de ajuste (contenido y área de la vista).
  ({Size content, Size client})? lastFit;

  @override
  Future<void> fitCompact({required Size content, required Size client}) async {
    lastFit = (content: content, client: client);
    calls.add('fitCompact:${content.height.toStringAsFixed(1)}');
  }

  /// Simula que la ventana nativa falla al volver a la vista completa.
  bool throwOnExit = false;

  @override
  Future<void> exitCompact({required double opacity, required bool alwaysOnTop}) async {
    if (throwOnExit) throw StateError('la ventana no respondió');
    lastOpacity = opacity;
    lastAlwaysOnTop = alwaysOnTop;
    calls.add('exitCompact:${opacity.toStringAsFixed(2)}:$alwaysOnTop');
  }

  final _closeRequests = StreamController<void>.broadcast();
  bool preventClose = false;
  bool closed = false;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  @override
  Future<void> setPreventClose(bool value) async {
    preventClose = value;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  /// Simula que el usuario pulsa la X de la ventana.
  void requestClose() => _closeRequests.add(null);
}
