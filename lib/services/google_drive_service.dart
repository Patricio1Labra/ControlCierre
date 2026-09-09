import 'dart:async';
import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/google_drive_config.dart';
import 'database_service.dart';
import 'logger_service.dart';

class GoogleDriveService {
  drive.DriveApi? _driveApi;
  AutoRefreshingAuthClient? _authClient;

  /// Inicia el flujo OAuth2 para obtener credenciales
  ///
  /// Abre el navegador para que el usuario autorice la aplicación
  /// Retorna true si el flujo completó exitosamente
  Future<bool> iniciarFlujoOAuth({
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      await logger.info('GoogleDrive', '========== INICIANDO FLUJO OAUTH2 ==========');
      await logger.info('GoogleDrive', 'Client ID: $clientId');

      // Crear credenciales de cliente
      final credentials = ClientId(clientId, clientSecret);

      // Scopes necesarios para Google Drive
      final scopes = [drive.DriveApi.driveFileScope];

      // Puerto para el servidor local que recibirá el callback
      const redirectPort = 8080;

      await logger.info('GoogleDrive', 'Iniciando servidor local en puerto $redirectPort');

      // Función para abrir el navegador
      void prompt(String url) async {
        await logger.info('GoogleDrive', 'Abriendo navegador en: $url');
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          await logger.error('GoogleDrive', 'No se pudo abrir el navegador. URL: $url');
        }
      }

      // Obtener cliente autenticado
      await logger.info('GoogleDrive', 'Esperando autorización del usuario...');
      _authClient = await clientViaUserConsent(
        credentials,
        scopes,
        prompt,
      );

      if (_authClient == null) {
        await logger.error('GoogleDrive', 'No se pudo obtener el cliente autenticado');
        return false;
      }

      // Crear API de Drive
      _driveApi = drive.DriveApi(_authClient!);

      // Guardar tokens en la base de datos
      await logger.info('GoogleDrive', 'Guardando tokens en la base de datos...');
      final credentialsData = _authClient!.credentials;

      final db = DatabaseService.instance;
      final configActual = await db.getGoogleDriveConfig();

      final configActualizado = (configActual ?? GoogleDriveConfig()).copyWith(
        clientId: clientId,
        clientSecret: clientSecret,
        accessToken: credentialsData.accessToken.data,
        refreshToken: credentialsData.refreshToken,
        tokenExpiry: credentialsData.accessToken.expiry.millisecondsSinceEpoch,
        habilitado: true,
      );

      await db.updateGoogleDriveConfig(configActualizado);

      await logger.info('GoogleDrive', '========== FLUJO OAUTH2 COMPLETADO EXITOSAMENTE ==========');
      return true;
    } catch (e, stackTrace) {
      await logger.error('GoogleDrive', 'Error en flujo OAuth2: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Inicializa el servicio con las credenciales almacenadas
  Future<bool> inicializar(GoogleDriveConfig config) async {
    try {
      if (!config.estaConfigurada) {
        await logger.warning('GoogleDrive', 'Configuración incompleta');
        return false;
      }

      await logger.info('GoogleDrive', 'Inicializando servicio con tokens guardados...');

      // Crear credenciales desde los tokens guardados
      final credentials = AccessCredentials(
        AccessToken(
          'Bearer',
          config.accessToken!,
          config.tokenExpiry != null
            ? DateTime.fromMillisecondsSinceEpoch(config.tokenExpiry!).toUtc()
            : DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        config.refreshToken,
        scopes,
      );

      final clientId = ClientId(config.clientId!, config.clientSecret!);

      // Crear cliente auto-refrescante
      _authClient = autoRefreshingClient(
        clientId,
        credentials,
        http.Client(),
      );

      // Crear API de Drive
      _driveApi = drive.DriveApi(_authClient!);

      // Actualizar tokens si cambiaron
      _authClient!.credentialUpdates.listen((newCredentials) async {
        await logger.info('GoogleDrive', 'Tokens actualizados automáticamente');
        final db = DatabaseService.instance;
        final configActual = await db.getGoogleDriveConfig();

        if (configActual != null) {
          final configActualizado = configActual.copyWith(
            accessToken: newCredentials.accessToken.data,
            refreshToken: newCredentials.refreshToken,
            tokenExpiry: newCredentials.accessToken.expiry.millisecondsSinceEpoch,
          );
          await db.updateGoogleDriveConfig(configActualizado);
        }
      });

      await logger.info('GoogleDrive', 'Servicio inicializado exitosamente');
      return true;
    } catch (e, stackTrace) {
      await logger.error('GoogleDrive', 'Error al inicializar: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Scopes de Google Drive
  static const scopes = [drive.DriveApi.driveFileScope];

  /// Sube un archivo PDF a Google Drive
  ///
  /// [pdfBytes] - Bytes del PDF
  /// [nombreArchivo] - Nombre del archivo (ej: "Cierre_2024-01-15_S1.pdf")
  /// [carpetaId] - ID de la carpeta raíz donde subir (opcional)
  /// [rutaSubcarpetas] - Ruta de subcarpetas a crear (ej: "Patricio/2026/01_enero")
  ///
  /// Retorna el ID del archivo subido o null si falla
  Future<String?> subirPDF({
    required Uint8List pdfBytes,
    required String nombreArchivo,
    String? carpetaId,
    String? rutaSubcarpetas,
  }) async {
    try {
      if (_driveApi == null) {
        await logger.error('GoogleDrive', 'Servicio no inicializado');
        return null;
      }

      await logger.info('GoogleDrive', 'Subiendo archivo: $nombreArchivo (${pdfBytes.length} bytes)');

      // Si hay subcarpetas, crear la estructura jerárquica
      String? carpetaFinal = carpetaId;

      if (rutaSubcarpetas != null && rutaSubcarpetas.isNotEmpty) {
        await logger.info('GoogleDrive', 'Creando estructura de carpetas: $rutaSubcarpetas');

        // Dividir la ruta en carpetas individuales
        final carpetas = rutaSubcarpetas.split('/').where((c) => c.isNotEmpty).toList();

        // Crear cada carpeta en secuencia
        for (final nombreCarpeta in carpetas) {
          carpetaFinal = await obtenerOCrearCarpeta(
            nombreCarpeta: nombreCarpeta,
            parentId: carpetaFinal,
          );

          if (carpetaFinal == null) {
            await logger.error('GoogleDrive', 'No se pudo crear la carpeta: $nombreCarpeta');
            break;
          }
        }
      }

      // Metadata del archivo
      final driveFile = drive.File()
        ..name = nombreArchivo
        ..mimeType = 'application/pdf';

      // Si hay carpeta final, especificarla como parent
      if (carpetaFinal != null && carpetaFinal.isNotEmpty) {
        await logger.info('GoogleDrive', 'Usando carpeta ID: $carpetaFinal');
        driveFile.parents = [carpetaFinal];
      }

      // Media del archivo
      final media = drive.Media(
        Stream.value(pdfBytes),
        pdfBytes.length,
        contentType: 'application/pdf',
      );

      // Subir archivo
      await logger.info('GoogleDrive', 'Subiendo a Google Drive...');
      final response = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id, name, mimeType, parents, webViewLink',
      );

      await logger.info('GoogleDrive', 'Archivo subido exitosamente. ID: ${response.id}');
      if (response.webViewLink != null) {
        await logger.info('GoogleDrive', 'Link: ${response.webViewLink}');
      }
      return response.id;
    } catch (e, stackTrace) {
      await logger.error('GoogleDrive', 'Error al subir PDF: $e', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Crea una carpeta en Google Drive
  ///
  /// [nombreCarpeta] - Nombre de la carpeta a crear
  /// [parentId] - ID de la carpeta padre (opcional)
  ///
  /// Retorna el ID de la carpeta creada o null si falla
  Future<String?> crearCarpeta({
    required String nombreCarpeta,
    String? parentId,
  }) async {
    try {
      if (_driveApi == null) {
        await logger.error('GoogleDrive', 'Servicio no inicializado');
        return null;
      }

      await logger.info('GoogleDrive', 'Creando carpeta: $nombreCarpeta');

      final driveFolder = drive.File()
        ..name = nombreCarpeta
        ..mimeType = 'application/vnd.google-apps.folder';

      if (parentId != null && parentId.isNotEmpty) {
        driveFolder.parents = [parentId];
      }

      final response = await _driveApi!.files.create(driveFolder);

      await logger.info('GoogleDrive', 'Carpeta creada exitosamente. ID: ${response.id}');
      return response.id;
    } catch (e, stackTrace) {
      await logger.error('GoogleDrive', 'Error al crear carpeta: $e', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Busca una carpeta por nombre
  ///
  /// [nombreCarpeta] - Nombre de la carpeta a buscar
  /// [parentId] - ID de la carpeta padre donde buscar (opcional)
  ///
  /// Retorna el ID de la carpeta encontrada o null si no existe
  Future<String?> buscarCarpeta({
    required String nombreCarpeta,
    String? parentId,
  }) async {
    try {
      if (_driveApi == null) {
        await logger.error('GoogleDrive', 'Servicio no inicializado');
        return null;
      }

      // Construir query
      String query = "mimeType='application/vnd.google-apps.folder' and name='$nombreCarpeta' and trashed=false";

      if (parentId != null && parentId.isNotEmpty) {
        query += " and '$parentId' in parents";
      }

      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first.id;
      }

      return null;
    } catch (e, stackTrace) {
      await logger.error('GoogleDrive', 'Error al buscar carpeta: $e', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Obtiene o crea una carpeta (si no existe, la crea)
  ///
  /// [nombreCarpeta] - Nombre de la carpeta
  /// [parentId] - ID de la carpeta padre (opcional)
  ///
  /// Retorna el ID de la carpeta
  Future<String?> obtenerOCrearCarpeta({
    required String nombreCarpeta,
    String? parentId,
  }) async {
    // Primero intentar buscarla
    final carpetaId = await buscarCarpeta(
      nombreCarpeta: nombreCarpeta,
      parentId: parentId,
    );

    if (carpetaId != null) {
      await logger.debug('GoogleDrive', 'Carpeta "$nombreCarpeta" ya existe: $carpetaId');
      return carpetaId;
    }

    // Si no existe, crearla
    await logger.debug('GoogleDrive', 'Carpeta "$nombreCarpeta" no existe, creando...');
    return await crearCarpeta(
      nombreCarpeta: nombreCarpeta,
      parentId: parentId,
    );
  }

  /// Cierra el cliente de autenticación
  void cerrar() {
    _authClient?.close();
    _driveApi = null;
    _authClient = null;
  }
}
