class JiraAuthException implements Exception {
  JiraAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// El access token ya no es válido (caducó o fue revocado).
class JiraUnauthorized implements Exception {
  const JiraUnauthorized();
}

class JiraApiException implements Exception {
  JiraApiException(this.message, {this.statusCode});
  final String message;

  /// Código HTTP de la respuesta, cuando el error viene de una.
  final int? statusCode;
  @override
  String toString() => message;
}
