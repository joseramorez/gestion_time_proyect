import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

/// Formulario para crear o editar un proyecto/ticket.
Future<void> showProjectForm(
  BuildContext context,
  ProjectsController controller, {
  Project? existing,
}) {
  final name = TextEditingController(text: existing?.name ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final link = TextEditingController(text: existing?.link ?? '');
  final formKey = GlobalKey<FormState>();

  return showFittedDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Nuevo proyecto / ticket' : 'Editar'),
      content: AppDialogBody(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: name,
                label: 'Nombre',
                autofocus: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField.multiline(
                controller: description,
                label: 'Descripción',
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(controller: link, label: 'Enlace'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final n = name.text.trim(),
                d = description.text.trim(),
                l = link.text.trim();
            if (existing == null) {
              await controller.add(n, d, l);
            } else {
              await controller.edit(existing, name: n, description: d, link: l);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
