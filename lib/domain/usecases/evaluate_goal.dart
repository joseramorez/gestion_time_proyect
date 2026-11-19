/// Cómo queda el total del día frente a la meta y al mínimo:
/// `short` (menos del mínimo), `acceptable` (del mínimo a la meta, sin llegar),
/// `met` (justo la meta) u `over` (más de la meta: permitido).
enum GoalStatus { short, acceptable, met, over }

/// Compara un total de horas con la meta del día. Es solo una **referencia**: no
/// impide nada, solo dice cómo va el día.
///
/// Se compara en minutos (un parte de horas no lleva segundos): `7 h 59 m 40 s`
/// cuenta como `8 h`. El mínimo nunca pasa de la meta.
class EvaluateGoal {
  const EvaluateGoal();

  static int _minutes(Duration d) => (d.inSeconds / 60).round();

  GoalStatus call({
    required Duration total,
    required Duration goal,
    required Duration minimum,
  }) {
    final totalMin = _minutes(total);
    final goalMin = goal.inMinutes;
    final minMin = minimum > goal ? goalMin : minimum.inMinutes;
    if (totalMin < minMin) return GoalStatus.short;
    if (totalMin < goalMin) return GoalStatus.acceptable;
    if (totalMin > goalMin) return GoalStatus.over;
    return GoalStatus.met;
  }

  /// Cuánto falta o sobra respecto a la meta (siempre positivo; el signo lo da
  /// `call`).
  Duration difference({required Duration total, required Duration goal}) =>
      Duration(minutes: (_minutes(total) - goal.inMinutes).abs());
}
