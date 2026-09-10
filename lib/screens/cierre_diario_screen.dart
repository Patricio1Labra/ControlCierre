import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/gestures.dart';

import 'package:flutter/services.dart';
import '../utils/peso_input_formatter.dart';

import 'package:intl/intl.dart';

import 'package:file_picker/file_picker.dart';

import 'package:printing/printing.dart';

import '../models/cierre_caja.dart';

import '../models/factura.dart';

import '../models/boleta_credito.dart';

import '../models/pago.dart';

import '../models/movimiento_simple.dart';

import '../models/tarjeta.dart';

import '../services/database_service.dart';

import '../services/pdf_service.dart';

import '../services/preferences_service.dart';

import '../services/thermal_print_service.dart';

import '../services/update_service.dart';

import '../services/logger_service.dart';

import '../services/google_drive_service.dart';

import '../widgets/update_dialog.dart';

import 'historial_cierres_screen.dart';

import 'configuracion_google_drive_screen.dart';

class CierreDiarioScreen extends StatefulWidget {
  const CierreDiarioScreen({super.key});

  @override
  State<CierreDiarioScreen> createState() => _CierreDiarioScreenState();
}

class RutInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Eliminar todo excepto números y K

    String text = newValue.text.replaceAll(RegExp(r'[^0-9kK]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Calcular posición del cursor en texto sin formato

    int cursorPos = newValue.selection.baseOffset;

    String textBeforeCursor = newValue.text.substring(0, cursorPos);

    String cleanTextBeforeCursor =
        textBeforeCursor.replaceAll(RegExp(r'[^0-9kK]'), '');

    int cleanCursorPos = cleanTextBeforeCursor.length;

    // Separar dígito verificador

    String dv = '';

    String numbers = text;

    if (text.length > 1) {
      dv = text[text.length - 1].toUpperCase();

      numbers = text.substring(0, text.length - 1);
    }

    // Formatear números con puntos

    String formatted = '';

    int count = 0;

    for (int i = numbers.length - 1; i >= 0; i--) {
      if (count == 3) {
        formatted = '.$formatted';

        count = 0;
      }

      formatted = numbers[i] + formatted;

      count++;
    }

    // Agregar guión y dígito verificador si existe

    if (dv.isNotEmpty) {
      formatted = '$formatted-$dv';
    }

    // Calcular nueva posición del cursor en texto formateado

    int newCursorPos = 0;

    int charCount = 0;

    for (int i = 0; i < formatted.length && charCount < cleanCursorPos; i++) {
      if (formatted[i] != '.' && formatted[i] != '-') {
        charCount++;
      }

      newCursorPos = i + 1;
    }

    // Asegurar que el cursor no quede después del guión

    if (newCursorPos > 0 && newCursorPos < formatted.length) {
      if (formatted[newCursorPos - 1] == '-') {
        newCursorPos--;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
          offset: newCursorPos.clamp(0, formatted.length)),
    );
  }
}

class _HoraInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) return newValue.copyWith(text: '');

    String formatted = text;
    if (text.length > 2) {
      formatted = '${text.substring(0, 2)}:${text.substring(2)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ClockTitle extends StatefulWidget {
  final String nombreCaja;
  const _ClockTitle({required this.nombreCaja});

  @override
  State<_ClockTitle> createState() => _ClockTitleState();
}

class _ClockTitleState extends State<_ClockTitle> {
  Timer? _timer;
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _dateFormat.format(DateTime.now());
    return Text(widget.nombreCaja.isEmpty
        ? 'Control de Cierre - $now'
        : 'Control de Cierre - ${widget.nombreCaja} - $now');
  }
}

class _CierreDiarioScreenState extends State<CierreDiarioScreen> {
  final _db = DatabaseService.instance;

  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  final _numberFormat = NumberFormat('#,##0', 'es_CL');

  String _formatCurrency(double amount) {
    return '\$${_numberFormat.format(amount)}';
  }

  double _monto(String texto) {
    return double.tryParse(
            texto.replaceAll('.', '').replaceAll(',', '').trim()) ??
        0;
  }

  bool _validarRut(String rut) {
    // Eliminar puntos y guión

    String rutLimpio = rut.replaceAll('.', '').replaceAll('-', '');

    if (rutLimpio.length < 2) return false;

    // Separar número y dígito verificador

    String dv = rutLimpio[rutLimpio.length - 1].toUpperCase();

    String numero = rutLimpio.substring(0, rutLimpio.length - 1);

    // Validar que el número sea numérico

    if (int.tryParse(numero) == null) return false;

    // Calcular dígito verificador

    int suma = 0;

    int multiplicador = 2;

    for (int i = numero.length - 1; i >= 0; i--) {
      suma += int.parse(numero[i]) * multiplicador;

      multiplicador = multiplicador == 7 ? 2 : multiplicador + 1;
    }

    int resto = suma % 11;

    String dvCalculado = resto == 0
        ? '0'
        : resto == 1
            ? 'K'
            : (11 - resto).toString();

    return dv == dvCalculado;
  }

  CierreCaja? _cierreActual;

  List<Factura> _facturas = [];

  List<BoletaCredito> _boletasCredito = [];

  List<Pago> _pagos = [];

  List<MovimientoSimple> _transferencias = [];

  List<MovimientoSimple> _cheques = [];

  List<MovimientoSimple> _depositos = [];

  List<MovimientoSimple> _notasCredito = [];

  List<MovimientoSimple> _otrosEntrada = [];

  List<MovimientoSimple> _otrosSalida = [];

  List<MovimientoSimple> _donJose = [];

  List<Tarjeta> _tarjetas = [];

  // Configuraciones

  bool _modoFerreteria = false;

  int _ultimoNumeroFactura = 0;

  String _rutaGuardadoLocal = '';

  String _rutaGuardadoServidor = '';

  String _nombreCaja = '';

  String _printerName = '';

  // Visibilidad de paneles (solo en modo no-ferretería)

  final Map<String, bool> _panelesVisibles = {
    'factura': true,
    'boleta_credito': true,
    'pago': true,
    'transferencia': true,
    'cheque': true,
    'deposito': true,
    'nota_credito': true,
    'otros': true,
    'don_jose': true,
  };

  // Estados de toggles para mantener después de agregar

  bool _donJoseEsBoleta = true;

  bool _otrosEsIngreso = true;

  // Control de expansión de paneles (solo uno abierto a la vez)

  int? _panelExpandido; // null = todos cerrados, 0-8 = panel específico abierto

  void _handlePanelExpansion(int panelIndex, bool isExpanded) {
    setState(() {
      _panelExpandido = isExpanded ? panelIndex : null;
    });
  }

  // Ancho del panel izquierdo en píxeles

  double _leftPanelWidth = 0.3; // 400px por defecto

  @override
  void initState() {
    super.initState();

    _cargarPreferencias();

    _cargarCierreActual();

    _checkForUpdates();
  }

  /// Verifica si hay actualizaciones disponibles

  Future<void> _checkForUpdates() async {
    // Esperar un poco para que la UI se cargue primero

    await Future.delayed(const Duration(seconds: 2));

    final updateInfo = await UpdateService.checkForUpdates();

    if (updateInfo != null && mounted) {
      await showUpdateDialog(context, updateInfo);
    }
  }

  Future<void> _cargarPreferencias() async {
    final modoFerreteria = await PreferencesService.getModoFerreteria();

    final ultimoNumero = await PreferencesService.getUltimoNumeroFactura();

    final rutaLocal = await PreferencesService.getRutaLocal();

    final rutaServidor = await PreferencesService.getRutaServidor();

    final nombreCaja = await PreferencesService.getNombreCaja();

    final printerName = await PreferencesService.getPrinterName();

    final panelesVisibles = await PreferencesService.getPanelesVisibles();

    setState(() {
      _modoFerreteria = modoFerreteria;

      _ultimoNumeroFactura = ultimoNumero;

      _rutaGuardadoLocal = rutaLocal;

      _rutaGuardadoServidor = rutaServidor;

      _nombreCaja = nombreCaja;

      _printerName = printerName;

      // Actualizar visibilidad de paneles

      _panelesVisibles.clear();

      _panelesVisibles.addAll(panelesVisibles);
    });
  }

  Future<void> _cargarCierreActual() async {
    final hoy = DateTime.now();

    var cierre = await _db.getCierreByDate(hoy);

    if (cierre == null) {
      // Crear nuevo cierre para hoy

      final numeroSesion = await _db.getNextSessionNumber(hoy);

      final id = await _db.insertCierre(CierreCaja(
        fecha: hoy,
        aperturaCaja: 0,
        numeroSesion: numeroSesion,
      ));

      cierre = await _db.getCierre(id);
    }

    if (cierre != null) {
      setState(() {
        _cierreActual = cierre;
      });

      await _cargarDatos();
    }
  }

  Future<void> _crearNuevaSesion() async {
    // Mostrar diálogo de confirmación con monto de apertura

    final aperturaCajaController = TextEditingController();

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Sesión'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Desea crear una nueva sesión?'),
            const SizedBox(height: 16),
            TextField(
              controller: aperturaCajaController,
              decoration: const InputDecoration(
                labelText: 'Apertura de caja',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (resultado == true) {
      final apertura = _monto(aperturaCajaController.text);

      final hoy = DateTime.now();

      final numeroSesion = await _db.getNextSessionNumber(hoy);

      final id = await _db.insertCierre(CierreCaja(
        fecha: hoy,
        aperturaCaja: apertura,
        numeroSesion: numeroSesion,
      ));

      final nuevoCierre = await _db.getCierre(id);

      if (nuevoCierre != null) {
        setState(() {
          _cierreActual = nuevoCierre;
        });

        await _cargarDatos();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nueva sesión #$numeroSesion creada')),
        );
      }
    }
  }

