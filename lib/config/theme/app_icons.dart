import 'package:flutter/material.dart';

/// Todos los iconos de la app, con nombre por su **función** y no por su forma.
/// Ninguna pantalla usa `Icons.algo` directamente: si un icono cambia (o se
/// quiere otro conjunto), se cambia aquí y cambia en toda la app.
abstract final class AppIcons {
  // Barra superior
  static const IconData pin = Icons.push_pin_outlined;
  static const IconData pinActive = Icons.push_pin;
  static const IconData jira = Icons.cloud_sync_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData search = Icons.search_rounded;
  static const IconData clear = Icons.close_rounded;
  static const IconData filter = Icons.filter_list_rounded;
  static const IconData sort = Icons.sort_rounded;
  static const IconData opacity = Icons.opacity;
  static const IconData add = Icons.add;

  // Cronómetro y acciones de la tarjeta
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData reset = Icons.restart_alt_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData cutToJira = Icons.cloud_upload_outlined;

  // Edición
  static const IconData edit = Icons.edit_outlined;
  static const IconData delete = Icons.delete_outline_rounded;

  // Datos de un ticket
  static const IconData timer = Icons.timer_outlined;
  static const IconData sentToJira = Icons.cloud_done_outlined;
  static const IconData jiraTicket = Icons.task_alt_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData openExternal = Icons.open_in_new_rounded;

  // Vista simple
  /// Volver de la vista simple a la completa.
  static const IconData restoreView = Icons.open_in_full_rounded;

  // Utilidades
  static const IconData copy = Icons.copy;
  static const IconData copied = Icons.check;

  /// Marca la opción vigente de una lista (p. ej. el estado actual de un ticket).
  static const IconData current = Icons.check_rounded;
}
