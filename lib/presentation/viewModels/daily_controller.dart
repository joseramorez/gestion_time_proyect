import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gestion_time_proyect/domain/entities/day_key.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/repositories/work_log_repository.dart';
import 'package:gestion_time_proyect/domain/usecases/prepare_worklog.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

/// Envía un worklog a Jira; devuelve `null` si se aceptó o el texto del error.
typedef WorklogPoster =
    Future<String?> Function({
      required String issueKey,
      required int seconds,
      required DateTime started,
      String comment,
    });

/// Una subida pedida desde el corte: ticket, minutos y día trabajado (`null` = hoy).
class UploadRequest {
  const UploadRequest(this.projectId, this.minutes, [this.day]);

  final int projectId;
  final int minutes;
  final String? day;
}

/// Progreso del día y corte del día (opcional).
///
/// - `ticketsTotal`: suma de lo que marcan ahora los cronómetros de todos los tickets.
///   Si se limpia un ticket o se sube su tiempo con reinicio, deja de contar.
/// - `sentToday`: lo que se subió a Jira **hoy**; se ve aparte y no se suma al total
///   de los tickets. Al cambiar el día vuelve a cero.
/// - `upload` / `uploadAll`: suben a Jira horas y minutos (sin segundos) de uno o de
///   varios tickets. Nada bloquea al usuario: el corte lo abre él cuando quiere.
class DailyController extends ChangeNotifier {
  DailyController(
    this._projects,
    this._work, {
    required this.goal,
    this.minimum = const Duration(hours: 7),
    this._post,
    this._canPost = _never,
    this._clock = DateTime.now,
    this._rolloverCheck = const Duration(seconds: 30),
  });

  static bool _never() => false;

  final ProjectsController _projects;
  final WorkLogRepository _work;
  final WorklogPoster? _post;
  final bool Function() _canPost;
  final DateTime Function() _clock;
  final Duration _rolloverCheck;

  /// Meta diaria de horas (día completo).
  final Duration goal;

  /// Mínimo aceptable del día; solo referencia, nada se impone.
  final Duration minimum;

  Map<int, int> _sentToday = {};
  String _today = '';
  Timer? _timer;
  bool _sending = false;

  /// ¿Se está subiendo algo ahora mismo?
  bool get sending => _sending;

  /// Clave (`YYYY-MM-DD`) del día que se está contando.
  String get today => _today;

  Future<void> load() async {
    _today = dayKey(_clock());
    _sentToday = await _work.sentOn(_today);
    _timer?.cancel();
    _timer = Timer.periodic(_rolloverCheck, (_) => _checkRollover());
    notifyListeners();
  }

  /// ¿Puede la subida a Jira funcionar ahora (sesión con permiso de escritura)?
  bool get canSend => _post != null && _canPost();

  /// Suma de los cronómetros actuales de todos los tickets, en vivo.
  Duration get ticketsTotal => _projects.projects.fold(
    Duration.zero,
    (sum, p) => sum + p.elapsed(_clock()),
  );

  /// Lo subido a Jira hoy (aparte del total de los tickets).
  Duration get sentToday =>
      Duration(seconds: _sentToday.values.fold(0, (sum, s) => sum + s));

  /// Lo subido hoy por ticket: ticket → segundos.
  Map<int, int> get sentTodayByProject => Map.unmodifiable(_sentToday);

  /// Fracción de la meta que marcan los tickets ahora (puede pasar de 1).
  double get ticketsProgress => _fraction(ticketsTotal);

  /// Fracción de la meta que se subió hoy (puede pasar de 1).
  double get sentProgress => _fraction(sentToday);

  double _fraction(Duration d) =>
      goal.inMilliseconds == 0 ? 0 : d.inMilliseconds / goal.inMilliseconds;

  /// ¿Trae el ticket tiempo (al menos 1 minuto) de un día anterior?
  bool carriesOlderTime(Project project) =>
      project.carriesTimeBefore(_today, _clock());

  /// Tickets que traen tiempo de un día anterior.
  List<Project> get carriedOver => [
    for (final p in _projects.projects)
      if (carriesOlderTime(p)) p,
  ];

  /// ¿Está bloqueado **iniciar** este ticket? Sí si trae tiempo de un día anterior: hay
  /// que subirlo (o limpiarlo) antes de seguir, para no mezclar días en un mismo cronómetro.
  /// Solo afecta a ese ticket; pausar siempre se puede y un cronómetro en marcha no se
  /// detiene.
  bool isStartBlocked(Project project) =>
      !project.isRunning && carriesOlderTime(project);

  /// Día al que probablemente pertenece el tiempo del ticket: aquel desde el que viene
  /// si es anterior a hoy; si no, hoy.
  String suggestedDay(Project project) =>
      carriesOlderTime(project) ? project.timeSinceDay! : _today;

  /// El "registro anterior" del ticket (el otro escenario además de hoy): el día desde el
  /// que viene su tiempo si se sabe (puede ser de varios días atrás si no se registró desde
  /// la última vez que se usó la app); si no, el día hábil anterior.
  String previousDayFor(Project project) => carriesOlderTime(project)
      ? project.timeSinceDay!
      : previousWorkday(_today);