  Future<void> _cargarDatos() async {
    if (_cierreActual == null) return;

    final facturas = await _db.getFacturasByCierre(_cierreActual!.id!);

    final boletas = await _db.getBoletasCreditoByCierre(_cierreActual!.id!);

    final pagos = await _db.getPagosByCierre(_cierreActual!.id!);

    final transferencias = await _db.getMovimientosByCierre(_cierreActual!.id!,
        tipo: 'transferencia');

    final cheques =
        await _db.getMovimientosByCierre(_cierreActual!.id!, tipo: 'cheque');

    final depositos =
        await _db.getMovimientosByCierre(_cierreActual!.id!, tipo: 'deposito');

    final notas = await _db.getMovimientosByCierre(_cierreActual!.id!,
        tipo: 'nota_credito');

    final otrosEntrada = await _db.getMovimientosByCierre(_cierreActual!.id!,
        tipo: 'otros_entrada');

    final otrosSalida = await _db.getMovimientosByCierre(_cierreActual!.id!,
        tipo: 'otros_salida');

    final donJose =
        await _db.getMovimientosByCierre(_cierreActual!.id!, tipo: 'don_jose');

    final tarjetas = await _db.getTarjetasByCierre(_cierreActual!.id!);

    setState(() {
      _facturas = facturas;

      _boletasCredito = boletas;

      _pagos = pagos;

      _transferencias = transferencias;

      _cheques = cheques;

      _depositos = depositos;

      _notasCredito = notas;

      _otrosEntrada = otrosEntrada;

      _otrosSalida = otrosSalida;

      _donJose = donJose;

      _tarjetas = tarjetas;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _ClockTitle(nombreCaja: _nombreCaja),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HistorialCierresScreen(),
                ),
              );
            },
            tooltip: 'Ver Historial',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed:
                _cierreActual?.cerrada == true ? null : _crearNuevaSesion,
            tooltip: 'Nueva Sesión',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _mostrarDialogoConfiguracion,
            tooltip: 'Configuración',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _cierreActual?.cerrada == true
                ? null
                : _mostrarDialogoCerrarDia,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: _cierreActual == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    SizedBox(
                      width: constraints.maxWidth * _leftPanelWidth,
                      child: _buildPanelFormularios(),
                    ),
                    GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          final newWidth = _leftPanelWidth +
                              (details.delta.dx / constraints.maxWidth);

                          // Limitar entre 10% y 50%

