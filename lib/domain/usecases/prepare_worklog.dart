/// Un registro de trabajo listo para enviar a Jira.
class Worklog {
  const Worklog({required this.seconds, required this.started});

  final int seconds;

  /// Hora de inicio: *ahora menos la duración*.
  final DateTime started;
}

/// El tiempo a registrar no cumple las reglas (demasiado corto o demasiado largo).
class InvalidWorklog implements Exception {
  const InvalidWorklog(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Decide qué registro se envía a Jira en un corte y lo valida.
///
/// Reglas (salvaguardas propias, no impuestas por Jira): entre 1 minuto y 24
/// horas. El mínimo evita registros sin sentido; el máximo atrapa errores de
/// tecleo (p. ej. 100 h en vez de 1 h).
class PrepareWorklog {
  const PrepareWorklog();

  static const minSeconds = 60;
  static const maxSeconds = 24 * 3600;

  /// `requested` es el tiempo que el usuario confirmó (puede haberlo editado); sin
  /// él se usa el medido.
  Worklog call({
    required Duration measured,
    Duration? requested,
    required DateTime now,
  }) {
    final seconds = (requested ?? measured).inSeconds;
    if (seconds < minSeconds) {
      throw const InvalidWorklog(
        'Hay menos de 1 minuto: no hay nada que registrar.',
      );
    }
    if (seconds > maxSeconds) {
      throw const InvalidWorklog(
        'Un registro no puede pasar de 24 horas. '
        'Revisa el tiempo o envíalo en varios cortes.',
      );
    }
    return Worklog(
      seconds: seconds,
      started: now.subtract(Duration(seconds: seconds)),
    );
  }
}
