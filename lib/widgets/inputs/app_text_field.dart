import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestion_time_proyect/config/theme/app_icons.dart';
import 'package:gestion_time_proyect/config/theme/app_limits.dart';
import 'package:gestion_time_proyect/config/theme/app_tokens.dart';
import 'package:gestion_time_proyect/widgets/buttons/app_icon_button.dart';

/// Campo de texto de la app. Es la única forma de poner un campo: el aspecto
/// (fondo, bordes, radio, relleno) sale de `AppTheme`, y los límites (líneas,
/// dígitos) de `FieldLimits`, así todos los campos se ven y se comportan igual.
///
/// Variantes:
///  * `AppTextField(...)`: una línea (nombre, enlace, Client ID).
///  * `AppTextField.multiline(...)`: varias líneas con tope (descripción,
///    comentario).
///  * `AppTextField.secret(...)`: oculta lo que se escribe (Client Secret).
///  * `AppTextField.digits(...)`: solo dígitos, centrado y compacto (horas,
///    minutos y segundos).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
  }) : maxLines = 1,
       obscure = false,
       search = false,
       digitsOnly = false,
       maxLength = null;

  const AppTextField.multiline({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    int maxLines = FieldLimits.multilineDefault,
  }) : maxLines = maxLines < 1
           ? 1
           : (maxLines > FieldLimits.maxLinesCap
                 ? FieldLimits.maxLinesCap
                 : maxLines),
       obscure = false,
       search = false,
       digitsOnly = false,
       maxLength = null;

  /// Campo de búsqueda: una línea densa, con lupa y un botón para borrar lo escrito.
  const AppTextField.search({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
  }) : helper = null,
       validator = null,
       autofocus = false,
       enabled = true,
       maxLines = 1,
       obscure = false,
       digitsOnly = false,
       maxLength = null,
       search = true;

  const AppTextField.secret({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.enabled = true,
    this.onChanged,
  }) : maxLines = 1,
       obscure = true,
       search = false,
       digitsOnly = false,
       maxLength = null,
       validator = null,
       autofocus = false;

  const AppTextField.digits({
    super.key,
    required this.controller,
    required this.label,
    required int this.maxLength,
    this.enabled = true,
    this.onChanged,
  }) : maxLines = 1,
       obscure = false,
       search = false,
       digitsOnly = true,
       helper = null,
       validator = null,
       autofocus = false;

  final TextEditingController controller;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  final int maxLines;
  final bool search;
  final bool obscure;
  final bool digitsOnly;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    if (search) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: label,
            isDense: true,
            prefixIcon: const Icon(AppIcons.search, size: 18),
            suffixIcon: value.text.isEmpty
                ? null
                : AppIconButton(
                    icon: AppIcons.clear,
                    tooltip: 'Borrar búsqueda',
                    size: AppIconButtonSize.compact,
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                  ),
          ),
        ),
      );
    }
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      minLines: maxLines > 1 ? 1 : null,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      keyboardType: digitsOnly ? TextInputType.number : null,
      textAlign: digitsOnly ? TextAlign.center : TextAlign.start,
      inputFormatters: [
        if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        floatingLabelAlignment: digitsOnly
            ? FloatingLabelAlignment.center
            : FloatingLabelAlignment.start,
        contentPadding: digitsOnly
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 10)
            : null,
      ),
    );
  }
}
