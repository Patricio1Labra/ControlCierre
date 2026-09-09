import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  static const int maxLogFileSize = 5 * 1024 * 1024; // 5 MB
  static const int maxLogFiles = 5; // Mantener máximo 5 archivos de log

  File? _currentLogFile;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  final _fileNameFormat = DateFormat('yyyy-MM-dd');

  /// Inicializa el servicio de logging
  Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${directory.path}/logs');

      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      final fileName = 'app_${_fileNameFormat.format(DateTime.now())}.log';
      _currentLogFile = File('${logsDir.path}/$fileName');

      await _rotateLogsIfNeeded();

      await info('Logger', 'Sistema de logging inicializado correctamente');
    } catch (e) {
      // Fallback to console if logger initialization fails
      // ignore: avoid_print
      print('Error al inicializar logger: $e');
    }
  }

  /// Verifica el tamaño del archivo y rota si es necesario
  Future<void> _rotateLogsIfNeeded() async {
    if (_currentLogFile == null) return;

    try {
      if (await _currentLogFile!.exists()) {
        final size = await _currentLogFile!.length();
        if (size > maxLogFileSize) {
          await _rotateLogs();
        }
      }

      await _cleanOldLogs();
    } catch (e) {
      // Fallback to console if rotation fails
      // ignore: avoid_print
      print('Error en rotación de logs: $e');
    }
  }

  /// Rota los archivos de log
  Future<void> _rotateLogs() async {
    if (_currentLogFile == null) return;

    try {
      final directory = _currentLogFile!.parent;
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final rotatedFile = File('${directory.path}/app_$timestamp.log');

      if (await _currentLogFile!.exists()) {
        await _currentLogFile!.copy(rotatedFile.path);
        await _currentLogFile!.writeAsString(''); // Limpiar archivo actual
      }
    } catch (e) {
      // Fallback to console if rotation fails
      // ignore: avoid_print
      print('Error al rotar logs: $e');
    }
  }

  /// Limpia archivos de log antiguos
  Future<void> _cleanOldLogs() async {
    if (_currentLogFile == null) return;

    try {
      final directory = _currentLogFile!.parent;
      final files = await directory.list().toList();

      final logFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      logFiles.sort((a, b) => b.path.compareTo(a.path)); // Ordenar por fecha (más reciente primero)

      if (logFiles.length > maxLogFiles) {
        for (int i = maxLogFiles; i < logFiles.length; i++) {
          await logFiles[i].delete();
        }
      }
    } catch (e) {
      // Fallback to console if cleanup fails
      // ignore: avoid_print
      print('Error al limpiar logs antiguos: $e');
    }
  }

  /// Escribe un mensaje en el log
  Future<void> _writeLog(LogLevel level, String tag, String message, {Object? error, StackTrace? stackTrace}) async {
    final timestamp = _dateFormat.format(DateTime.now());
    final levelStr = level.toString().split('.').last.toUpperCase().padRight(8);
    final tagStr = '[$tag]'.padRight(30);

    final logMessage = StringBuffer('$timestamp $levelStr $tagStr $message');

    if (error != null) {
      logMessage.write('\nError: $error');
    }

    if (stackTrace != null) {
      logMessage.write('\nStackTrace:\n$stackTrace');
    }

    logMessage.write('\n');

    // Escribir en consola para desarrollo
    // ignore: avoid_print
    print(logMessage.toString().trim());

    // Escribir en archivo
    try {
      if (_currentLogFile == null) {
        await initialize();
      }

      if (_currentLogFile != null) {
        await _rotateLogsIfNeeded();
        await _currentLogFile!.writeAsString(
          logMessage.toString(),
          mode: FileMode.append,
        );
      }
    } catch (e) {
      // Fallback to console if file write fails
      // ignore: avoid_print
      print('Error al escribir log: $e');
    }
  }

  // Métodos de logging por nivel
  Future<void> debug(String tag, String message) async {
    await _writeLog(LogLevel.debug, tag, message);
  }

  Future<void> info(String tag, String message) async {
    await _writeLog(LogLevel.info, tag, message);
  }

  Future<void> warning(String tag, String message, {Object? error}) async {
    await _writeLog(LogLevel.warning, tag, message, error: error);
  }

  Future<void> error(String tag, String message, {Object? error, StackTrace? stackTrace}) async {
    await _writeLog(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);
  }

  Future<void> critical(String tag, String message, {Object? error, StackTrace? stackTrace}) async {
    await _writeLog(LogLevel.critical, tag, message, error: error, stackTrace: stackTrace);
  }

  // Métodos de conveniencia para logging de operaciones comunes
  Future<void> logDatabaseOperation(String operation, String table, {Map<String, dynamic>? data}) async {
    final details = data != null ? ' - Data: ${data.toString()}' : '';
    await info('Database', '$operation en tabla "$table"$details');
  }

  Future<void> logDatabaseError(String operation, String table, Object err, StackTrace stackTrace) async {
    await error('Database', 'Error en $operation de tabla "$table"', error: err, stackTrace: stackTrace);
  }

  Future<void> logPrintOperation(String documentType, {String? printerName, int? documentCount}) async {
    final printer = printerName != null ? ' en impresora "$printerName"' : '';
    final count = documentCount != null ? ' ($documentCount documento${documentCount > 1 ? 's' : ''})' : '';
    await info('Printing', 'Imprimiendo $documentType$printer$count');
  }

  Future<void> logPrintError(String documentType, Object err, StackTrace stackTrace) async {
    await error('Printing', 'Error al imprimir $documentType', error: err, stackTrace: stackTrace);
  }

  Future<void> logFileOperation(String operation, String filePath) async {
    await info('FileSystem', '$operation: $filePath');
  }

  Future<void> logFileError(String operation, String filePath, Object err, StackTrace stackTrace) async {
    await error('FileSystem', 'Error en $operation de archivo: $filePath', error: err, stackTrace: stackTrace);
  }

  Future<void> logUserAction(String action, {Map<String, dynamic>? details}) async {
    final detailsStr = details != null ? ' - ${details.toString()}' : '';
    await info('UserAction', '$action$detailsStr');
  }

  Future<void> logSessionEvent(String event, {int? sessionId, String? cajero}) async {
    final session = sessionId != null ? 'Sesión $sessionId' : 'Sesión';
    final user = cajero != null ? ' - Cajero: $cajero' : '';
    await info('Session', '$event - $session$user');
  }

  /// Obtiene la ruta del archivo de log actual
  String? getCurrentLogFilePath() {
    return _currentLogFile?.path;
  }

  /// Obtiene la ruta del directorio de logs
  Future<String?> getLogsDirectoryPath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/logs';
    } catch (e) {
      return null;
    }
  }

  /// Lista todos los archivos de log disponibles
  Future<List<File>> getLogFiles() async {
    try {
      final logsPath = await getLogsDirectoryPath();
      if (logsPath == null) return [];

      final directory = Directory(logsPath);
      if (!await directory.exists()) return [];

      final files = await directory.list().toList();
      final logFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      logFiles.sort((a, b) => b.path.compareTo(a.path)); // Más reciente primero
      return logFiles;
    } catch (e) {
      // Fallback to console if listing fails
      // ignore: avoid_print
      print('Error al listar archivos de log: $e');
      return [];
    }
  }

  /// Lee el contenido de un archivo de log específico
  Future<String?> readLogFile(File logFile) async {
    try {
      if (await logFile.exists()) {
        return await logFile.readAsString();
      }
      return null;
    } catch (e) {
      // Fallback to console if read fails
      // ignore: avoid_print
      print('Error al leer archivo de log: $e');
      return null;
    }
  }

  /// Exporta todos los logs a un archivo único
  Future<File?> exportAllLogs() async {
    try {
      final logFiles = await getLogFiles();
      if (logFiles.isEmpty) return null;

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final exportFile = File('${directory.path}/logs_export_$timestamp.txt');

      final buffer = StringBuffer();
      buffer.writeln('='.padRight(80, '='));
      buffer.writeln('EXPORTACIÓN DE LOGS - ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}');
      buffer.writeln('='.padRight(80, '='));
      buffer.writeln();

      for (final logFile in logFiles) {
        buffer.writeln('\n${'='.padRight(80, '=')}');
        buffer.writeln('ARCHIVO: ${logFile.path.split(Platform.pathSeparator).last}');
        buffer.writeln('='.padRight(80, '='));

        final content = await readLogFile(logFile);
        if (content != null) {
          buffer.writeln(content);
        }
      }

      await exportFile.writeAsString(buffer.toString());
      await info('Logger', 'Logs exportados a: ${exportFile.path}');

      return exportFile;
    } catch (e, stackTrace) {
      await error('Logger', 'Error al exportar logs', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Limpia todos los archivos de log
  Future<void> clearAllLogs() async {
    try {
      await warning('Logger', 'Limpiando todos los archivos de log');

      final logFiles = await getLogFiles();
      for (final file in logFiles) {
        await file.delete();
      }

      // Reinicializar el logger
      await initialize();
      await info('Logger', 'Todos los logs han sido limpiados');
    } catch (e, stackTrace) {
      await error('Logger', 'Error al limpiar logs', error: e, stackTrace: stackTrace);
    }
  }
}

// Instancia global del logger
final logger = LoggerService();
