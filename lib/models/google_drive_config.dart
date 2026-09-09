/// Configuración para Google Drive API con OAuth2
class GoogleDriveConfig {
  final int? id;
  final bool habilitado;
  final String? clientId; // Client ID de OAuth2
  final String? clientSecret; // Client Secret de OAuth2
  final String? accessToken; // Token de acceso
  final String? refreshToken; // Token de refresh
  final int? tokenExpiry; // Timestamp de expiración del token
  final String? carpetaId; // ID de la carpeta raíz en Drive
  final bool subirAutomaticamente; // Subir PDFs automáticamente al cerrar

  GoogleDriveConfig({
    this.id,
    this.habilitado = false,
    this.clientId,
    this.clientSecret,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiry,
    this.carpetaId,
    this.subirAutomaticamente = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'habilitado': habilitado ? 1 : 0,
      'client_id': clientId,
      'client_secret': clientSecret,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_expiry': tokenExpiry,
      'carpeta_id': carpetaId,
      'subir_automaticamente': subirAutomaticamente ? 1 : 0,
    };
  }

  factory GoogleDriveConfig.fromMap(Map<String, dynamic> map) {
    return GoogleDriveConfig(
      id: map['id'] as int?,
      habilitado: ((map['habilitado'] as int?) ?? 0) == 1,
      clientId: map['client_id'] as String?,
      clientSecret: map['client_secret'] as String?,
      accessToken: map['access_token'] as String?,
      refreshToken: map['refresh_token'] as String?,
      tokenExpiry: map['token_expiry'] as int?,
      carpetaId: map['carpeta_id'] as String?,
      subirAutomaticamente: ((map['subir_automaticamente'] as int?) ?? 1) == 1,
    );
  }

  GoogleDriveConfig copyWith({
    int? id,
    bool? habilitado,
    String? clientId,
    String? clientSecret,
    String? accessToken,
    String? refreshToken,
    int? tokenExpiry,
    String? carpetaId,
    bool? subirAutomaticamente,
  }) {
    return GoogleDriveConfig(
      id: id ?? this.id,
      habilitado: habilitado ?? this.habilitado,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
      carpetaId: carpetaId ?? this.carpetaId,
      subirAutomaticamente: subirAutomaticamente ?? this.subirAutomaticamente,
    );
  }

  /// Verifica si la configuración está completa y lista para usar
  bool get estaConfigurada {
    return habilitado &&
           clientId != null &&
           clientId!.isNotEmpty &&
           clientSecret != null &&
           clientSecret!.isNotEmpty &&
           accessToken != null &&
           accessToken!.isNotEmpty;
  }

  /// Verifica si hay credenciales OAuth configuradas (client_id y client_secret)
  bool get tieneCredencialesOAuth {
    return clientId != null &&
           clientId!.isNotEmpty &&
           clientSecret != null &&
           clientSecret!.isNotEmpty;
  }

  /// Verifica si está autenticado (tiene access token válido)
  bool get estaAutenticado {
    return accessToken != null && accessToken!.isNotEmpty;
  }
}
