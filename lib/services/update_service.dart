import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:archive/archive.dart';

class UpdateService {
  static const String githubRepo = 'Patricio1Labra/ControlCierre';
  static const String currentVersion = '1.0.7'; // Debe coincidir con pubspec.yaml

  /// Verifica si hay una nueva versión disponible en GitHub
  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['tag_name'] as String;
        final downloadUrl = _findWindowsZipUrl(data['assets'] as List);

        if (downloadUrl != null && _isNewerVersion(latestVersion, currentVersion)) {
          return UpdateInfo(
            version: latestVersion,
            downloadUrl: downloadUrl,
            releaseNotes: data['body'] as String? ?? '',
            publishedAt: DateTime.parse(data['published_at'] as String),
          );
        }
      }
      return null;
    } catch (e) {
      // Silenciosamente retornar null si hay error al verificar actualizaciones
      return null;
    }
  }

  /// Busca el archivo .zip en los assets del release
  static String? _findWindowsZipUrl(List assets) {
    for (var asset in assets) {
      final name = asset['name'] as String;
      if (name.toLowerCase().endsWith('.zip') && name.toLowerCase().contains('windows')) {
        return asset['browser_download_url'] as String;
      }
    }
    return null;
  }

  /// Compara versiones (formato: v1.0.0 o 1.0.0)
  static bool _isNewerVersion(String latest, String current) {
    final latestClean = latest.replaceFirst('v', '');
    final currentClean = current.replaceFirst('v', '');

    final latestParts = latestClean.split('.').map(int.parse).toList();
    final currentParts = currentClean.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// Descarga el archivo ZIP de actualización
  static Future<File?> downloadUpdate(String downloadUrl, Function(double)? onProgress) async {
    try {
      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final zipFile = File('${tempDir.path}/update.zip');
        await zipFile.writeAsBytes(response.bodyBytes);
        return zipFile;
      }
      return null;
    } catch (e) {
      // Silenciosamente retornar null si hay error al descargar
      return null;
    }
  }

  /// Abre el navegador en la página de releases
  static Future<void> openReleasesPage() async {
    final url = Uri.parse('https://github.com/$githubRepo/releases/latest');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Instala la actualización (extrae el ZIP y reemplaza todos los archivos)
  static Future<bool> installUpdate(File zipFile) async {
    try {
      final currentExePath = Platform.resolvedExecutable;
      final currentExeName = currentExePath.split('\\').last;
      final currentDir = File(currentExePath).parent.path;

      // Extraer el ZIP a un directorio temporal
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/update_extract');
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      // Leer y extraer el archivo ZIP
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outputFile = File('${extractDir.path}/$filename');
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(data);
        } else {
          await Directory('${extractDir.path}/$filename').create(recursive: true);
        }
      }

      // Crear un script batch para:
      // 1. Cerrar la app
      // 2. Eliminar archivos viejos (exe, dlls, carpeta data)
      // 3. Copiar nuevos archivos
      // 4. Reiniciar la app
      final batchScript = '''
@echo off
echo Actualizando Control de Cierre...

REM Esperar un momento
timeout /t 1 /nobreak > nul

REM Forzar el cierre de la aplicación
taskkill /F /IM "$currentExeName" 2>nul

REM Esperar a que el proceso termine completamente
timeout /t 2 /nobreak > nul

REM Eliminar archivos viejos
del /f /q "$currentDir\\*.exe" 2>nul
del /f /q "$currentDir\\*.dll" 2>nul
rd /s /q "$currentDir\\data" 2>nul

REM Copiar nuevos archivos desde el directorio extraído
xcopy /E /Y /I "${extractDir.path}\\*" "$currentDir\\"

REM Iniciar la aplicación actualizada
start "" "$currentExePath"

REM Esperar un poco antes de limpiar
timeout /t 2 /nobreak > nul

REM Limpiar archivos temporales
rd /s /q "${extractDir.path}" 2>nul
del /f /q "${zipFile.path}" 2>nul

REM Eliminar este script
del "%~f0"
''';

      final batchFile = File('${tempDir.path}/update.bat');
      await batchFile.writeAsString(batchScript);

      // Ejecutar el script en segundo plano (se encargará de cerrar la app)
      await Process.start(
        'cmd.exe',
        ['/c', batchFile.path],
        mode: ProcessStartMode.detached,
        workingDirectory: currentDir,
      );

      // El batch se encargará de cerrar la aplicación, solo retornamos true
      return true;
    } catch (e) {
      // Silenciosamente retornar false si hay error al instalar
      return false;
    }
  }
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });
}
