import 'package:flutter/material.dart';

/// Nombres de las rutas de la app.
abstract final class AppRoutes {
  static const home = '/';
}

/// Rutas de la app. Hoy hay una sola pantalla (la lista de proyectos, que además
/// alterna con la vista simple dentro de sí misma), pero las rutas pasan por
/// aquí para que una pantalla nueva sea añadir una línea y no tocar `main.dart`.
///
/// Las pantallas reciben sus dependencias por el constructor (ver `main.dart`);
/// el router solo sabe construirlas, por eso `homeBuilder` llega de fuera.
class AppRouter {
  const AppRouter({required this.homeBuilder});

  final WidgetBuilder homeBuilder;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      AppRoutes.home => _route(settings, homeBuilder),
      _ => _route(
        settings,
        (_) => Scaffold(
          body: Center(child: Text('Ruta desconocida: ${settings.name}')),
        ),
      ),
    };
  }

  /// Sin animación de transición: la ventana es de escritorio y la pantalla
  /// principal debe aparecer de golpe al abrir la app.
  Route<dynamic> _route(RouteSettings settings, WidgetBuilder builder) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => builder(context),
    );
  }
}
