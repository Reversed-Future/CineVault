class RemoteAuth {
  static bool isAuthorized({
    required String? authorizationHeader,
    required String expectedToken,
  }) {
    final token = expectedToken.trim();
    if (token.isEmpty) {
      return false;
    }

    final header = authorizationHeader?.trim();
    if (header == null || !header.startsWith('Bearer ')) {
      return false;
    }

    return header.substring('Bearer '.length).trim() == token;
  }

  static bool isTokenAuthorized({
    required String? providedToken,
    required String expectedToken,
  }) {
    final token = expectedToken.trim();
    return token.isNotEmpty && providedToken?.trim() == token;
  }
}
