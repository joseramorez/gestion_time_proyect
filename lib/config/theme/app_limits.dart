import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:gestion_time_proyect/config/theme/app_tokens.dart';

/// Límites de cada componente y de cada vista. Son los números que hacen que las
/// piezas "se acuerden" entre sí: por ejemplo, el hueco que le queda a la
/// etiqueta de estado en una tarjeta sale de restar a la ventana mínima todo lo
/// que ocupan los demás elementos de la fila. Si se cambia un límite aquí, las
/// pruebas de `test/core/ui_kit_test.dart` avisan si algo deja de caber.
///
/// Regla: un componente o pantalla lee su medida de aquí; no la inventa.

/// Ventana de la aplicación.
abstract final class WindowLimits {
  /// Tamaño MÍNIMO de la ventana completa: 360×242 (la medida original 300×220 más un
  /// 20 % de ancho y un 10 % de alto, para que quepa la etiqueta de estado de Jira
  /// en el centro de cada tarjeta). Ya no es el tamaño de arranque: ver `startFor`.
  static const Size min = Size(360, 242);

  /// Tamaño de ARRANQUE de la ventana completa: un cuarto de la pantalla (la mitad de
  /// ancho y la mitad de alto), sin bajar nunca del mínimo (`min`). `screen` es el
  /// tamaño de la pantalla en píxeles lógicos.
  static Size startFor(Size screen) => Size(
    math.max(min.width, screen.width / 2),
    math.max(min.height, screen.height / 2),
  );

  /// Vista simple (ticket en curso + deslizador de transparencia): tamaño de PARTIDA,
  /// 280×140. El ancho es
  /// fijo; el alto se ajusta solo al contenido (`CompactView.onFit` →
  /// `WindowService.fitCompact`), porque la barra de título del sistema ocupa más o
  /// menos según el equipo y la escala de pantalla, y una cifra fija se queda corta
  /// en unos y sobrada en otros.
  static const Size compact = Size(280, 140);

  /// Mínimo que admite la ventana simple mientras se ajusta: lo bastante bajo para
  /// que quepa la barra de título y una sola línea de contenido.
  static const Size compactMin = Size(280, 60);
}

/// Vista simple (`CompactView`).
abstract final class CompactLimits {
  /// El nombre del ticket ocupa una sola línea.
  static const int nameMaxLines = 1;

  /// Alto de la fila del deslizador de transparencia.
  static const double opacityRowHeight = 28;
}

/// Etiquetas (`AppChip`).
abstract final class ChipLimits {
  /// Ancho máximo absoluto de una etiqueta; más allá se recorta con "…".
  static const double maxWidth = 240;

  /// Una etiqueta nunca ocupa más de una línea.
  static const int maxLines = 1;
}

/// Campos de texto (`AppTextField`).
abstract final class FieldLimits {
  /// Tope de líneas de cualquier campo multilínea.
  static const int maxLinesCap = 6;

  /// Líneas por defecto de un campo multilínea (descripción, comentario).
  static const int multilineDefault = 4;

  /// Dígitos de los campos de duración del corte a Jira.
  static const int hoursDigits = 3;
  static const int minutesSecondsDigits = 2;
}

/// Diálogos.
abstract final class DialogLimits {
  /// Ancho del contenido de formularios y diálogos normales (alta/edición,
  /// Jira, corte).
  static const double formWidth = 300;

  /// Ancho del contenido de diálogos pequeños (p. ej. transparencia).
  static const double compactWidth = 260;

  /// Ancho máximo del detalle del ticket.
  static const double infoMaxWidth = 420;

  /// Por debajo de este alto disponible, el detalle pasa a su versión compacta
  /// (nombre en una línea y sin rótulos de sección).
  static const double infoCompactBelow = 170;
}

/// Tarjeta de la lista (`ProjectTile`).
///
/// Fila de controles, de izquierda a derecha:
/// `[play] [cronómetro] [— etiqueta de estado —] [acciones…]`
/// Todo salvo la etiqueta tiene ancho fijo; la etiqueta ocupa el hueco central.
abstract final class TileLimits {
  /// Relleno horizontal de la lista, a cada lado.
  static const double listInset = 10;

  /// Relleno de la tarjeta (izquierda y derecha) y grosor del borde.
  static const double paddingLeft = 10;
  static const double paddingRight = 6;
  static const double border = 1.5;

  /// Separación entre el botón de play y el cronómetro.
  static const double gap = AppSpacing.sm;

  /// Ancho máximo del bloque cronómetro + "En Jira"; si no cabe, se reduce.
  static const double timeMaxWidth = 96;

  /// Acciones a la derecha: limpiar, cortar a Jira (solo tickets de Jira) e
  /// información.
  static const int maxActions = 3;

  /// Ancho mínimo que debe tener el hueco de la etiqueta de estado para que se
  /// lea un estado corto ("Por hacer", "En curso") sin recortarlo.
  static const double statusSlotMinWidth = 84;

  /// Líneas del nombre.
  static const int nameMaxLines = 1;

  /// Ancho que ocupan los elementos de ancho fijo de la fila.
  static double fixedWidth({int actions = maxActions}) =>
      AppIconButtonSize.large.box +
      gap +
      timeMaxWidth +
      actions * AppIconButtonSize.compact.box;

  /// Hueco que le queda a la etiqueta de estado en una ventana de `windowWidth`.
  static double statusSlotWidth(
    double windowWidth, {
    int actions = maxActions,
  }) =>
      windowWidth -
      2 * listInset -
      (paddingLeft + paddingRight) -
      2 * border -
      fixedWidth(actions: actions);
}

/// Barra de búsqueda, orden y filtros de la lista (una sola fila bajo el progreso del día).
abstract final class FilterBarLimits {
  /// Alto de la fila: el del botón regular, para que la barra no robe alto a la lista
  /// en la ventana mínima (360×242).
  static double get height => AppIconButtonSize.regular.box + AppSpacing.sm;

  /// El campo de búsqueda se encoge, pero no por debajo de esto.
  static const double searchMinWidth = 120;
}