                          _leftPanelWidth = newWidth.clamp(0.127, 0.5);
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 8,
                              color: Colors.transparent,
                              child: const Center(
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildPanelListas(),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildPanelFormularios() {
    return FocusTraversalGroup(
        child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'AGREGAR DATOS',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_panelesVisibles['factura'] == true) ...[
            _buildFormularioFactura(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['boleta_credito'] == true) ...[
            _buildFormularioBoletaCredito(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['pago'] == true) ...[
            _buildFormularioPago(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['transferencia'] == true) ...[
            _buildFormularioTransferencia(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['cheque'] == true) ...[
            _buildFormularioCheque(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['deposito'] == true) ...[
            _buildFormularioDeposito(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['nota_credito'] == true) ...[
            _buildFormularioNotaCredito(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['otros'] == true) ...[
            _buildFormularioOtros(),
            const Divider(height: 32),
          ],
          if (_panelesVisibles['don_jose'] == true) _buildFormularioDonJose(),
        ],
      ),
    ));
  }

  Widget _buildFormularioFactura() {
    final numeroController = TextEditingController();

    final montoContadoController = TextEditingController();
    final montoCreditoController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setStateLocal) {
        // Si está en modo ferretería, establecer el próximo número automáticamente como sugerencia

        if (_modoFerreteria && numeroController.text.isEmpty) {
          numeroController.text = (_ultimoNumeroFactura + 1).toString();
        }

        return Card(
          child: ExpansionTile(
            key: ValueKey('factura_$_panelExpandido'),
            initiallyExpanded: _panelExpandido == 0,
            onExpansionChanged: (expanded) {
              _handlePanelExpansion(0, expanded);
            },
            leading: const Icon(Icons.receipt, size: 20),
            title: const Text('Factura',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: numeroController,
                      decoration: InputDecoration(
                        labelText: _modoFerreteria
                            ? 'Número (autoincrementa)'
                            : 'Número',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        helperText: _modoFerreteria
                            ? 'Editable para cambios de folio'
                            : null,
                        helperStyle: const TextStyle(fontSize: 10),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: montoContadoController,
                      decoration: const InputDecoration(
                        labelText: 'Monto Contado',
                        isDense: true,
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [PesoInputFormatter()],
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: montoCreditoController,
                      decoration: const InputDecoration(
                        labelText: 'Monto Crédito',
                        isDense: true,
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [PesoInputFormatter()],
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) async {
                        if (numeroController.text.isNotEmpty &&
                            (montoContadoController.text.isNotEmpty ||
                                montoCreditoController.text.isNotEmpty)) {
                          // Verificar si el número ya existe

                          final numeroExiste = _facturas
                              .any((f) => f.numero == numeroController.text);

                          if (numeroExiste) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('El número de factura ya existe'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 2),
                              ),
                            );

                            return;
                          }

                          final montoContado =
                              _monto(montoContadoController.text);
                          final montoCredito =
                              _monto(montoCreditoController.text);

                          final factura = Factura(
                            cierreId: _cierreActual!.id!,
                            numero: numeroController.text,
                            montoContado: montoContado,
                            montoCredito: montoCredito,
                            fecha: DateTime.now(),
                          );

                          await _db.insertFactura(factura);

                          // Actualizar el último número de factura en modo ferretería

                          if (_modoFerreteria) {
                            final numeroFactura =
                                int.tryParse(numeroController.text);

                            if (numeroFactura != null &&
                                numeroFactura > _ultimoNumeroFactura) {
                              setState(() {
                                _ultimoNumeroFactura = numeroFactura;
                              });

                              await PreferencesService.saveUltimoNumeroFactura(
                                  numeroFactura);
                            }
                          }

                          await _cargarDatos();

                          numeroController.clear();
                          montoContadoController.clear();
                          montoCreditoController.clear();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (numeroController.text.isNotEmpty &&
                              (montoContadoController.text.isNotEmpty ||
                                  montoCreditoController.text.isNotEmpty)) {
                            final numeroExiste = _facturas
                                .any((f) => f.numero == numeroController.text);

                            if (numeroExiste) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('El número de factura ya existe'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 2),
                                ),
                              );

                              return;
                            }

                            final montoContado =
                                _monto(montoContadoController.text);
                            final montoCredito =
                                _monto(montoCreditoController.text);
                            final factura = Factura(
                              cierreId: _cierreActual!.id!,
                              numero: numeroController.text,
                              montoContado: montoContado,
                              montoCredito: montoCredito,
                              fecha: DateTime.now(),
                            );

                            await _db.insertFactura(factura);

                            // Actualizar el último número de factura en modo ferretería

                            if (_modoFerreteria) {
                              final numeroFactura =
                                  int.tryParse(numeroController.text);

                              if (numeroFactura != null &&
                                  numeroFactura > _ultimoNumeroFactura) {
                                setState(() {
                                  _ultimoNumeroFactura = numeroFactura;
                                });

                                await PreferencesService
                                    .saveUltimoNumeroFactura(numeroFactura);
                              }
                            }

                            await _cargarDatos();

                            numeroController.clear();
                            montoContadoController.clear();
                            montoCreditoController.clear();
                          }
                        },
                        child: const Text('Agregar',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormularioBoletaCredito() {
    final rutController = TextEditingController();

    final montoController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('boleta_credito_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 1,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(1, expanded);
        },
        leading: const Icon(Icons.description, size: 20),
        title: const Text('Boleta Crédito',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: rutController,
                  decoration: const InputDecoration(
                    labelText: 'RUT Cliente (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [RutInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) async {
                    if (montoController.text.isNotEmpty) {
                      if (rutController.text.isNotEmpty &&
                          !_validarRut(rutController.text)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('RUT inválido'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );

                        return;
                      }

                      final boleta = BoletaCredito(
                        cierreId: _cierreActual!.id!,
                        rut: rutController.text.isEmpty
                            ? 'N/A'
                            : rutController.text,
                        monto: _monto(montoController.text),
                        fecha: DateTime.now(),
                      );

                      await _db.insertBoletaCredito(boleta);

                      await _cargarDatos();

                      rutController.clear();

                      montoController.clear();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (montoController.text.isNotEmpty) {
                        if (rutController.text.isNotEmpty &&
                            !_validarRut(rutController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('RUT inválido'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );

                          return;
                        }

                        final boleta = BoletaCredito(
                          cierreId: _cierreActual!.id!,
                          rut: rutController.text.isEmpty
                              ? 'N/A'
                              : rutController.text,
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                        );

                        await _db.insertBoletaCredito(boleta);

                        await _cargarDatos();

                        rutController.clear();

                        montoController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioPago() {
    final rutController = TextEditingController();

    final montoController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('pago_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 2,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(2, expanded);
        },
        leading: const Icon(Icons.payments, size: 20),
        title: const Text('Pago',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: rutController,
                  decoration: const InputDecoration(
                    labelText: 'RUT Cliente (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [RutInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) async {
                    if (montoController.text.isNotEmpty) {
                      if (rutController.text.isNotEmpty &&
                          !_validarRut(rutController.text)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('RUT inválido'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );

                        return;
                      }

                      final pago = Pago(
                        cierreId: _cierreActual!.id!,
                        rut: rutController.text.isEmpty
                            ? 'N/A'
                            : rutController.text,
                        monto: _monto(montoController.text),
                        fecha: DateTime.now(),
                      );

                      await _db.insertPago(pago);

                      await _cargarDatos();

                      rutController.clear();

                      montoController.clear();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (montoController.text.isNotEmpty) {
                        if (rutController.text.isNotEmpty &&
                            !_validarRut(rutController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('RUT inválido'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );

                          return;
                        }

                        final pago = Pago(
                          cierreId: _cierreActual!.id!,
                          rut: rutController.text.isEmpty
                              ? 'N/A'
                              : rutController.text,
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                        );

                        await _db.insertPago(pago);

                        await _cargarDatos();

                        rutController.clear();

                        montoController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioTransferencia() {
    final montoController = TextEditingController();

    final numeroBoletaFacturaController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('transferencia_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 3,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(3, expanded);
        },
        leading: const Icon(Icons.swap_horiz, size: 20),
        title: const Text('Transferencia',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: numeroBoletaFacturaController,
                  decoration: const InputDecoration(
                    labelText: 'Número de Boleta o Factura (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) async {
                    if (montoController.text.isNotEmpty) {
                      final movimiento = MovimientoSimple(
                        cierreId: _cierreActual!.id!,
                        tipo: 'transferencia',
                        numero: numeroBoletaFacturaController.text.isEmpty
                            ? null
                            : numeroBoletaFacturaController.text,
                        monto: _monto(montoController.text),
                        fecha: DateTime.now(),
                      );

                      await _db.insertMovimiento(movimiento);

                      await _cargarDatos();

                      montoController.clear();

                      numeroBoletaFacturaController.clear();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (montoController.text.isNotEmpty) {
                        final movimiento = MovimientoSimple(
                          cierreId: _cierreActual!.id!,
                          tipo: 'transferencia',
                          rut: numeroBoletaFacturaController.text.isEmpty
                              ? null
                              : numeroBoletaFacturaController.text,
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                        );

                        await _db.insertMovimiento(movimiento);

                        await _cargarDatos();

                        montoController.clear();

                        numeroBoletaFacturaController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioCheque() {
    final numeroController = TextEditingController();

    final rutController = TextEditingController();

    final montoController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('cheque_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 4,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(4, expanded);
        },
        leading: const Icon(Icons.request_quote, size: 20),
        title: const Text('Cheque',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: numeroController,
                  decoration: const InputDecoration(
                    labelText: 'Número (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rutController,
                  decoration: const InputDecoration(
                    labelText: 'RUT (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [RutInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) async {
                    if (montoController.text.isNotEmpty) {
                      if (rutController.text.isNotEmpty &&
                          !_validarRut(rutController.text)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('RUT inválido'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );

                        return;
                      }

                      final movimiento = MovimientoSimple(
                        cierreId: _cierreActual!.id!,
                        tipo: 'cheque',
                        numero: numeroController.text.isEmpty
                            ? null
                            : numeroController.text,
                        rut: rutController.text.isEmpty
                            ? null
                            : rutController.text,
                        monto: _monto(montoController.text),
                        fecha: DateTime.now(),
                      );

                      await _db.insertMovimiento(movimiento);

                      await _cargarDatos();

                      numeroController.clear();

                      rutController.clear();

                      montoController.clear();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (montoController.text.isNotEmpty) {
                        if (rutController.text.isNotEmpty &&
                            !_validarRut(rutController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('RUT inválido'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );

                          return;
                        }

                        final movimiento = MovimientoSimple(
                          cierreId: _cierreActual!.id!,
                          tipo: 'cheque',
                          numero: numeroController.text.isEmpty
                              ? null
                              : numeroController.text,
                          rut: rutController.text.isEmpty
                              ? null
                              : rutController.text,
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                        );

                        await _db.insertMovimiento(movimiento);

                        await _cargarDatos();

                        numeroController.clear();

                        rutController.clear();

                        montoController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioDeposito() {
    final montoController = TextEditingController();
    final horaController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('deposito_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 5,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(5, expanded);
        },
        leading: const Icon(Icons.account_balance, size: 20),
        title: const Text('Depósito',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: horaController,
                  decoration: const InputDecoration(
                    labelText: 'Hora (opcional, HH:mm)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                    _HoraInputFormatter(),
                  ],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (montoController.text.isNotEmpty) {
                        final movimiento = MovimientoSimple(
                          cierreId: _cierreActual!.id!,
                          tipo: 'deposito',
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                          horaDeposito: horaController.text.isEmpty
                              ? null
                              : horaController.text,
                        );

                        await _db.insertMovimiento(movimiento);

                        await _cargarDatos();

                        montoController.clear();
                        horaController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioNotaCredito() {
    final numeroController = TextEditingController();

    final montoController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('nota_credito_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 6,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(6, expanded);
        },
        leading: const Icon(Icons.note, size: 20),
        title: const Text('Nota Crédito',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: numeroController,
                  decoration: const InputDecoration(
                    labelText: 'Número',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) async {
                    if (montoController.text.isNotEmpty) {
                      // Verificar si el número ya existe

                      if (numeroController.text.isNotEmpty) {
                        final numeroExiste = _notasCredito
                            .any((nc) => nc.numero == numeroController.text);

                        if (numeroExiste) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'El número de nota de crédito ya existe'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );

                          return;
                        }
                      }

                      final movimiento = MovimientoSimple(
                        cierreId: _cierreActual!.id!,
                        tipo: 'nota_credito',
                        numero: numeroController.text,
                        monto: _monto(montoController.text),
                        fecha: DateTime.now(),
                      );

                      await _db.insertMovimiento(movimiento);

                      await _cargarDatos();

                      numeroController.clear();

                      montoController.clear();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (montoController.text.isNotEmpty) {
                        // Verificar si el número ya existe

                        if (numeroController.text.isNotEmpty) {
                          final numeroExiste = _notasCredito
                              .any((nc) => nc.numero == numeroController.text);

                          if (numeroExiste) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'El número de nota de crédito ya existe'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 2),
                              ),
                            );

                            return;
                          }
                        }

                        final movimiento = MovimientoSimple(
                          cierreId: _cierreActual!.id!,
                          tipo: 'nota_credito',
                          numero: numeroController.text,
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                        );

                        await _db.insertMovimiento(movimiento);

                        await _cargarDatos();

                        numeroController.clear();

                        montoController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioOtros() {
    final motivoController = TextEditingController();

    final montoController = TextEditingController();

    return Card(
      child: ExpansionTile(
        key: ValueKey('otros_$_panelExpandido'),
        initiallyExpanded: _panelExpandido == 7,
        onExpansionChanged: (expanded) {
          _handlePanelExpansion(7, expanded);
        },
        leading: const Icon(Icons.more_horiz, size: 20),
        title: const Text('Otros',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_otrosEsIngreso ? 'Ingreso' : 'Salida',
                style: const TextStyle(fontSize: 11)),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: _otrosEsIngreso,
                onChanged: (value) {
                  setState(() {
                    _otrosEsIngreso = value;
                  });
                },
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: motivoController,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) async {
                    if (motivoController.text.isNotEmpty &&
                        montoController.text.isNotEmpty) {
                      final tipo =
                          _otrosEsIngreso ? 'otros_entrada' : 'otros_salida';

                      final movimiento = MovimientoSimple(
                        cierreId: _cierreActual!.id!,
                        tipo: tipo,
                        numero: motivoController.text,
                        monto: _monto(montoController.text),
                        fecha: DateTime.now(),
                      );

                      await _db.insertMovimiento(movimiento);

                      await _cargarDatos();

                      motivoController.clear();

                      montoController.clear();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (motivoController.text.isNotEmpty &&
                          montoController.text.isNotEmpty) {
                        final tipo =
                            _otrosEsIngreso ? 'otros_entrada' : 'otros_salida';

                        final movimiento = MovimientoSimple(
                          cierreId: _cierreActual!.id!,
                          tipo: tipo,
                          numero: motivoController.text,
                          monto: _monto(montoController.text),
                          fecha: DateTime.now(),
                        );

                        await _db.insertMovimiento(movimiento);

                        await _cargarDatos();

                        motivoController.clear();

                        montoController.clear();
                      }
                    },
                    child:
                        const Text('Agregar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioDonJose() {
    final numeroController = TextEditingController();

    final montoController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setStateLocal) {
        return Card(
          child: ExpansionTile(
            key: ValueKey('don_jose_$_panelExpandido'),
            initiallyExpanded: _panelExpandido == 8,
            onExpansionChanged: (expanded) {
              _handlePanelExpansion(8, expanded);
            },
            leading: const Icon(Icons.person, size: 20),
            title: const Text('Don José',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_donJoseEsBoleta ? 'Boleta' : 'Factura',
                    style: const TextStyle(fontSize: 11)),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _donJoseEsBoleta,
                    onChanged: (value) {
                      setState(() {
                        _donJoseEsBoleta = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: numeroController,
                      decoration: const InputDecoration(
                        labelText: 'Número (opcional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: montoController,
                      decoration: const InputDecoration(
                        labelText: 'Monto',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [PesoInputFormatter()],
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) async {
                        if (montoController.text.isNotEmpty) {
                          final tipoDoc =
                              _donJoseEsBoleta ? 'Boleta' : 'Factura';

                          final numeroFinal = numeroController.text.isNotEmpty
                              ? '$tipoDoc ${numeroController.text}'
                              : tipoDoc;

                          // Verificar si el número ya existe

                          if (numeroController.text.isNotEmpty) {
                            final numeroExiste =
                                _donJose.any((d) => d.numero == numeroFinal);

                            if (numeroExiste) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'El número de $tipoDoc de Don José ya existe'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 2),
                                ),
                              );

                              return;
                            }
                          }

                          final movimiento = MovimientoSimple(
                            cierreId: _cierreActual!.id!,
                            tipo: 'don_jose',
                            numero: numeroFinal,
                            monto: _monto(montoController.text),
                            fecha: DateTime.now(),
                          );

                          await _db.insertMovimiento(movimiento);

                          await _cargarDatos();

                          numeroController.clear();

                          montoController.clear();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (montoController.text.isNotEmpty) {
                            final tipoDoc =
                                _donJoseEsBoleta ? 'Boleta' : 'Factura';

                            final numeroFinal = numeroController.text.isNotEmpty
                                ? '$tipoDoc ${numeroController.text}'
                                : tipoDoc;

                            // Verificar si el número ya existe

                            if (numeroController.text.isNotEmpty) {
                              final numeroExiste =
                                  _donJose.any((d) => d.numero == numeroFinal);

                              if (numeroExiste) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'El número de $tipoDoc de Don José ya existe'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );

                                return;
                              }
                            }

                            final movimiento = MovimientoSimple(
                              cierreId: _cierreActual!.id!,
                              tipo: 'don_jose',
                              numero: numeroFinal,
                              monto: _monto(montoController.text),
                              fecha: DateTime.now(),
                            );

                            await _db.insertMovimiento(movimiento);

                            await _cargarDatos();

                            numeroController.clear();

                            montoController.clear();
                          }
                        },
                        child: const Text('Agregar',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPanelListas() {
    final scrollController = ScrollController();

    // Construir lista de tarjetas que tienen datos

    final cards = <Widget>[];

    // Facturas con componente contado (incluye mixtas, muestra solo el contado)
    final facturasContado = _facturas.where((f) => f.esContado).toList();

    if (facturasContado.isNotEmpty) {
      cards.add(
          _buildLista('Facturas Contado', facturasContado, esContado: true));
    }

    // Facturas con componente crédito (incluye mixtas, muestra solo el crédito)
    final facturasCredito = _facturas.where((f) => f.esCredito).toList();

    if (facturasCredito.isNotEmpty) {
      cards.add(
          _buildLista('Facturas Crédito', facturasCredito, esContado: false));
    }

    if (_boletasCredito.isNotEmpty) {
      cards.add(_buildListaBoletas('Boletas Crédito', _boletasCredito));
    }

    if (_pagos.isNotEmpty) {
      cards.add(_buildListaPagos('Pagos', _pagos));
    }

    if (_transferencias.isNotEmpty) {
      cards.add(_buildListaMovimientos('Transferencias', _transferencias));
    }

    if (_cheques.isNotEmpty) {
      cards.add(_buildListaMovimientos('Cheques', _cheques));
    }

    if (_depositos.isNotEmpty) {
      cards.add(_buildListaMovimientos('Depósitos', _depositos));
    }

    if (_notasCredito.isNotEmpty) {
      cards.add(_buildListaMovimientos('Notas de Crédito', _notasCredito));
    }

    // Combinar otros entrada y salida en una sola tarjeta

    if (_otrosEntrada.isNotEmpty || _otrosSalida.isNotEmpty) {
      final todosOtros = [..._otrosEntrada, ..._otrosSalida];

      cards.add(_buildListaOtros('Otros', todosOtros));
    }

    // Don José separado por Boleta y Factura

    if (_donJose.isNotEmpty) {
      final donJoseBoletas = _donJose
          .where((d) => d.numero?.startsWith('Boleta') ?? false)
          .toList();

      final donJoseFacturas = _donJose
          .where((d) => d.numero?.startsWith('Factura') ?? false)
          .toList();

      if (donJoseBoletas.isNotEmpty || donJoseFacturas.isNotEmpty) {
        cards.add(
            _buildListaDonJose('Don José', donJoseBoletas, donJoseFacturas));
      }
    }

    // Si no hay datos, mostrar mensaje

    if (cards.isEmpty) {
      return const Center(
        child: Text(
          'No hay datos registrados',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return FocusTraversalGroup(child: LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final offset =
                        scrollController.offset + event.scrollDelta.dy;

                    scrollController.jumpTo(offset.clamp(
                      0.0,
                      scrollController.position.maxScrollExtent,
                    ));
                  }
                },
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    itemCount: cards.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 16),
                    itemBuilder: (context, index) => cards[index],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ));
  }

  Widget _buildLista(String titulo, List<Factura> items,
      {bool esContado = true}) {
    final total = items.fold<double>(
        0,
        (sum, item) =>
            sum + (esContado ? item.montoContado : item.montoCredito));

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Divider(),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No hay registros',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ...items.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('N° ${item.numero}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_dateFormat.format(item.fecha),
                            style: const TextStyle(fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                _formatCurrency(esContado
                                    ? item.montoContado
                                    : item.montoCredito),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarFactura(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarFactura(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                const Divider(),
                Text(
                  'Total: ${_formatCurrency(total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListaBoletas(String titulo, List<BoletaCredito> items) {
    final total = items.fold<double>(0, (sum, item) => sum + item.monto);

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Divider(),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No hay registros',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ...items.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('RUT: ${item.rut}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_dateFormat.format(item.fecha),
                            style: const TextStyle(fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarBoleta(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarBoleta(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                const Divider(),
                Text(
                  'Total: ${_formatCurrency(total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListaPagos(String titulo, List<Pago> items) {
    final total = items.fold<double>(0, (sum, item) => sum + item.monto);

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Divider(),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No hay registros',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ...items.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('RUT: ${item.rut}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_dateFormat.format(item.fecha),
                            style: const TextStyle(fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarPago(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarPago(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                const Divider(),
                Text(
                  'Total: ${_formatCurrency(total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListaMovimientos(String titulo, List<MovimientoSimple> items) {
    final total = items.fold<double>(0, (sum, item) => sum + item.monto);

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Divider(),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No hay registros',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ...items.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.numero ??
                              (item.tipo == 'transferencia'
                                  ? item.rut
                                  : null) ??
                              (item.tipo == 'cheque'
                                  ? (item.rut ?? 'Sin RUT')
                                  : 'Sin info'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_dateFormat.format(item.fecha),
                                style: const TextStyle(fontSize: 11)),
                            if (item.tipo == 'deposito' &&
                                item.horaDeposito != null &&
                                item.horaDeposito!.isNotEmpty)
                              Text('Hora: ${item.horaDeposito}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.teal)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarMovimiento(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarMovimiento(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                const Divider(),
                Text(
                  'Total: ${_formatCurrency(total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListaDonJose(String titulo, List<MovimientoSimple> boletas,
      List<MovimientoSimple> facturas) {
    final totalBoletas =
        boletas.fold<double>(0, (sum, item) => sum + item.monto);

    final totalFacturas =
        facturas.fold<double>(0, (sum, item) => sum + item.monto);

    final totalGeneral = totalBoletas + totalFacturas;

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),

                const Divider(),

                // Boletas

                if (boletas.isNotEmpty) ...[
                  const Text(
                    'Boletas',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.blue),
                  ),
                  ...boletas.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.numero != null && item.numero!.contains(' ')
                              ? item.numero!
                              : _dateFormat.format(item.fecha),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle:
                            item.numero != null && item.numero!.contains(' ')
                                ? Text(_dateFormat.format(item.fecha),
                                    style: const TextStyle(fontSize: 11))
                                : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarMovimiento(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarMovimiento(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                  Text(
                    'Subtotal Boletas: ${_formatCurrency(totalBoletas)}',
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                ],

                // Facturas

                if (facturas.isNotEmpty) ...[
                  const Text(
                    'Facturas',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.green),
                  ),
                  ...facturas.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.numero != null && item.numero!.contains(' ')
                              ? item.numero!
                              : _dateFormat.format(item.fecha),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle:
                            item.numero != null && item.numero!.contains(' ')
                                ? Text(_dateFormat.format(item.fecha),
                                    style: const TextStyle(fontSize: 11))
                                : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarMovimiento(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarMovimiento(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                  Text(
                    'Subtotal Facturas: ${_formatCurrency(totalFacturas)}',
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                ],

                const Divider(),

                Text(
                  'Total: ${_formatCurrency(totalGeneral)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListaOtros(String titulo, List<MovimientoSimple> otros) {
    final otrosEntrada = otros.where((o) => o.tipo == 'otros_entrada').toList();

    final otrosSalida = otros.where((o) => o.tipo == 'otros_salida').toList();

    final totalEntrada =
        otrosEntrada.fold<double>(0, (sum, item) => sum + item.monto);

    final totalSalida =
        otrosSalida.fold<double>(0, (sum, item) => sum + item.monto);

    final totalGeneral = totalEntrada - totalSalida;

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),

                const Divider(),

                // Entradas

                if (otrosEntrada.isNotEmpty) ...[
                  const Text(
                    'Entradas',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.green),
                  ),
                  ...otrosEntrada.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.numero ?? 'Sin motivo',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_dateFormat.format(item.fecha),
                            style: const TextStyle(fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.green)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarMovimiento(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarMovimiento(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                  Text(
                    'Subtotal Entradas: ${_formatCurrency(totalEntrada)}',
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                ],

                // Salidas

                if (otrosSalida.isNotEmpty) ...[
                  const Text(
                    'Salidas',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.red),
                  ),
                  ...otrosSalida.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.numero ?? 'Sin motivo',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_dateFormat.format(item.fecha),
                            style: const TextStyle(fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatCurrency(item.monto),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.red)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _editarMovimiento(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: () => _eliminarMovimiento(item.id!),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      )),
                  Text(
                    'Subtotal Salidas: ${_formatCurrency(totalSalida)}',
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                ],

                const Divider(),

                Text(
                  'Total: ${_formatCurrency(totalGeneral)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editarFactura(Factura factura) async {
    final numeroController = TextEditingController(text: factura.numero);

    final montoContadoController =
        TextEditingController(text: _numberFormat.format(factura.montoContado));
    final montoCreditoController =
        TextEditingController(text: _numberFormat.format(factura.montoCredito));

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Editar Factura'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numeroController,
                  decoration: const InputDecoration(
                    labelText: 'Número',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: montoContadoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto Contado',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [PesoInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: montoCreditoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto Crédito',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [PesoInputFormatter()],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (numeroController.text.isNotEmpty &&
                      (montoContadoController.text.isNotEmpty ||
                          montoCreditoController.text.isNotEmpty)) {
                    // Verificar duplicados solo si cambió el número

                    if (numeroController.text != factura.numero) {
                      final numeroExiste = _facturas.any((f) =>
                          f.numero == numeroController.text &&
                          f.id != factura.id);

                      if (numeroExiste) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('El número de factura ya existe'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );

                        return;
                      }
                    }

                    final montoContado = _monto(montoContadoController.text);
                    final montoCredito = _monto(montoCreditoController.text);

                    final facturaActualizada = Factura(
                      id: factura.id,
                      cierreId: factura.cierreId,
                      numero: numeroController.text,
                      montoContado: montoContado,
                      montoCredito: montoCredito,
                      fecha: factura.fecha,
                    );

                    await _db.updateFactura(facturaActualizada);

                    await _cargarDatos();

                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    montoContadoController.dispose();
    montoCreditoController.dispose();
    numeroController.dispose();
  }

  Future<void> _editarBoleta(BoletaCredito boleta) async {
    final rutController = TextEditingController(text: boleta.rut);

    final montoController =
        TextEditingController(text: _numberFormat.format(boleta.monto));

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Boleta Crédito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rutController,
              decoration: const InputDecoration(
                labelText: 'RUT Cliente',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [RutInputFormatter()],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoController,
              decoration: const InputDecoration(
                labelText: 'Monto',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (rutController.text.isNotEmpty &&
                  montoController.text.isNotEmpty) {
                if (!_validarRut(rutController.text)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('RUT inválido'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );

                  return;
                }

                final boletaActualizada = BoletaCredito(
                  id: boleta.id,
                  cierreId: boleta.cierreId,
                  rut: rutController.text,
                  monto: _monto(montoController.text),
                  fecha: boleta.fecha,
                );

                await _db.updateBoletaCredito(boletaActualizada);

                await _cargarDatos();

                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    rutController.dispose();
  }

  Future<void> _editarPago(Pago pago) async {
    final rutController = TextEditingController(text: pago.rut);

    final montoController =
        TextEditingController(text: _numberFormat.format(pago.monto));

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rutController,
              decoration: const InputDecoration(
                labelText: 'RUT Cliente',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [RutInputFormatter()],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoController,
              decoration: const InputDecoration(
                labelText: 'Monto',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (rutController.text.isNotEmpty &&
                  montoController.text.isNotEmpty) {
                if (!_validarRut(rutController.text)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('RUT inválido'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );

                  return;
                }

                final pagoActualizado = Pago(
                  id: pago.id,
                  cierreId: pago.cierreId,
                  rut: rutController.text,
                  monto: _monto(montoController.text),
                  fecha: pago.fecha,
                );

                await _db.updatePago(pagoActualizado);

                await _cargarDatos();

                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    rutController.dispose();
  }

  Future<void> _editarMovimiento(MovimientoSimple movimiento) async {
    final esTransferencia = movimiento.tipo == 'transferencia';
    final esDonJose = movimiento.tipo == 'don_jose';
    String numeroInicial =
        movimiento.numero ?? (esTransferencia ? movimiento.rut : null) ?? '';
    if (esDonJose && numeroInicial.isNotEmpty) {
      final spaceIndex = numeroInicial.indexOf(' ');
      numeroInicial = spaceIndex != -1
          ? numeroInicial.substring(spaceIndex + 1)
          : numeroInicial;
    }
    final numeroController = TextEditingController(text: numeroInicial);

    final rutController = TextEditingController(text: movimiento.rut ?? '');

    final montoController =
        TextEditingController(text: _numberFormat.format(movimiento.monto));

    final esDeposito = movimiento.tipo == 'deposito';
    final horaController = TextEditingController(
        text: esDeposito ? (movimiento.horaDeposito ?? '') : '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${_getTituloMovimiento(movimiento.tipo)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tieneNumero(movimiento.tipo))
              TextField(
                controller: numeroController,
                decoration: InputDecoration(
                  labelText: movimiento.tipo == 'transferencia'
                      ? 'Número de Boleta o Factura'
                      : (movimiento.tipo == 'don_jose'
                          ? 'Número de Boleta o Factura'
                          : (movimiento.tipo == 'otros_entrada' ||
                                  movimiento.tipo == 'otros_salida'
                              ? 'Motivo'
                              : 'Número')),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: (movimiento.tipo == 'otros_entrada' ||
                        movimiento.tipo == 'otros_salida')
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters: (movimiento.tipo == 'otros_entrada' ||
                        movimiento.tipo == 'otros_salida')
                    ? []
                    : [FilteringTextInputFormatter.digitsOnly],
              ),
            if (_tieneNumero(movimiento.tipo)) const SizedBox(height: 12),
            if (_tieneRut(movimiento.tipo))
              TextField(
                controller: rutController,
                decoration: const InputDecoration(
                  labelText: 'RUT',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [RutInputFormatter()],
              ),
            if (_tieneRut(movimiento.tipo)) const SizedBox(height: 12),
            if (esDeposito)
              TextField(
                controller: horaController,
                decoration: const InputDecoration(
                  labelText: 'Hora (HH:mm)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  _HoraInputFormatter(),
                  LengthLimitingTextInputFormatter(5),
                ],
              ),
            if (esDeposito) const SizedBox(height: 12),
            TextField(
              controller: montoController,
              decoration: const InputDecoration(
                labelText: 'Monto',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (montoController.text.isNotEmpty) {
                if (_tieneRut(movimiento.tipo) &&
                    rutController.text.isNotEmpty &&
                    !_validarRut(rutController.text)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('RUT inválido'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );

                  return;
                }

                // Verificar duplicados de número para nota de crédito

                if (movimiento.tipo == 'nota_credito' &&
                    numeroController.text.isNotEmpty &&
                    numeroController.text != movimiento.numero) {
                  final numeroExiste = _notasCredito.any((nc) =>
                      nc.numero == numeroController.text &&
                      nc.id != movimiento.id);

                  if (numeroExiste) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El número de nota de crédito ya existe'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );

                    return;
                  }
                }

                // Verificar duplicados de número para Don José

                String numeroGuardado = numeroController.text;
                if (esDonJose && numeroGuardado.isNotEmpty) {
                  final tipoDoc =
                      movimiento.numero?.startsWith('Boleta') == true
                          ? 'Boleta'
                          : 'Factura';
                  numeroGuardado = '$tipoDoc $numeroGuardado';
                }

                if (movimiento.tipo == 'don_jose' &&
                    numeroGuardado.isNotEmpty &&
                    numeroGuardado != movimiento.numero) {
                  final numeroExiste = _donJose.any((d) =>
                      d.numero == numeroGuardado && d.id != movimiento.id);

                  if (numeroExiste) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El número de Don José ya existe'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );

                    return;
                  }
                }

                final movimientoActualizado = MovimientoSimple(
                  id: movimiento.id,
                  cierreId: movimiento.cierreId,
                  tipo: movimiento.tipo,
                  numero: _tieneNumero(movimiento.tipo) ? numeroGuardado : null,
                  rut: _tieneRut(movimiento.tipo) ? rutController.text : null,
                  monto: _monto(montoController.text),
                  fecha: movimiento.fecha,
                  horaDeposito: esDeposito
                      ? (horaController.text.isEmpty
                          ? null
                          : horaController.text)
                      : movimiento.horaDeposito,
                );

                await _db.updateMovimiento(movimientoActualizado);

                await _cargarDatos();

                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    rutController.dispose();
    numeroController.dispose();
    if (esDeposito) horaController.dispose();
  }

  String _getTituloMovimiento(String tipo) {
    switch (tipo) {
      case 'transferencia':
        return 'Transferencia';

      case 'cheque':
        return 'Cheque';

      case 'deposito':
        return 'Depósito';

      case 'nota_credito':
        return 'Nota de Crédito';

      case 'don_jose':
        return 'Don José';

      case 'otros_entrada':
        return 'Otros (Ingreso)';

      case 'otros_salida':
        return 'Otros (Salida)';

      default:
        return tipo;
    }
  }

  bool _tieneNumero(String tipo) {
    return tipo == 'cheque' ||
        tipo == 'nota_credito' ||
        tipo == 'transferencia' ||
        tipo == 'otros_entrada' ||
        tipo == 'otros_salida' ||
        tipo == 'don_jose';
  }

  bool _tieneRut(String tipo) {
    return tipo == 'cheque';
  }

  Future<void> _eliminarFactura(int id) async {
    final confirmado =
        await _mostrarDialogoConfirmacion('¿Eliminar esta factura?');

    if (confirmado) {
      await _db.deleteFactura(id);

      await _cargarDatos();
    }
  }

  Future<void> _eliminarBoleta(int id) async {
    final confirmado =
        await _mostrarDialogoConfirmacion('¿Eliminar esta boleta de crédito?');

    if (confirmado) {
      await _db.deleteBoletaCredito(id);

      await _cargarDatos();
    }
  }

  Future<void> _eliminarPago(int id) async {
    final confirmado =
        await _mostrarDialogoConfirmacion('¿Eliminar este pago?');

    if (confirmado) {
      await _db.deletePago(id);

      await _cargarDatos();
    }
  }

  Future<void> _eliminarMovimiento(int id) async {
    final confirmado =
        await _mostrarDialogoConfirmacion('¿Eliminar este registro?');

    if (confirmado) {
      await _db.deleteMovimiento(id);

      await _cargarDatos();
    }
  }

  Future<bool> _mostrarDialogoConfirmacion(String mensaje) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    return resultado ?? false;
  }

  Future<void> _mostrarDialogoConfiguracion() async {
    final nombreCajaController = TextEditingController(text: _nombreCaja);

    // Cargar lista de impresoras disponibles

    List<Printer> printers = [];

    String? selectedPrinter = _printerName.isEmpty ? null : _printerName;

    try {
      printers = await Printing.listPrinters();

      if (printers.isNotEmpty && selectedPrinter == null) {
        selectedPrinter = printers.first.name;
      }
    } catch (e) {
      // Si falla, continuar sin impresoras
    }

    // Cargar configuración de impresión

    var configuracionImpresion = await _db.getConfiguracionImpresion();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Configuración'),
            contentPadding: const EdgeInsets.all(24),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 200, vertical: 24),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. NOMBRE DE LA CAJA

                      const Text('Nombre de la Caja',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),

                      const SizedBox(height: 12),

                      TextField(
                        controller: nombreCajaController,
                        decoration: const InputDecoration(
                          hintText: 'Ej: Caja 1, Caja Principal, etc.',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setStateDialog(() {
                            _nombreCaja = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      const Divider(),

                      // 2. MODO FERRETERÍA

                      SwitchListTile(
                        title: const Text('Modo Ferretería'),
                        subtitle:
                            const Text('Numeración automática de facturas'),
                        value: _modoFerreteria,
                        onChanged: (value) {
                          setStateDialog(() {
                            _modoFerreteria = value;

                            // Si se activa modo ferretería, ocultar Don José y mostrar todos los demás

                            if (value) {
                              _panelesVisibles['factura'] = true;

                              _panelesVisibles['boleta_credito'] = true;

                              _panelesVisibles['pago'] = true;

                              _panelesVisibles['transferencia'] = true;

                              _panelesVisibles['cheque'] = true;

                              _panelesVisibles['deposito'] = true;

                              _panelesVisibles['nota_credito'] = true;

                              _panelesVisibles['otros'] = true;

                              _panelesVisibles['don_jose'] = false;
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),

                      // 3. PANELES VISIBLES (solo si no está en modo ferretería)

                      if (!_modoFerreteria) ...[
                        const Divider(),
                        const Text('Paneles Visibles',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          title: const Text('Factura'),
                          value: _panelesVisibles['factura'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['factura'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Boleta Crédito'),
                          value: _panelesVisibles['boleta_credito'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['boleta_credito'] =
                                  value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Pago'),
                          value: _panelesVisibles['pago'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['pago'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Transferencia'),
                          value: _panelesVisibles['transferencia'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['transferencia'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Cheque'),
                          value: _panelesVisibles['cheque'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['cheque'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Depósito'),
                          value: _panelesVisibles['deposito'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['deposito'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Nota Crédito'),
                          value: _panelesVisibles['nota_credito'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['nota_credito'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Otros'),
                          value: _panelesVisibles['otros'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['otros'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Don José'),
                          value: _panelesVisibles['don_jose'],
                          onChanged: (value) {
                            setStateDialog(() {
                              _panelesVisibles['don_jose'] = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],

                      const Divider(),

                      // 4. CONFIGURACIÓN DE IMPRESIÓN

                      const Text('Configuración de Impresión',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),

                      const SizedBox(height: 12),

                      const Text(
                        'Documentos a imprimir automáticamente al cerrar sesión:',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),

                      const SizedBox(height: 12),

                      CheckboxListTile(
                        value: configuracionImpresion.imprimirFacturasContado,
                        onChanged: (value) {
                          setStateDialog(() {
                            configuracionImpresion =
                                configuracionImpresion.copyWith(
                              imprimirFacturasContado: value ?? true,
                            );
                          });
                        },
                        title: const Row(
                          children: [
                            Icon(Icons.receipt_long,
                                size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Facturas de Contado'),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),

                      CheckboxListTile(
                        value: configuracionImpresion.imprimirFacturasCredito,
                        onChanged: (value) {
                          setStateDialog(() {
                            configuracionImpresion =
                                configuracionImpresion.copyWith(
                              imprimirFacturasCredito: value ?? true,
                            );
                          });
                        },
                        title: const Row(
                          children: [
                            Icon(Icons.credit_card,
                                size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Facturas a Crédito'),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),

                      CheckboxListTile(
                        value: configuracionImpresion.imprimirResumen,
                        onChanged: (value) {
                          setStateDialog(() {
                            configuracionImpresion =
                                configuracionImpresion.copyWith(
                              imprimirResumen: value ?? true,
                            );
                          });
                        },
                        title: const Row(
                          children: [
                            Icon(Icons.summarize, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Resumen General'),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),

                      CheckboxListTile(
                        value: configuracionImpresion.imprimirTicketEntrega,
                        onChanged: (value) {
                          setStateDialog(() {
                            configuracionImpresion =
                                configuracionImpresion.copyWith(
                              imprimirTicketEntrega: value ?? true,
                            );
                          });
                        },
                        title: const Row(
                          children: [
                            Icon(Icons.local_shipping,
                                size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Ticket de Entrega'),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),

                      CheckboxListTile(
                        value: configuracionImpresion.imprimirDonJose,
                        onChanged: (value) {
                          setStateDialog(() {
                            configuracionImpresion =
                                configuracionImpresion.copyWith(
                              imprimirDonJose: value ?? true,
                            );
                          });
                        },
                        title: const Row(
                          children: [
                            Icon(Icons.person, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Don José'),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 12),

                      // Seleccionar impresora

                      if (printers.isNotEmpty) ...[
                        const Text('Impresora',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Printer>(
                          value: printers.any((p) => p.name == selectedPrinter)
                              ? printers
                                  .firstWhere((p) => p.name == selectedPrinter)
                              : null,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Seleccionar impresora',
                          ),
                          items: printers.map((Printer printer) {
                            return DropdownMenuItem<Printer>(
                              value: printer,
                              child: Text(printer.name,
                                  style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (Printer? nuevaImpresora) {
                            setStateDialog(() {
                              selectedPrinter = nuevaImpresora?.name;
                            });
                          },
                        ),
                      ] else ...[
                        const Text('Impresora',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        const Text('No se detectaron impresoras',
                            style: TextStyle(color: Colors.grey)),
                      ],

                      const SizedBox(height: 12),

                      const Divider(),

                      // 5. DIRECTORIOS

                      const Text('Directorios',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),

                      const SizedBox(height: 12),

                      const Text('Guardado Local',
                          style: TextStyle(fontWeight: FontWeight.bold)),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _rutaGuardadoLocal.isEmpty
                                  ? 'No seleccionado'
                                  : _rutaGuardadoLocal,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_open),
                            onPressed: () async {
                              String? selectedDirectory =
                                  await FilePicker.getDirectoryPath();

                              if (selectedDirectory != null) {
                                setStateDialog(() {
                                  _rutaGuardadoLocal = selectedDirectory;
                                });
                              }
                            },
                            tooltip: 'Seleccionar carpeta',
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Dirección guardado servidor

                      const Text('Guardado Servidor',
                          style: TextStyle(fontWeight: FontWeight.bold)),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _rutaGuardadoServidor.isEmpty
                                  ? 'No seleccionado'
                                  : _rutaGuardadoServidor,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_open),
                            onPressed: () async {
                              String? selectedDirectory =
                                  await FilePicker.getDirectoryPath();

                              if (selectedDirectory != null) {
                                setStateDialog(() {
                                  _rutaGuardadoServidor = selectedDirectory;
                                });
                              }
                            },
                            tooltip: 'Seleccionar carpeta',
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Google Drive

                      const Text('Nube',
                          style: TextStyle(fontWeight: FontWeight.bold)),

                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ConfiguracionGoogleDriveScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.cloud),
                        label: const Text('Configurar Google Drive'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 40),
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Divider(),

                      // 6. VERSIÓN DE LA APLICACIÓN

                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Versión de la aplicación',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            'v${UpdateService.currentVersion}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Capturar contexts antes de async

                  final navigator = Navigator.of(context);

                  final messenger = ScaffoldMessenger.of(context);

                  // Guardar preferencias

                  await PreferencesService.saveNombreCaja(
                      nombreCajaController.text);

                  await PreferencesService.saveModoFerreteria(_modoFerreteria);

                  await PreferencesService.saveUltimoNumeroFactura(
                      _ultimoNumeroFactura);

                  await PreferencesService.savePanelesVisibles(
                      _panelesVisibles);

                  await PreferencesService.saveRutaLocal(_rutaGuardadoLocal);

                  await PreferencesService.saveRutaServidor(
                      _rutaGuardadoServidor);

                  await PreferencesService.savePrinterName(
                      selectedPrinter ?? '');

                  // Guardar configuración de impresión

                  await _db
                      .updateConfiguracionImpresion(configuracionImpresion);

                  if (!mounted) return;

                  setState(() {
                    _printerName = selectedPrinter ?? '';
                  });

                  navigator.pop();

                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Configuración guardada'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _mostrarDialogoCerrarDia() async {
    // Cargar el nombre del cajero guardado

    final nombreCajeroGuardado = await PreferencesService.getNombreCajero();

    if (!mounted) return;

    final aperturaCajaController = TextEditingController(text: '150000');

    final tarjetasController = TextEditingController();

    final tarjetaPagoController = TextEditingController();

    final efectivoController = TextEditingController();

    final nombreCajeroController =
        TextEditingController(text: nombreCajeroGuardado);

    String? errorMessage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> validarYProcesar(String accion) async {
            final nombreCajero = nombreCajeroController.text.trim();

            // Validar campos

            if (nombreCajero.isEmpty) {
              setStateDialog(() {
                errorMessage = 'Debe ingresar el nombre del cajero';
              });

              return;
            }

            // Si hay apertura de caja, debe haber efectivo

            if (aperturaCajaController.text.isNotEmpty &&
                efectivoController.text.isEmpty) {
              setStateDialog(() {
                errorMessage =
                    'Si hay apertura de caja, debe ingresar el total de efectivo';
              });

              return;
            }

            // Capturar contextos antes de operaciones async

            final messenger = ScaffoldMessenger.of(context);

            final navigator = Navigator.of(context);

            // Guardar el nombre del cajero para la próxima vez

            await PreferencesService.saveNombreCajero(nombreCajero);

            final apertura = _monto(aperturaCajaController.text);

            final tarjetasPOS = _monto(tarjetasController.text);

            final tarjetaPago = _monto(tarjetaPagoController.text);

            final efectivo = _monto(efectivoController.text);

            if (accion == 'print') {
              // Imprimir con diálogo (layoutPdf)

              try {
                await logger.info(
                    'UI', '========== INICIO IMPRESIÓN CON DIÁLOGO ==========');

                await logger.info('UI',
                    'Sesión: ${_cierreActual!.numeroSesion}, Cajero: $nombreCajero, Caja: $_nombreCaja');

                await logger.info('UI',
                    'Apertura: $apertura, Tarjetas POS: $tarjetasPOS, Tarjetas Pago: $tarjetaPago, Efectivo: $efectivo');

                final cierreConDatos = _cierreActual!.copyWith(
                  nombreCajero: nombreCajero,
                  aperturaCaja: apertura,
                  tarjetas: tarjetasPOS,
                  tarjetasPago: tarjetaPago,
                  efectivo: efectivo,
                );

                // Cargar correcciones si existen

                final correcciones =
                    await _db.getCorreccionesByCierre(_cierreActual!.id!);

                await logger.info(
                    'UI', 'Correcciones cargadas: ${correcciones.length}');

                // Cargar configuración de impresión

                final configuracion = await _db.getConfiguracionImpresion();

                await logger.info('UI', 'Configuración de impresión cargada');

                // Generar todos los documentos usando la función unificada

                await logger.info('UI', 'Generando documentos térmicos...');

                final documentos =
                    await ThermalPrintService.generarTodosLosDocumentos(
                  cierre: cierreConDatos,
                  facturas: _facturas,
                  boletasCredito: _boletasCredito,
                  pagos: _pagos,
                  transferencias: _transferencias,
                  cheques: _cheques,
                  depositos: _depositos,
                  notasCredito: _notasCredito,
                  nombreCaja: _nombreCaja,
                  correcciones: correcciones,
                  tarjetas: _tarjetas,
                  donJose: _donJose,
                  otrosEntrada: _otrosEntrada,
                  otrosSalida: _otrosSalida,
                  mostrarCorrecciones: true,
                  configuracion: configuracion,
                );

                await logger.info('UI',
                    '${documentos.length} documentos generados correctamente');

                // Imprimir cada documento generado

                await logger.info('UI',
                    'Iniciando impresión de ${documentos.length} documentos...');

                for (int i = 0; i < documentos.length; i++) {
                  final doc = documentos[i];

                  String nombreDoc =
                      'Documento_${i + 1}_Sesion${_cierreActual!.numeroSesion}';

                  await logger.info('UI',
                      'Imprimiendo documento ${i + 1}/${documentos.length}: $nombreDoc');

                  try {
                    await Printing.layoutPdf(
                      onLayout: (format) async {
                        await logger.debug('UI',
                            'Formato de página: ${format.width}x${format.height}');

                        final bytes = await doc.save();

                        await logger.info('UI',
                            'Documento $nombreDoc guardado: ${bytes.length} bytes');

                        return bytes;
                      },
                      name: nombreDoc,
                    );

                    await logger.info('UI',
                        'Documento $nombreDoc enviado a impresora exitosamente');
                  } catch (e, stackTrace) {
                    await logger.error(
                        'UI', 'Error al imprimir documento $nombreDoc',
                        error: e, stackTrace: stackTrace);

                    rethrow;
                  }
                }

                await logger.info('UI',
                    '========== IMPRESIÓN COMPLETADA EXITOSAMENTE ==========');

                if (!mounted) return;

                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Documentos enviados a impresora'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e, stackTrace) {
                await logger.error(
                    'UI', '========== ERROR EN IMPRESIÓN ==========',
                    error: e, stackTrace: stackTrace);

                if (!mounted) return;

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error al imprimir: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } else if (accion == 'directprint') {
              // Impresión directa (directPrintPdf) - EXPERIMENTAL

              try {
                await logger.info(
                    'UI', '========== INICIO IMPRESIÓN DIRECTA ==========');

                await logger.info('UI',
                    'Sesión: ${_cierreActual!.numeroSesion}, Cajero: $nombreCajero, Caja: $_nombreCaja');

                await logger.info('UI', 'Impresora guardada: $_printerName');

                final cierreConDatos = _cierreActual!.copyWith(
                  nombreCajero: nombreCajero,
                  aperturaCaja: apertura,
                  tarjetas: tarjetasPOS,
                  tarjetasPago: tarjetaPago,
                  efectivo: efectivo,
                );

                // Cargar correcciones si existen

                final correcciones =
                    await _db.getCorreccionesByCierre(_cierreActual!.id!);

                await logger.info(
                    'UI', 'Correcciones cargadas: ${correcciones.length}');

                // Cargar configuración de impresión
                final configuracion = await _db.getConfiguracionImpresion();

                await logger.info('UI', 'Configuración de impresión cargada');
                await logger.info('UI',
                    'Modo impresora: ${configuracion.usarImpresoraPorDefecto ? "Por defecto" : "Específica: ${configuracion.impresoraNombre ?? "No configurada"}"}');

                // Obtener impresora según configuración
                Printer? impresora;

                try {
                  await logger.info('UI', 'Listando impresoras disponibles...');

                  final impresoras = await Printing.listPrinters();

                  await logger.info(
                      'UI', 'Impresoras encontradas: ${impresoras.length}');

                  for (final p in impresoras) {
                    await logger.debug('UI',
                        '  - ${p.name} (${p.isDefault ? "por defecto" : "no predeterminada"})');
                  }

                  if (impresoras.isEmpty) {
                    await logger.warning(
                        'UI', 'No se encontraron impresoras disponibles');
                  } else {
                    if (configuracion.usarImpresoraPorDefecto) {
                      // Usar impresora por defecto del sistema
                      impresora = impresoras.firstWhere(
                        (p) => p.isDefault,
                        orElse: () => impresoras.first,
                      );
                      await logger.info('UI',
                          'Usando impresora por defecto: ${impresora.name}');
                    } else {
                      // Usar impresora específica configurada
                      final nombreBuscado = configuracion.impresoraNombre;
                      if (nombreBuscado != null && nombreBuscado.isNotEmpty) {
                        try {
                          impresora = impresoras.firstWhere(
                            (p) => p.name == nombreBuscado,
                          );
                          await logger.info('UI',
                              'Impresora específica encontrada: ${impresora.name}');
                        } catch (e) {
                          // Si no se encuentra la impresora configurada, usar la primera disponible
                          impresora = impresoras.first;
                          await logger.warning('UI',
                              'Impresora "$nombreBuscado" no encontrada, usando: ${impresora.name}');
                        }
                      } else {
                        // Si no hay nombre configurado, usar la primera disponible
                        impresora = impresoras.first;
                        await logger.warning('UI',
                            'No hay impresora configurada, usando: ${impresora.name}');
                      }
                    }
                  }
                } catch (e, stackTrace) {
                  await logger.error('UI', 'Error al listar impresoras',
                      error: e, stackTrace: stackTrace);

                  impresora = null;
                }

                // Generar todos los documentos usando la función unificada

                await logger.info('UI', 'Generando documentos térmicos...');

                final documentos =
                    await ThermalPrintService.generarTodosLosDocumentos(
                  cierre: cierreConDatos,
                  facturas: _facturas,
                  boletasCredito: _boletasCredito,
                  pagos: _pagos,
                  transferencias: _transferencias,
                  cheques: _cheques,
                  depositos: _depositos,
                  notasCredito: _notasCredito,
                  nombreCaja: _nombreCaja,
                  correcciones: correcciones,
                  tarjetas: _tarjetas,
                  donJose: _donJose,
                  otrosEntrada: _otrosEntrada,
                  otrosSalida: _otrosSalida,
                  mostrarCorrecciones: true,
                  configuracion: configuracion,
                );

                await logger.info('UI',
                    '${documentos.length} documentos generados correctamente');

                // Imprimir cada documento generado

                if (impresora != null) {
                  await logger.info('UI',
                      'Iniciando impresión directa de ${documentos.length} documentos en ${impresora.name}...');

                  for (int i = 0; i < documentos.length; i++) {
                    final doc = documentos[i];

                    String nombreDoc =
                        'Documento_${i + 1}_Sesion${_cierreActual!.numeroSesion}';

                    await logger.info('UI',
                        'Imprimiendo directamente documento ${i + 1}/${documentos.length}: $nombreDoc');

                    try {
                      await Printing.directPrintPdf(
                        printer: impresora,
                        onLayout: (format) async {
                          await logger.debug('UI',
                              'Formato de página: ${format.width}x${format.height}');

                          final bytes = await doc.save();

                          await logger.info('UI',
                              'Documento $nombreDoc guardado: ${bytes.length} bytes');

                          return bytes;
                        },
                        name: nombreDoc,
                      );

                      await logger.info('UI',
                          'Documento $nombreDoc enviado directamente a ${impresora.name}');
                    } catch (e, stackTrace) {
                      await logger.error('UI',
                          'Error al imprimir directamente documento $nombreDoc',
                          error: e, stackTrace: stackTrace);

                      rethrow;
                    }
                  }

                  await logger.info('UI',
                      '========== IMPRESIÓN DIRECTA COMPLETADA ==========');
                } else {
                  await logger.warning('UI',
                      'No hay impresora disponible para impresión directa');
                }

                if (!mounted) return;

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(impresora != null
                        ? 'Documentos enviados a ${impresora.name}'
                        : 'No hay impresora configurada'),
                    backgroundColor:
                        impresora != null ? Colors.green : Colors.orange,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } catch (e, stackTrace) {
                await logger.error(
                    'UI', '========== ERROR EN IMPRESIÓN DIRECTA ==========',
                    error: e, stackTrace: stackTrace);

                if (!mounted) return;

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error al imprimir directamente: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } else if (accion == 'pdf') {
              // Cerrar sesión y guardar PDF

              final cierreActualizado = _cierreActual!.copyWith(
                nombreCajero: nombreCajero,
                aperturaCaja: apertura,
                tarjetas: tarjetasPOS,
                tarjetasPago: tarjetaPago,
                efectivo: efectivo,
                cerrada: true,
              );

              await _db.updateCierre(cierreActualizado);

              setState(() {
                _cierreActual = cierreActualizado;
              });

              try {
                // Combinar otros entrada y salida en una sola lista

                final otros = [..._otrosEntrada, ..._otrosSalida];

                // Cargar correcciones si existen

                final correcciones =
                    await _db.getCorreccionesByCierre(cierreActualizado.id!);

                final rutasGuardadas = await PdfService.generarYGuardarPdf(
                  cierreActualizado,
                  _facturas,
                  _boletasCredito,
                  _pagos,
                  _transferencias,
                  _cheques,
                  _depositos,
                  _notasCredito,
                  otros,
                  _donJose,
                  _rutaGuardadoLocal,
                  _rutaGuardadoServidor,
                  _nombreCaja,
                  correcciones,
                  _tarjetas,
                );

                if (!mounted) return;

                String mensaje;

                if (rutasGuardadas.isEmpty) {
                  mensaje =
                      'Por favor configure las rutas de guardado en Configuración';
                } else {
                  mensaje =
                      'Sesión cerrada. PDF generado correctamente:\n${rutasGuardadas.join('\n')}';
                }

                // Intentar subir a Google Drive si está configurado

                bool driveSubidaExitosa = false;

                try {
                  final driveConfig = await _db.getGoogleDriveConfig();

                  if (driveConfig != null &&
                      driveConfig.estaConfigurada &&
                      driveConfig.subirAutomaticamente) {
                    await logger.info(
                        'UI', 'Iniciando subida a Google Drive...');

                    final driveService = GoogleDriveService();

                    final inicializado =
                        await driveService.inicializar(driveConfig);

                    if (inicializado && rutasGuardadas.isNotEmpty) {
                      // Leer el primer PDF generado para subirlo

                      final primerPdf = rutasGuardadas.first;

                      final archivo = File(primerPdf);

                      if (await archivo.exists()) {
                        final pdfBytes = await archivo.readAsBytes();

                        final nombreArchivo = archivo.uri.pathSegments.last;

                        // Extraer estructura de carpetas del path local

                        // Ejemplo: C:\...\Patricio\2026\01_enero\archivo.pdf -> Patricio/2026/01_enero

                        String? rutaSubcarpetas;

                        final pathSegments = archivo.uri.pathSegments;

                        if (pathSegments.length >= 4) {
                          // Tomar las últimas 3 carpetas antes del nombre del archivo (cajero/año/mes)

                          final subcarpetas = pathSegments.sublist(
                              pathSegments.length - 4, pathSegments.length - 1);

                          rutaSubcarpetas = subcarpetas.join('/');

                          await logger.info(
                              'UI', 'Estructura de carpetas: $rutaSubcarpetas');
                        }

                        await logger.info('UI',
                            'Subiendo archivo a Google Drive: $nombreArchivo');

                        final archivoId = await driveService.subirPDF(
                          pdfBytes: pdfBytes,
                          nombreArchivo: nombreArchivo,
                          carpetaId: driveConfig.carpetaId,
                          rutaSubcarpetas: rutaSubcarpetas,
                        );

                        if (archivoId != null) {
                          driveSubidaExitosa = true;

                          await logger.info('UI',
                              'Archivo subido exitosamente a Google Drive');

                          mensaje += '\n\nâ PDF subido a Google Drive';
                        } else {
                          await logger.warning('UI',
                              'No se pudo subir el archivo a Google Drive');
                        }
                      }
                    }

                    driveService.cerrar();
                  }
                } catch (e, stackTrace) {
                  await logger.error('UI', 'Error al subir a Google Drive',
                      error: e, stackTrace: stackTrace);

                  // No interrumpir el flujo si falla la subida a Drive
                }

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(mensaje),
                    backgroundColor:
                        rutasGuardadas.isEmpty ? Colors.orange : Colors.green,
                    duration: Duration(seconds: driveSubidaExitosa ? 5 : 4),
                  ),
                );

                // Crear automáticamente una nueva sesión después de cerrar

                await _cargarCierreActual();

                // Cerrar diálogo

                if (mounted) navigator.pop();
              } catch (e) {
                if (!mounted) return;

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Cerrar Sesión')),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Cancelar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: nombreCajeroController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Cajero',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setStateDialog(() => errorMessage = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: aperturaCajaController,
                  decoration: const InputDecoration(
                    labelText: 'Apertura Caja',
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  onChanged: (_) => setStateDialog(() => errorMessage = null),
                ),
                if (_modoFerreteria) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: tarjetasController,
                    decoration: InputDecoration(
                      labelText: _modoFerreteria
                          ? 'Tarjetas Venta'
                          : 'Total Tarjetas Venta',
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [PesoInputFormatter()],
                    onChanged: (_) => setStateDialog(() => errorMessage = null),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: tarjetaPagoController,
                  decoration: const InputDecoration(
                    labelText: 'Tarjetas Pago',
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  onChanged: (_) => setStateDialog(() => errorMessage = null),
                ),
                TextField(
                  controller: efectivoController,
                  decoration: const InputDecoration(
                    labelText: 'Total Efectivo',
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PesoInputFormatter()],
                  onChanged: (_) => setStateDialog(() => errorMessage = null),
                ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.print),
                onPressed: () => validarYProcesar('print'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                label: const Text('Imprimir'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.flash_on),
                onPressed: () => validarYProcesar('directprint'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                label: const Text('Impresión Directa'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: () => validarYProcesar('pdf'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                label: const Text('Guardar y Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
