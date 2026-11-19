/// Horas y minutos enteros (sin segundos).
typedef HoursMinutes = ({int hours, int minutes});

/// Al subir tiempo a Jira solo se trabaja con horas y minutos: los segundos no se
/// tienen en cuenta.
class SplitMinutes {
  const SplitMinutes();

  /// Horas y minutos de `d`, **truncando** los segundos (`1:23:40` → `1 h 23 m`).
  HoursMinutes call(Duration d) =>
      (hours: d.inHours, minutes: d.inMinutes.remainder(60));

  /// Minutos enteros de `d`, truncando los segundos.
  static int wholeMinutes(Duration d) => d.inMinutes;

  /// Segundos de `hours` h y `minutes` min (siempre múltiplo de 60).
  static int seconds(int hours, int minutes) => hours * 3600 + minutes * 60;
}