  /// Sube a Jira `minutes` minutos del ticket y los anota en el día `day`
  /// (`YYYY-MM-DD`; por defecto hoy) para el control interno de la app: a Jira solo viaja
  /// el tiempo. Devuelve `null` si Jira lo aceptó o el texto del error.
  ///
  /// Con `reset` (por defecto) el cronómetro se reinicia al subir; sin él conserva lo
  /// que sobre. Solo cuando Jira lo acepta cambia algo localmente.
  Future<String?> upload(
    Project project,
    int minutes, {
    bool reset = true,
    String? day,
  }) async {
    if (_sending) return 'Ya se está subiendo tiempo.';
    _sending = true;
    notifyListeners();
    try {
      return await _uploadOne(project, minutes, reset, day ?? _today);
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Sube varios tickets, uno por uno, cada uno con su día trabajado. Un fallo no
  /// detiene los demás. Devuelve el error de cada ticket que falló (vacío = todo subido);
  /// lo que sí se subió ya no se repite en un reintento porque su cronómetro cambió.
  Future<Map<int, String>> uploadAll(
    List<UploadRequest> items, {
    bool reset = true,
  }) async {
    if (_sending) {
      return {
        for (final i in items) i.projectId: 'Ya se está subiendo tiempo.',
      };
    }
    _sending = true;
    notifyListeners();
    final errors = <int, String>{};
    try {
      for (final item in items) {
        final matches = _projects.projects.where((p) => p.id == item.projectId);
        if (matches.isEmpty) continue;
        final error = await _uploadOne(
          matches.first,
          item.minutes,
          reset,
          item.day ?? _today,
        );
        if (error != null) errors[item.projectId] = error;
      }
      return errors;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<String?> _uploadOne(
    Project project,
    int minutes,
    bool reset,
    String day,
  ) async {
    final key = project.jiraKey;
    if (key == null || project.id == null) return 'Esta entrada no es de Jira.';
    final seconds = minutes * 60;
    if (seconds < PrepareWorklog.minSeconds) {
      return 'Mínimo 1 minuto para subir.';
    }
    if (seconds > PrepareWorklog.maxSeconds) {
      return 'Máximo 24 horas por registro.';
    }
    if (day.compareTo(_today) > 0) return 'No se puede subir a un día futuro.';
    final post = _post;
    if (post == null || !_canPost()) {
      return 'Inicia sesión en Jira con permiso de escritura.';
    }

    // A Jira solo viaja el TIEMPO (con `started = ahora − duración`, como el corte por
    // ticket): el día trabajado es solo control interno de la app.
    final error = await post(
      issueKey: key,
      seconds: seconds,
      started: _clock().subtract(Duration(seconds: seconds)),
      comment: '',
    );
    if (error != null) return error;

    // Jira ya lo aceptó: primero se descuenta del cronómetro (para no poder reenviarlo)
    // y luego se anota en el día trabajado; si eso falla, solo afecta a lo que se ve.
    await _projects.registerJiraCut(
      project,
      seconds * 1000,
      recordSent: false,
      reset: reset,
    );
    await _record(project.id!, seconds, day);
    return null;
  }

  /// Tickets en curso cuyo tiempo se puede subir ahora: de Jira y con al menos 1 minuto.
  List<Project> get uploadableRunning {
    final now = _clock();
    return [
      for (final p in _projects.running)
        if (p.jiraKey != null &&
            p.elapsed(now).inSeconds >= PrepareWorklog.minSeconds)
          p,
    ];
  }

  /// Pausa los tickets en curso y sube a Jira lo medido (horas y minutos, con reinicio),
  /// cada uno en su día de trabajo sugerido. Los que no se pueden subir (sin Jira o con
  /// menos de 1 minuto) solo se pausan. Devuelve el error de cada ticket que falló
  /// (vacío = todo bien); un ticket que falló queda pausado con su tiempo intacto.
  Future<Map<int, String>> pauseAndUploadRunning() async {
    final items = <UploadRequest>[];
    final upload = uploadableRunning.map((p) => p.id).toSet();
    final now = _clock();
    for (final p in _projects.running) {
      if (upload.contains(p.id)) {
        items.add(
          UploadRequest(p.id!, p.elapsed(now).inMinutes, suggestedDay(p)),
        );
      }
      await _projects.pause(p);
    }
    return uploadAll(items);
  }

  /// Anota un corte por ticket ya enviado (el diálogo de corte de un ticket) como
  /// subido hoy.
  Future<void> recordSent(Project project, int sentMs) async {
    final id = project.id;
    if (id == null) return;
    await _record(id, sentMs ~/ 1000, _today);
  }

  Future<void> _record(int projectId, int seconds, String day) async {
    if (dayKey(_clock()) != _today) await _checkRollover();
    // Solo lo subido para HOY se ve en "subido hoy"; lo de otros días se guarda por su fecha.
    if (day == _today) {
      _sentToday = {
        ..._sentToday,
        projectId: (_sentToday[projectId] ?? 0) + seconds,
      };
      notifyListeners();
    }
    try {
      await _work.addSent(day, projectId, seconds);
    } catch (e) {
      debugPrint('No se pudo guardar lo subido el $day: $e');
    }
  }

  Future<void> _checkRollover() async {
    final key = dayKey(_clock());
    if (key == _today) return;
    _today = key;
    _sentToday = await _work.sentOn(key);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
