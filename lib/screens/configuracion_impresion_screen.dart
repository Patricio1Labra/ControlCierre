import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/configuracion_impresion.dart';
import '../services/database_service.dart';
import '../services/logger_service.dart';

class ConfiguracionImpresionScreen extends StatefulWidget {
  const ConfiguracionImpresionScreen({super.key});

  @override
  State<ConfiguracionImpresionScreen> createState() => _ConfiguracionImpresionScreenState();
}

class _ConfiguracionImpresionScreenState extends State<ConfiguracionImpresionScreen> {
  final _db = DatabaseService.instance;

  ConfiguracionImpresion? _configuracion;
  bool _isLoading = true;
  bool _isSaving = false;

  List<Printer> _impresoras = [];
  Printer? _impresoraSeleccionada;

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
    _cargarImpresoras();
  }

  Future<void> _cargarConfiguracion() async {
    try {
      await logger.info('UI', 'Cargando configuración de impresión');
      final config = await _db.getConfiguracionImpresion();

      setState(() {
        _configuracion = config;
        _isLoading = false;
      });

      await logger.debug('UI', 'Configuración cargada: Impresora=${config.impresoraNombre ?? "Sin configurar"}');
    } catch (e, stackTrace) {
      await logger.error('UI', 'Error al cargar configuración de impresión', error: e, stackTrace: stackTrace);
      setState(() => _isLoading = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar configuración: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cargarImpresoras() async {
    try {
      await logger.info('UI', 'Detectando impresoras disponibles');
      final impresoras = await Printing.listPrinters();

      setState(() {
        _impresoras = impresoras;

        // Si hay una impresora configurada, buscarla en la lista
        if (_configuracion?.impresoraNombre != null) {
          try {
            _impresoraSeleccionada = impresoras.firstWhere(
              (p) => p.name == _configuracion!.impresoraNombre,
            );
          } catch (e) {
            // Si no se encuentra la impresora configurada, usar la primera disponible
            _impresoraSeleccionada = impresoras.isNotEmpty ? impresoras.first : null;
          }
        } else if (impresoras.isNotEmpty) {
          _impresoraSeleccionada = impresoras.first;
        }
      });

      await logger.info('UI', '${impresoras.length} impresoras detectadas');
    } catch (e, stackTrace) {
      await logger.error('UI', 'Error al detectar impresoras', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _guardarConfiguracion() async {
    if (_configuracion == null) return;

    setState(() => _isSaving = true);

    try {
      await logger.info('UI', 'Guardando configuración de impresión');

      final configActualizada = _configuracion!.copyWith(
        impresoraNombre: _impresoraSeleccionada?.name,
      );

      await _db.updateConfiguracionImpresion(configActualizada);

      setState(() {
        _configuracion = configActualizada;
        _isSaving = false;
      });

      await logger.info('UI', 'Configuración de impresión guardada exitosamente');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración guardada correctamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e, stackTrace) {
      await logger.error('UI', 'Error al guardar configuración', error: e, stackTrace: stackTrace);
      setState(() => _isSaving = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Impresión'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _guardarConfiguracion,
              tooltip: 'Guardar configuración',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _configuracion == null
              ? const Center(child: Text('Error al cargar configuración'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSeccionImpresora(),
                      const SizedBox(height: 24),
                      _buildSeccionDocumentos(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSeccionImpresora() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.print, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Impresora',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            if (_impresoras.isEmpty)
              const Text(
                'No se detectaron impresoras',
                style: TextStyle(color: Colors.orange),
              )
            else
              DropdownButtonFormField<Printer>(
                initialValue: _impresoraSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Seleccionar impresora',
                  border: OutlineInputBorder(),
                ),
                items: _impresoras.map((impresora) {
                  return DropdownMenuItem<Printer>(
                    value: impresora,
                    child: Text(impresora.name),
                  );
                }).toList(),
                onChanged: (Printer? nuevaImpresora) {
                  setState(() {
                    _impresoraSeleccionada = nuevaImpresora;
                  });
                },
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _cargarImpresoras,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Actualizar lista de impresoras'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionDocumentos() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Documentos a Imprimir',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Selecciona qué documentos deseas imprimir automáticamente al cerrar una sesión:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildDocumentoCheckbox(
              'Facturas de Contado',
              _configuracion!.imprimirFacturasContado,
              (value) {
                setState(() {
                  _configuracion = _configuracion!.copyWith(
                    imprimirFacturasContado: value,
                  );
                });
              },
              Icons.receipt_long,
            ),
            _buildDocumentoCheckbox(
              'Facturas a Crédito',
              _configuracion!.imprimirFacturasCredito,
              (value) {
                setState(() {
                  _configuracion = _configuracion!.copyWith(
                    imprimirFacturasCredito: value,
                  );
                });
              },
              Icons.credit_card,
            ),
            _buildDocumentoCheckbox(
              'Resumen General',
              _configuracion!.imprimirResumen,
              (value) {
                setState(() {
                  _configuracion = _configuracion!.copyWith(
                    imprimirResumen: value,
                  );
                });
              },
              Icons.summarize,
            ),
            _buildDocumentoCheckbox(
              'Ticket de Entrega',
              _configuracion!.imprimirTicketEntrega,
              (value) {
                setState(() {
                  _configuracion = _configuracion!.copyWith(
                    imprimirTicketEntrega: value,
                  );
                });
              },
              Icons.local_shipping,
            ),
            _buildDocumentoCheckbox(
              'Don José',
              _configuracion!.imprimirDonJose,
              (value) {
                setState(() {
                  _configuracion = _configuracion!.copyWith(
                    imprimirDonJose: value,
                  );
                });
              },
              Icons.person,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentoCheckbox(
    String titulo,
    bool valor,
    ValueChanged<bool> onChanged,
    IconData icono,
  ) {
    return CheckboxListTile(
      value: valor,
      onChanged: (newValue) => onChanged(newValue ?? false),
      title: Row(
        children: [
          Icon(icono, size: 20, color: Colors.blue),
          const SizedBox(width: 8),
          Text(titulo),
        ],
      ),
      contentPadding: EdgeInsets.zero,
    );
  }
}
