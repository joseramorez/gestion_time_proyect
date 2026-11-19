import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Franja bajo la barra superior con el progreso del día frente a la meta:
/// "Hoy 5 h 40 m / 8 h" (suma de lo que marcan ahora los tickets) y, aparte y en
/// verde, "subido hoy 2 h" (lo ya enviado a Jira hoy). La barra tiene dos tramos: los
/// tickets y lo subido. A la derecha, el botón del corte del día.
class DayProgressBar extends StatelessWidget {
  const DayProgressBar({super.key, required this.daily, required this.onCut});

  final DailyController daily;

  /// Abre el corte del día (lo decide el usuario, no se abre solo).
  final VoidCallback onCut;

  static const tooltip =
      'Suma de lo que marcan ahora todos los tickets frente a la meta '
      'diaria. En verde, lo subido a Jira hoy.';
  static const cutTooltip = 'Corte del día: subir el tiempo a Jira';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final total = daily.ticketsTotal;
    final sent = daily.sentToday;
    final reached = total >= daily.goal;
    final sentColor = AppColors.onSuccess(brightness);

    // Tramos de la barra, sin pasar de la meta: primero los tickets, luego lo subido.
    final a = daily.ticketsProgress.clamp(0.0, 1.0);
    final b = daily.sentProgress.clamp(0.0, 1.0 - a);
    final flexA = (a * 1000).round();
    final flexB = (b * 1000).round();
    final flexRest = 1000 - flexA - flexB;
    final carried = daily.carriedOver.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TileLimits.listInset,
        AppSpacing.xs,
        TileLimits.listInset,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: tooltip,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              'Hoy ${formatHoursMinutes(total)} / ${formatHoursMinutes(daily.goal)}',
                          style: TextStyle(
                            color: reached
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        if (sent.inSeconds >= 60)
                          TextSpan(
                            text: ' · subido ${formatHoursMinutes(sent)}',
                            style: TextStyle(color: sentColor),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 4,
                      child: Row(
                        children: [
                          if (flexA > 0)
                            Expanded(
                              flex: flexA,
                              child: ColoredBox(color: scheme.primary),
                            ),
                          if (flexB > 0)
                            Expanded(
                              flex: flexB,
                              child: ColoredBox(color: AppColors.success()),
                            ),
                          if (flexRest > 0)
                            Expanded(
                              flex: flexRest,
                              child: ColoredBox(
                                color: scheme.surfaceContainerHighest,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (carried > 0)
                    InkWell(
                      onTap: onCut,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          carried == 1
                              ? 'Un ticket con tiempo de días anteriores · ver corte'
                              : '$carried tickets con tiempo de días anteriores · ver corte',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppIconButton(
            icon: AppIcons.cutToJira,
            size: AppIconButtonSize.compact,
            tooltip: cutTooltip,
            onPressed: onCut,
          ),
        ],
      ),
    );
  }
}
