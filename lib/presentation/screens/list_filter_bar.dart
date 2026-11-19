import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/domain/entities/project_filter.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/list_filter_dialog.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Nombre de cada orden, tal como se ve en el menú y en el diálogo de filtros.
String sortLabel(ProjectSort sort) => switch (sort) {
  ProjectSort.original => 'Orden original',
  ProjectSort.name => 'Nombre (A–Z)',
  ProjectSort.mostTime => 'Más tiempo primero',
  ProjectSort.status => 'Por estado',
  ProjectSort.runningFirst => 'En curso primero',
};

/// Una sola fila bajo el progreso del día: búsqueda, orden y filtros. Con filtros activos
/// añade una línea «Mostrando X de Y · Limpiar». Una fila para no quitarle alto a la lista
/// en la ventana mínima.
class ListFilterBar extends StatefulWidget {
  const ListFilterBar({super.key, required this.controller});

  final ProjectsController controller;

  @override
  State<ListFilterBar> createState() => _ListFilterBarState();
}

class _ListFilterBarState extends State<ListFilterBar> {
  late final TextEditingController _search;

  ProjectsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: _c.filter.query);
    _c.addListener(_sync);
  }

  /// «Limpiar filtros» (u otra vía) cambia la búsqueda desde fuera: se refleja en el campo.
  void _sync() {
    if (_search.text != _c.filter.query) _search.text = _c.filter.query;
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final filter = _c.filter;
        final active = filter.activeCount;
        final shown = _c.visibleProjects.length;
        final hidden = _c.projects.length - shown;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            TileLimits.listInset,
            0,
            TileLimits.listInset,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: FilterBarLimits.height,
                child: Row(
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: FilterBarLimits.searchMinWidth,
                        ),
                        child: AppTextField.search(
                          controller: _search,
                          label: 'Buscar…',
                          onChanged: (v) => _c.setFilter(filter.copyWith(query: v)),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    PopupMenuButton<ProjectSort>(
                      tooltip: 'Ordenar: ${sortLabel(filter.sort)}',
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      constraints: const BoxConstraints(minWidth: 180),
                      icon: Icon(
                        AppIcons.sort,
                        color: filter.sort == ProjectSort.original
                            ? null
                            : scheme.primary,
                      ),
                      initialValue: filter.sort,
                      onSelected: (s) => _c.setFilter(filter.copyWith(sort: s)),
                      itemBuilder: (_) => [
                        for (final s in ProjectSort.values)
                          CheckedPopupMenuItem(
                            value: s,
                            checked: s == filter.sort,
                            child: Text(sortLabel(s)),
                          ),
                      ],
                    ),
                    Badge(
                      isLabelVisible: active > 0,
                      label: Text('$active'),
                      child: AppIconButton(
                        icon: AppIcons.filter,
                        tooltip: 'Filtros',
                        variant: active > 0
                            ? AppIconButtonVariant.tonal
                            : AppIconButtonVariant.plain,
                        onPressed: () => showListFilterDialog(context, _c),
                      ),
                    ),
                  ],
                ),
              ),
              if (filter.isActive || hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Text(
                        'Mostrando $shown de ${_c.projects.length}',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      InkWell(
                        // Con filtros activos «Limpiar» vuelve a lo normal; si solo hay
                        // finalizados ocultos, «Mostrar finalizados» los trae.
                        onTap: filter.isActive
                            ? _c.clearFilter
                            : () => _c.setFilter(filter.copyWith(hideDone: false)),
                        child: Text(
                          filter.isActive ? 'Limpiar' : 'Mostrar finalizados',
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
