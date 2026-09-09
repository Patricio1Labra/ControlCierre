import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.blue),
          const SizedBox(width: 8),
          Text('Actualización disponible: ${widget.updateInfo.version}'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una nueva versión disponible.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
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
                    widget.updateInfo.releaseNotes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Más tarde'),
        ),
        TextButton(
          onPressed: _isDownloading ? null : _openReleasesPage,
          child: const Text('Ver en GitHub'),
        ),
        ElevatedButton.icon(
          onPressed: _isDownloading ? null : _downloadAndInstall,
          icon: const Icon(Icons.download),
          label: const Text('Descargar e instalar'),
        ),
      ],
    );
  }

  Future<void> _openReleasesPage() async {
    await UpdateService.openReleasesPage();
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      // Descargar actualización
      final updateFile = await UpdateService.downloadUpdate(
        widget.updateInfo.downloadUrl,
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

      // Instalar actualización
      final success = await UpdateService.installUpdate(updateFile);

      if (!mounted) return;

      if (success) {
        // Cerrar el diálogo - el batch se encargará de cerrar la aplicación automáticamente
        if (!mounted) return;
        Navigator.of(context).pop(true);

        // Mostrar mensaje de que la actualización está en proceso
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Actualizando... La aplicación se cerrará automáticamente'),
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

/// Muestra el diálogo de actualización
Future<bool?> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UpdateDialog(updateInfo: updateInfo),
  );
}
