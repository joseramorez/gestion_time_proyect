/// Clave de un día del calendario **local**: `YYYY-MM-DD`.
///
/// Al ser texto con ceros a la izquierda, ordenar las claves alfabéticamente es
/// ordenarlas por fecha, y compararlas con `compareTo` equivale a comparar días.
/// El día se toma en la zona horaria local: "hoy" es el día que ve el usuario, no
/// el de UTC.
String dayKey(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
}

/// Medianoche local con que empieza el día `key`.
DateTime dayStartOf(String key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Día hábil (lunes a viernes) anterior a `key`: el día de antes entre semana, y el
/// viernes si `key` es lunes (o fin de semana).
String previousWorkday(String key) {
  var d = dayStartOf(key);
  do {
    d = DateTime(d.year, d.month, d.day - 1);
  } while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday);
  return dayKey(d);
}

/// Medianoche local con que empieza el día siguiente a `key` (maneja los días de 23 y
/// 25 horas por el cambio de hora, porque `DateTime` normaliza el día).
DateTime nextDayStartOf(String key) {
  final s = dayStartOf(key);
  return DateTime(s.year, s.month, s.day + 1);
}
