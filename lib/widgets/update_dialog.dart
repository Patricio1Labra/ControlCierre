import 'package:flutter/material.dart';
import '../services/update_service.dart';

class ManualUpdateDialog extends StatefulWidget {
  const ManualUpdateDialog({super.key});

  @override
  State<ManualUpdateDialog> createState() => _ManualUpdateDialogState();
}

class _ManualUpdateDialogState extends State<ManualUpdateDialog> {
  UpdateCheckState _checkState = UpdateCheckState.checking;
  UpdateInfo? _updateInfo;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = 'Probando conexión...';

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkState = UpdateCheckState.checking;
      _statusMessage = 'Probando conexión...';
    });

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    setState(() {
      _statusMessage = 'Comprobando versión...';
    });

    final updateInfo = await UpdateService.checkForUpdates();

    if (!mounted) return;

    if (updateInfo != null) {
      setState(() {
        _checkState = UpdateCheckState.available;
        _updateInfo = updateInfo;
      });
    } else {
      setState(() {
        _checkState = UpdateCheckState.upToDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _checkState == UpdateCheckState.available
                ? Icons.system_update
                : _checkState == UpdateCheckState.upToDate
                    ? Icons.check_circle
                    : Icons.sync,
            color: _checkState == UpdateCheckState.available
                ? Colors.blue
                : _checkState == UpdateCheckState.upToDate
                    ? Colors.green
                    : Colors.blue,
          ),
          const SizedBox(width: 8),
          Text(
            _checkState == UpdateCheckState.available
                ? 'Actualización disponible'
                : _checkState == UpdateCheckState.upToDate
                    ? 'Versión actual'
                    : 'Verificando actualización...',
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_checkState == UpdateCheckState.checking) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
            if (_checkState == UpdateCheckState.available &&
                _updateInfo != null) ...[
              Text(
                'Versión ${_updateInfo!.version} está disponible.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              if (_updateInfo!.releaseNotes.isNotEmpty) ...[
                Text(
                  'Novedades:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      _updateInfo!.releaseNotes,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 8),
                Text(
                  'Descargando actualización...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (_checkState == UpdateCheckState.upToDate) ...[
              const SizedBox(height: 16),
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'Estás en la última versión',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No hay actualizaciones disponibles.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_checkState == UpdateCheckState.available && !_isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: _openReleasesPage,
            child: const Text('Ver en GitHub'),
          ),
          ElevatedButton.icon(
            onPressed: _downloadAndInstall,
            icon: const Icon(Icons.download),
            label: const Text('Actualizar'),
          ),
        ],
        if (_checkState == UpdateCheckState.upToDate ||
            (_checkState == UpdateCheckState.available && _isDownloading))
          TextButton(
            onPressed:
                _isDownloading ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cerrar'),
          ),
      ],
    );
  }

  Future<void> _openReleasesPage() async {
    await UpdateService.openReleasesPage();
  }

  Future<void> _downloadAndInstall() async {
    if (_updateInfo == null) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final updateFile = await UpdateService.downloadUpdate(
        _updateInfo!.downloadUrl,
        (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        },
      );

      if (updateFile == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al descargar la actualización'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isDownloading = false;
        });
        return;
      }

      final success = await UpdateService.installUpdate(updateFile);

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Actualizando... La aplicación se cerrará automáticamente'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al instalar la actualización'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isDownloading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isDownloading = false;
      });
    }
  }
}

enum UpdateCheckState {
  checking,
  available,
  upToDate,
}

Future<bool?> showManualUpdateDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const ManualUpdateDialog(),
  );
}
