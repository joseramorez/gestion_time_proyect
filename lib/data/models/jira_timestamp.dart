/// Formato de fecha que exige la API de worklogs de Jira:
/// `yyyy-MM-ddTHH:mm:ss.SSS+0000` en UTC (no sirve el `Z` de `toIso8601String`).
String jiraTimestamp(DateTime when) {
  final u = when.toUtc();
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${p(u.year, 4)}-${p(u.month)}-${p(u.day)}T${p(u.hour)}:${p(u.minute)}:'
      '${p(u.second)}.${p(u.millisecond, 3)}+0000';
}
