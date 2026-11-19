/// `HH:MM:SS` para el cronómetro.
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

/// Duración legible para mostrar lo registrado: `1 h 05 m`, `12 m 05 s`, `40 s`.
String formatWorkDuration(Duration d) {
  final h = d.inHours,
      m = d.inMinutes.remainder(60),
      s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h h ${two(m)} m';
  if (m > 0) return '$m m ${two(s)} s';
  return '$s s';
}

/// Horas y minutos sin segundos, para totales y metas: `8 h`, `5 h 40 m`, `40 m`, `0 m`.
String formatHoursMinutes(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60);
  if (h > 0 && m == 0) return '$h h';
  if (h > 0) return '$h h $m m';
  return '$m m';
}

/// Frecuencia en palabras: `cada hora`, `cada 2 horas`, `cada 30 minutos`, `cada 1 h 30 min`.
String formatEvery(Duration d) {
  final m = d.inMinutes;
  if (m >= 60 && m % 60 == 0) {
    final h = m ~/ 60;
    return h == 1 ? 'cada hora' : 'cada $h horas';
  }
  if (m < 60) return m == 1 ? 'cada minuto' : 'cada $m minutos';
  return 'cada ${m ~/ 60} h ${m % 60} min';
}
