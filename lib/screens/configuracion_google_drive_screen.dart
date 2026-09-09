import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/google_drive_config.dart';
import '../services/google_drive_service.dart';
import '../services/logger_service.dart';

class ConfiguracionGoogleDriveScreen extends StatefulWidget {
  const ConfiguracionGoogleDriveScreen({super.key});

  @override
  State<ConfiguracionGoogleDriveScreen> createState() => _ConfiguracionGoogleDriveScreenState();
}

class _ConfiguracionGoogleDriveScreenState extends State<ConfiguracionGoogleDriveScreen> {
  final _db = DatabaseService.instance;
  final _driveService = GoogleDriveService();

  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _carpetaIdController = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  bool _autenticando = false;
  bool _probandoSubida = false;
  bool _habilitado = false;
  bool _subirAutomaticamente = true;
  bool _estaAutenticado = false;

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _carpetaIdController.dispose();
    _driveService.cerrar();
    super.dispose();
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final config = await _db.getGoogleDriveConfig();

      if (config != null) {
        setState(() {
          _habilitado = config.habilitado;
          _subirAutomaticamente = config.subirAutomaticamente;
          _estaAutenticado = config.estaAutenticado;
          _clientIdController.clear();
          _clientSecretController.clear();
          _carpetaIdController.text = config.carpetaId ?? '';
        });
      }
    } catch (e) {
      await logger.error('UI', 'Error al cargar configuración', error: e);
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _guardarConfiguracion() async {
    try {
      setState(() => _guardando = true);

      final configActual = await _db.getGoogleDriveConfig();

      String? clientIdFinal;
      String? clientSecretFinal;

      if (_clientIdController.text.isNotEmpty) {
        clientIdFinal = _clientIdController.text.trim();
      } else if (configActual != null) {
        clientIdFinal = configActual.clientId;
      }

      if (_clientSecretController.text.isNotEmpty) {
        clientSecretFinal = _clientSecretController.text.trim();
      } else if (configActual != null) {
        clientSecretFinal = configActual.clientSecret;
      }

      final configNueva = (configActual ?? GoogleDriveConfig()).copyWith(
        habilitado: _habilitado,
        clientId: clientIdFinal,
        clientSecret: clientSecretFinal,
        carpetaId: _carpetaIdController.text.trim().isEmpty ? null : _carpetaIdController.text.trim(),
        subirAutomaticamente: _subirAutomaticamente,
      );

      await _db.updateGoogleDriveConfig(configNueva);

      _clientIdController.clear();
      _clientSecretController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Configuración guardada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      await logger.error('UI', 'Error al guardar', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      setState(() => _guardando = false);
    }
  }

  Future<void> _iniciarSesionGoogle() async {
    try {
      setState(() => _autenticando = true);

      final configActual = await _db.getGoogleDriveConfig();

      String? clientId;
      String? clientSecret;

      if (_clientIdController.text.isNotEmpty) {
        clientId = _clientIdController.text.trim();
        clientSecret = _clientSecretController.text.trim();
      } else if (configActual != null) {
        clientId = configActual.clientId;
        clientSecret = configActual.clientSecret;
      }

      if (clientId == null || clientId.isEmpty || clientSecret == null || clientSecret.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor ingresa Client ID y Client Secret primero'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _autenticando = false);
        return;
      }

      await logger.info('UI', 'Iniciando flujo OAuth2...');

      final exito = await _driveService.iniciarFlujoOAuth(
        clientId: clientId,
        clientSecret: clientSecret,
      );

      setState(() => _autenticando = false);

      if (mounted) {
        if (exito) {
          setState(() => _estaAutenticado = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Autenticación exitosa con Google'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          await _cargarConfiguracion();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✗ Error en la autenticación. Revisa los logs.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      await logger.error('UI', 'Error al autenticar', error: e, stackTrace: stackTrace);
      setState(() => _autenticando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _probarSubida() async {
    try {
      setState(() => _probandoSubida = true);

      await logger.info('GoogleDriveTest', '========== PRUEBA DE SUBIDA OAUTH2 ==========');

      final config = await _db.getGoogleDriveConfig();

      if (config == null || !config.estaConfigurada) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Primero debes autenticarte con Google'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _probandoSubida = false);
        return;
      }

      final pdfPrueba = Uint8List.fromList([
        0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a,
        ...List.filled(100, 0x20),
      ]);

      final driveService = GoogleDriveService();
      final inicializado = await driveService.inicializar(config);

      if (!inicializado) {
        await logger.error('GoogleDriveTest', 'No se pudo inicializar');
        setState(() => _probandoSubida = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✗ Error al inicializar servicio'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Crear estructura de prueba: Test/[Fecha]
      final ahora = DateTime.now();
      final anio = ahora.year.toString();
      final mes = DateFormat('MM_MMMM', 'es_ES').format(ahora);
      final rutaSubcarpetas = 'Test/$anio/$mes';

      await logger.info('GoogleDriveTest', 'Probando estructura: $rutaSubcarpetas');

      final archivoId = await driveService.subirPDF(
        pdfBytes: pdfPrueba,
        nombreArchivo: 'test_oauth2_${DateTime.now().millisecondsSinceEpoch}.pdf',
        carpetaId: config.carpetaId,
        rutaSubcarpetas: rutaSubcarpetas,
      );

      driveService.cerrar();

      setState(() => _probandoSubida = false);

      if (archivoId != null) {
        await logger.info('GoogleDriveTest', '========== PRUEBA EXITOSA ==========');
      } else {
        await logger.error('GoogleDriveTest', 'La subida falló');
      }

      if (mounted) {
        if (archivoId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Archivo subido exitosamente!\nID: $archivoId'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✗ Error al subir. Revisa los logs.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      await logger.error('GoogleDriveTest', 'Error en prueba', error: e, stackTrace: stackTrace);
      setState(() => _probandoSubida = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración Google Drive'),
        actions: [
          if (!_cargando)
            IconButton(
              icon: _guardando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              onPressed: _guardando ? null : _guardarConfiguracion,
              tooltip: 'Guardar configuración',
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'OAuth2 - Inicia sesión con tu cuenta',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Usa OAuth2 para subir PDFs a tu Google Drive personal.',
                            style: TextStyle(fontSize: 13),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '• Inicia sesión con tu cuenta de Google\n'
                            '• Los archivos se guardan en tu Drive\n'
                            '• No necesitas compartir carpetas',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: SwitchListTile(
                      title: const Text('Habilitar Google Drive'),
                      subtitle: const Text('Activar respaldo automático en la nube'),
                      value: _habilitado,
                      onChanged: (value) => setState(() => _habilitado = value),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_estaAutenticado)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '✓ Autenticado con Google Drive',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_estaAutenticado) const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Credenciales OAuth2',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Obtén estas credenciales desde Google Cloud Console',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _clientIdController,
                            decoration: const InputDecoration(
                              labelText: 'Client ID',
                              hintText: 'xxx.apps.googleusercontent.com',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _clientSecretController,
                            decoration: const InputDecoration(
                              labelText: 'Client Secret',
                              hintText: 'GOCSPX-xxx',
                              border: OutlineInputBorder(),
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Por seguridad, las credenciales guardadas no se muestran.',
                            style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _autenticando ? null : _iniciarSesionGoogle,
                      icon: _autenticando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_autenticando ? 'Autenticando...' : 'Iniciar Sesión con Google'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ID de Carpeta (Opcional)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ID de la carpeta donde guardar los PDFs. Déjalo vacío para la raíz.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _carpetaIdController,
                            decoration: const InputDecoration(
                              labelText: 'ID de carpeta',
                              hintText: '1a2B3c4D5e6F7g8H9i0J',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: SwitchListTile(
                      title: const Text('Subida automática'),
                      subtitle: const Text('Subir PDFs automáticamente al cerrar sesión'),
                      value: _subirAutomaticamente,
                      onChanged: _habilitado ? (value) => setState(() => _subirAutomaticamente = value) : null,
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_probandoSubida || !_estaAutenticado) ? null : _probarSubida,
                      icon: _probandoSubida
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(_probandoSubida ? 'Probando...' : 'Probar Subida a Google Drive'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Prueba que la conexión funciona subiendo un archivo de prueba',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  ExpansionTile(
                    title: const Text('¿Cómo obtener las credenciales OAuth2?'),
                    leading: const Icon(Icons.help_outline),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInstruccion('1', 'Ve a console.cloud.google.com'),
                            _buildInstruccion('2', 'Crea un proyecto nuevo'),
                            _buildInstruccion('3', 'Habilita la API de Google Drive'),
                            _buildInstruccion('4', 'Ve a "Credenciales" → "Crear credenciales"'),
                            _buildInstruccion('5', 'Selecciona "ID de cliente de OAuth 2.0"'),
                            _buildInstruccion('6', 'Tipo de aplicación: "Aplicación de escritorio"'),
                            _buildInstruccion('7', 'Copia el Client ID y Client Secret aquí'),
                            _buildInstruccion('8', 'Haz clic en "Iniciar Sesión con Google"'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInstruccion(String numero, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                numero,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
