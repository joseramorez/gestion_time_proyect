/// Valores de configuración que vienen de `.env`, compilados en la app con
/// `--dart-define-from-file=.env` (ver `docs/jira.md`). Cambiarlos exige recompilar.
abstract final class AppEnv {
  /// Horas que cuentan como un día de trabajo completo, de `DAILY_HOURS`.
  static const String _dailyHoursRaw = String.fromEnvironment('DAILY_HOURS');

  /// La meta diaria de esta compilación.
  static Duration get dailyGoal => parseDailyGoal(_dailyHoursRaw);

  static const String _dailyMinRaw = String.fromEnvironment('DAILY_MIN_HOURS');

  /// El mínimo aceptable del día, de `DAILY_MIN_HOURS` (por defecto 7 h). Nunca pasa
  /// de la meta: con una meta menor que el mínimo, el mínimo es la propia meta.
  static Duration get dailyMinimum =>
      parseDailyMinimum(_dailyMinRaw, dailyGoal);

  static const String _autoSyncRaw = String.fromEnvironment(
    'JIRA_AUTO_SYNC_HOURS',
  );

  /// Cada cuánto se sincroniza Jira solo (si el ajuste está activo), de
  /// `JIRA_AUTO_SYNC_HOURS` (por defecto 2 h).
  static Duration get jiraAutoSyncInterval =>
      parseAutoSyncInterval(_autoSyncRaw);

  /// Intervalo por defecto de la sincronización automática.
  static const Duration defaultAutoSyncInterval = Duration(hours: 2);

  /// Mínimo que se respeta: más seguido que esto no tiene sentido y sobrecargaría Jira.
  static const Duration minAutoSyncInterval = Duration(minutes: 5);

  /// Interpreta `JIRA_AUTO_SYNC_HOURS` (horas, con decimales: `2`, `0.5`, `1,5`). Vacío,
  /// no numérico, <= 0 o > 24 → 2 h; por debajo de 5 minutos se sube a 5 minutos.
  static Duration parseAutoSyncInterval(String raw) {
    final hours = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (hours == null || !hours.isFinite || hours <= 0 || hours > 24) {
      return defaultAutoSyncInterval;
    }
    final interval = Duration(minutes: (hours * 60).round());
    return interval < minAutoSyncInterval ? minAutoSyncInterval : interval;
  }

  /// Mínimo por defecto cuando `.env` no lo define o lo define mal.
  static const Duration defaultDailyMinimum = Duration(hours: 7);

  /// Interpreta `DAILY_MIN_HOURS` con las mismas reglas que la meta; un valor inválido
  /// usa 7 h. El resultado se recorta a `goal`.
  static Duration parseDailyMinimum(String raw, Duration goal) {
    final hours = double.tryParse(raw.trim().replaceAll(',', '.'));
    var min = defaultDailyMinimum;
    if (hours != null && hours.isFinite && hours > 0 && hours <= 24) {
      min = Duration(minutes: (hours * 60).round().clamp(1, 24 * 60));
    }
    return min > goal ? goal : min;
  }

  /// Meta por defecto cuando `.env` no la define o la define mal.
  static const Duration defaultDailyGoal = Duration(hours: 8);

  /// Interpreta el valor de `DAILY_HOURS`: horas como número, con decimales si hace
  /// falta (`8`, `7.5`, `7,5`). Un valor vacío, que no sea un número, menor o igual a
  /// cero o mayor de 24 se descarta y se usa la meta por defecto (8 h).
  static Duration parseDailyGoal(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    final hours = double.tryParse(text);
    if (hours == null || !hours.isFinite || hours <= 0 || hours > 24) {
      return defaultDailyGoal;
    }
    final minutes = (hours * 60).round();
    return Duration(minutes: minutes < 1 ? 1 : minutes);
  }
}
