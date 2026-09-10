import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/cierre_caja.dart';
import '../models/factura.dart';
import '../models/boleta_credito.dart';
import '../models/pago.dart';
import '../models/movimiento_simple.dart';
import '../models/correccion_cierre.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../services/thermal_print_service.dart';
import '../services/preferences_service.dart';
import '../utils/peso_input_formatter.dart';
import 'cierre_diario_screen.dart';

class EditarCierreScreen extends StatefulWidget {
  final CierreCaja cierre;

  const EditarCierreScreen({super.key, required this.cierre});

  @override
  State<EditarCierreScreen> createState() => _EditarCierreScreenState();
}

class _EditarCierreScreenState extends State<EditarCierreScreen> {
  final _db = DatabaseService.instance;
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _numberFormat = NumberFormat('#,##0', 'es_CL');

  // Controllers para montos principales
  late TextEditingController _efectivoController;
  late TextEditingController _tarjetasController;

  // Listas de documentos
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

  // Lista de correcciones a guardar
  final List<CorreccionCierre> _correcciones = [];

  bool _isLoading = true;
  bool _hasChanges = false;

  String _formatCurrency(double amount) {
    return '\$${_numberFormat.format(amount)}';
  }

  @override
  void initState() {
    super.initState();
    _efectivoController = TextEditingController(
      text: _numberFormat.format(widget.cierre.efectivo),
    );
    _tarjetasController = TextEditingController(
      text: _numberFormat.format(widget.cierre.tarjetas),
    );
    _cargarDatos();
  }

  @override
  void dispose() {
    _efectivoController.dispose();
    _tarjetasController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    try {
      final facturas = await _db.getFacturasByCierre(widget.cierre.id!);
      final boletas = await _db.getBoletasCreditoByCierre(widget.cierre.id!);
      final pagos = await _db.getPagosByCierre(widget.cierre.id!);
      final transferencias = await _db.getMovimientosByCierre(widget.cierre.id!,
          tipo: 'transferencia');
      final cheques =
          await _db.getMovimientosByCierre(widget.cierre.id!, tipo: 'cheque');
      final depositos =
          await _db.getMovimientosByCierre(widget.cierre.id!, tipo: 'deposito');
      final notasCredito = await _db.getMovimientosByCierre(widget.cierre.id!,
          tipo: 'nota_credito');
      final otrosEntrada = await _db.getMovimientosByCierre(widget.cierre.id!,
          tipo: 'otros_entrada');
      final otrosSalida = await _db.getMovimientosByCierre(widget.cierre.id!,
          tipo: 'otros_salida');
      final donJose = await _db.getDonJoseByCierre(widget.cierre.id!);

      setState(() {
        _facturas = facturas;
        _boletasCredito = boletas;
        _pagos = pagos;
        _transferencias = transferencias;
        _cheques = cheques;
        _depositos = depositos;
        _notasCredito = notasCredito;
        _otrosEntrada = otrosEntrada;
        _otrosSalida = otrosSalida;
        _donJose = donJose;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  void _registrarCorreccion(String descripcion, String tipoDoc,
      String? numeroDoc, String campo, String? valorAntes, String? valorNuevo) {
    final correccion = CorreccionCierre(
      cierreId: widget.cierre.id!,
      fechaCorreccion: DateTime.now(),
      tipoDocumento: tipoDoc,
      numeroDocumento: numeroDoc,
      campoModificado: campo,
      valorAnterior: valorAntes,
      valorNuevo: valorNuevo,
      descripcion: descripcion,
    );
    _correcciones.add(correccion);
    setState(() => _hasChanges = true);
  }

  // FACTURAS
  Future<void> _editarFactura(Factura factura) async {
    final montoContadoController =
        TextEditingController(text: _numberFormat.format(factura.montoContado));
    final montoCreditoController =
        TextEditingController(text: _numberFormat.format(factura.montoCredito));

    final resultado = await showDialog<Map<String, double>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Factura ${factura.numero}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: montoContadoController,
              decoration: const InputDecoration(
                  labelText: 'Monto Contado', prefixText: '\$'),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoCreditoController,
              decoration: const InputDecoration(
                  labelText: 'Monto Crédito', prefixText: '\$'),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final nc = double.tryParse(montoContadoController.text
                      .replaceAll('.', '')
                      .replaceAll(',', '')) ??
                  0;
              final cr = double.tryParse(montoCreditoController.text
                      .replaceAll('.', '')
                      .replaceAll(',', '')) ??
                  0;
              if (nc + cr > 0) {
                Navigator.pop(context, {'contado': nc, 'credito': cr});
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      final nuevoContado = resultado['contado']!;
      final nuevoCredito = resultado['credito']!;
      if (nuevoContado != factura.montoContado ||
          nuevoCredito != factura.montoCredito) {
        final anterior = _formatCurrency(factura.monto);
        await _db.updateFactura(Factura(
          id: factura.id,
          cierreId: factura.cierreId,
          numero: factura.numero,
          montoContado: nuevoContado,
          montoCredito: nuevoCredito,
          fecha: factura.fecha,
        ));

        final nuevo = _formatCurrency(nuevoContado + nuevoCredito);
        final tipo = (nuevoContado > 0 && nuevoCredito > 0)
            ? 'Factura Contado y Crédito'
            : (nuevoCredito > 0 ? 'Factura Crédito' : 'Factura Contado');
        _registrarCorreccion(
          'Corrección $tipo #${factura.numero}: antes $anterior, ahora $nuevo',
          tipo,
          factura.numero,
          'monto',
          anterior,
          nuevo,
        );
        await _cargarDatos();
      }
    }
  }

  Future<void> _eliminarFactura(Factura factura) async {
    if (await _confirmarEliminacion('factura ${factura.numero}')) {
      await _db.deleteFactura(factura.id!);
      final tipo = factura.esCredito ? 'Factura Crédito' : 'Factura Contado';
      _registrarCorreccion(
        'Eliminada $tipo #${factura.numero} de ${_formatCurrency(factura.monto)}',
        tipo,
        factura.numero,
        'eliminado',
        _formatCurrency(factura.monto),
        null,
      );
      await _cargarDatos();
    }
  }

  // BOLETAS CRÉDITO
  Future<void> _editarBoletaCredito(BoletaCredito boleta) async {
    final montoController =
        TextEditingController(text: _numberFormat.format(boleta.monto));

    final resultado = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Boleta Crédito\nRUT: ${boleta.rut}'),
        content: TextField(
          controller: montoController,
          decoration:
              const InputDecoration(labelText: 'Monto', prefixText: '\$'),
          keyboardType: TextInputType.number,
          inputFormatters: [PesoInputFormatter()],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto =
                  montoController.text.replaceAll('.', '').replaceAll(',', '');
              final nuevoMonto = double.tryParse(texto);
              if (nuevoMonto != null) Navigator.pop(context, nuevoMonto);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (resultado != null && resultado != boleta.monto) {
      await _db.updateBoletaCredito(BoletaCredito(
        id: boleta.id,
        cierreId: boleta.cierreId,
        rut: boleta.rut,
        monto: resultado,
        fecha: boleta.fecha,
      ));

      _registrarCorreccion(
        'Corrección Boleta Crédito RUT ${boleta.rut}: antes ${_formatCurrency(boleta.monto)}, ahora ${_formatCurrency(resultado)}',
        'Boleta Crédito',
        boleta.rut,
        'monto',
        _formatCurrency(boleta.monto),
        _formatCurrency(resultado),
      );
      await _cargarDatos();
    }
  }

  Future<void> _eliminarBoletaCredito(BoletaCredito boleta) async {
    if (await _confirmarEliminacion('boleta crédito RUT ${boleta.rut}')) {
      await _db.deleteBoletaCredito(boleta.id!);
      _registrarCorreccion(
        'Eliminada Boleta Crédito RUT ${boleta.rut} de ${_formatCurrency(boleta.monto)}',
        'Boleta Crédito',
        boleta.rut,
        'eliminado',
        _formatCurrency(boleta.monto),
        null,
      );
      await _cargarDatos();
    }
  }

  // PAGOS
  Future<void> _editarPago(Pago pago) async {
    final montoController =
        TextEditingController(text: _numberFormat.format(pago.monto));

    final resultado = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Pago\nRUT: ${pago.rut}'),
        content: TextField(
          controller: montoController,
          decoration:
              const InputDecoration(labelText: 'Monto', prefixText: '\$'),
          keyboardType: TextInputType.number,
          inputFormatters: [PesoInputFormatter()],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto =
                  montoController.text.replaceAll('.', '').replaceAll(',', '');
              final nuevoMonto = double.tryParse(texto);
              if (nuevoMonto != null) Navigator.pop(context, nuevoMonto);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (resultado != null && resultado != pago.monto) {
      await _db.updatePago(Pago(
        id: pago.id,
        cierreId: pago.cierreId,
        rut: pago.rut,
        monto: resultado,
        fecha: pago.fecha,
      ));

      _registrarCorreccion(
        'Corrección Pago RUT ${pago.rut}: antes ${_formatCurrency(pago.monto)}, ahora ${_formatCurrency(resultado)}',
        'Pago',
        pago.rut,
        'monto',
        _formatCurrency(pago.monto),
        _formatCurrency(resultado),
      );
      await _cargarDatos();
    }
  }

  Future<void> _eliminarPago(Pago pago) async {
    if (await _confirmarEliminacion('pago RUT ${pago.rut}')) {
      await _db.deletePago(pago.id!);
      _registrarCorreccion(
        'Eliminado Pago RUT ${pago.rut} de ${_formatCurrency(pago.monto)}',
        'Pago',
        pago.rut,
        'eliminado',
        _formatCurrency(pago.monto),
        null,
      );
      await _cargarDatos();
    }
  }

  // MOVIMIENTOS SIMPLES (Transferencias, Cheques, Depósitos, Notas Crédito, Otros)
  Future<void> _editarMovimiento(
      MovimientoSimple mov, String tipoNombre) async {
    final montoController =
        TextEditingController(text: _numberFormat.format(mov.monto));
    final esTransferencia = mov.tipo == 'transferencia';
    final esOtros = mov.tipo == 'otros_entrada' || mov.tipo == 'otros_salida';
    final esDonJose = mov.tipo == 'don_jose';
    String numeroInicial =
        mov.numero ?? (esTransferencia ? mov.rut : null) ?? '';
    if (esDonJose && numeroInicial.isNotEmpty) {
      final spaceIndex = numeroInicial.indexOf(' ');
      numeroInicial = spaceIndex != -1
          ? numeroInicial.substring(spaceIndex + 1)
          : numeroInicial;
    }
    final numeroController = TextEditingController(
        text: esTransferencia
            ? (mov.rut ?? '')
            : (esOtros || esDonJose ? numeroInicial : ''));

    final esDeposito = mov.tipo == 'deposito';
    final horaController =
        TextEditingController(text: esDeposito ? (mov.horaDeposito ?? '') : '');

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Editar $tipoNombre${mov.numero != null ? "\n#${mov.numero}" : ""}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (esTransferencia)
              TextField(
                controller: numeroController,
                decoration: const InputDecoration(
                  labelText: 'Número de Boleta o Factura',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            if (esTransferencia) const SizedBox(height: 12),
            if (esDonJose)
              TextField(
                controller: numeroController,
                decoration: const InputDecoration(
                  labelText: 'Número de Boleta o Factura',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            if (esDonJose) const SizedBox(height: 12),
            if (esOtros)
              TextField(
                controller: numeroController,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
              ),
            if (esOtros) const SizedBox(height: 12),
            if (esDeposito)
              TextField(
                controller: horaController,
                decoration: const InputDecoration(
                  labelText: 'Hora (HH:mm)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
              ),
            if (esDeposito) const SizedBox(height: 12),
            TextField(
              controller: montoController,
              decoration:
                  const InputDecoration(labelText: 'Monto', prefixText: '\$'),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto =
                  montoController.text.replaceAll('.', '').replaceAll(',', '');
              final nuevoMonto = double.tryParse(texto);
              if (nuevoMonto != null) {
                String? numeroGuardado = null;
                if (esOtros || esDonJose) {
                  if (numeroController.text.isNotEmpty) {
                    if (esDonJose) {
                      final tipoDoc = mov.numero?.startsWith('Boleta') == true
                          ? 'Boleta'
                          : 'Factura';
                      numeroGuardado = '$tipoDoc ${numeroController.text}';
                    } else {
                      numeroGuardado = numeroController.text;
                    }
                  }
                } else {
                  numeroGuardado = mov.numero;
                }

                Navigator.pop(context, {
                  'monto': nuevoMonto,
                  'rut': esTransferencia
                      ? (numeroController.text.isEmpty
                          ? null
                          : numeroController.text)
                      : mov.rut,
                  'numero': numeroGuardado,
                  'hora': esDeposito ? horaController.text : null,
                });
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      final nuevoMonto = resultado['monto'] as double;
      final nuevoRut = resultado['rut'] as String?;
      final nuevoNumero = resultado['numero'] as String?;
      final nuevaHora = resultado['hora'] as String?;

      if (nuevoMonto != mov.monto ||
          nuevoRut != mov.rut ||
          nuevoNumero != mov.numero ||
          nuevaHora != mov.horaDeposito) {
        await _db.updateMovimiento(MovimientoSimple(
          id: mov.id,
          cierreId: mov.cierreId,
          tipo: mov.tipo,
          numero: nuevoNumero,
          rut: nuevoRut,
          monto: nuevoMonto,
          fecha: mov.fecha,
          horaDeposito: esDeposito ? nuevaHora : mov.horaDeposito,
        ));

        final identificador = mov.numero ?? mov.rut ?? '';
        _registrarCorreccion(
          'Corrección $tipoNombre ${identificador.isNotEmpty ? "$identificador: " : ""}antes ${_formatCurrency(mov.monto)}, ahora ${_formatCurrency(nuevoMonto)}',
          tipoNombre,
          identificador.isNotEmpty ? identificador : null,
          'monto',
          _formatCurrency(mov.monto),
          _formatCurrency(nuevoMonto),
        );
        await _cargarDatos();
      }
    }
    montoController.dispose();
    numeroController.dispose();
    if (esDeposito) horaController.dispose();
  }

  Future<void> _eliminarMovimiento(
      MovimientoSimple mov, String tipoNombre) async {
    final identificador = mov.numero ?? mov.rut ?? '';
    if (await _confirmarEliminacion(
        '$tipoNombre ${identificador.isNotEmpty ? identificador : ""}')) {
      await _db.deleteMovimiento(mov.id!);
      _registrarCorreccion(
        'Eliminado $tipoNombre ${identificador.isNotEmpty ? "$identificador " : ""}de ${_formatCurrency(mov.monto)}',
        tipoNombre,
        identificador.isNotEmpty ? identificador : null,
        'eliminado',
        _formatCurrency(mov.monto),
        null,
      );
      await _cargarDatos();
    }
  }

  Future<bool> _confirmarEliminacion(String item) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Eliminar $item?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    return confirmado == true;
  }

  // MÉTODOS PARA AGREGAR NUEVOS DOCUMENTOS
  Future<void> _agregarFactura() async {
    final numeroController = TextEditingController();
    final montoContadoController = TextEditingController();
    final montoCreditoController = TextEditingController();

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Agregar Factura'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numeroController,
                decoration:
                    const InputDecoration(labelText: 'Número de Factura'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: montoContadoController,
                decoration: const InputDecoration(
                    labelText: 'Monto Contado', prefixText: '\$'),
                keyboardType: TextInputType.number,
                inputFormatters: [PesoInputFormatter()],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: montoCreditoController,
                decoration: const InputDecoration(
                    labelText: 'Monto Crédito', prefixText: '\$'),
                keyboardType: TextInputType.number,
                inputFormatters: [PesoInputFormatter()],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                final numero = numeroController.text;
                final nc = double.tryParse(montoContadoController.text
                        .replaceAll('.', '')
                        .replaceAll(',', '')) ??
                    0;
                final cr = double.tryParse(montoCreditoController.text
                        .replaceAll('.', '')
                        .replaceAll(',', '')) ??
                    0;
                if (numero.isNotEmpty && (nc + cr) > 0) {
                  Navigator.pop(context, {
                    'numero': numero,
                    'montoContado': nc,
                    'montoCredito': cr,
                  });
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );

    if (resultado != null) {
      final nc = resultado['montoContado'] as double;
      final cr = resultado['montoCredito'] as double;
      final total = nc + cr;
      final nuevaFactura = Factura(
        cierreId: widget.cierre.id!,
        numero: resultado['numero'] as String,
        montoContado: nc,
        montoCredito: cr,
        fecha: DateTime.now(),
      );
      await _db.insertFactura(nuevaFactura);

      final tipo = nc > 0 && cr > 0
          ? 'Factura Contado y Crédito'
          : (cr > 0 ? 'Factura Crédito' : 'Factura Contado');
      _registrarCorreccion(
        'Agregada $tipo #${resultado['numero']} de ${_formatCurrency(total)}',
        tipo,
        resultado['numero'] as String,
        'agregado',
        null,
        _formatCurrency(total),
      );
      await _cargarDatos();
    }
  }

  Future<void> _agregarBoletaCredito() async {
    final rutController = TextEditingController();
    final montoController = TextEditingController();

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Boleta Crédito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rutController,
              decoration: const InputDecoration(labelText: 'RUT'),
              inputFormatters: [RutInputFormatter()],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: montoController,
              decoration:
                  const InputDecoration(labelText: 'Monto', prefixText: '\$'),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final rut = rutController.text;
              final texto =
                  montoController.text.replaceAll('.', '').replaceAll(',', '');
              final monto = double.tryParse(texto);
              if (rut.isNotEmpty && monto != null) {
                Navigator.pop(context, {'rut': rut, 'monto': monto});
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      final nuevaBoleta = BoletaCredito(
        cierreId: widget.cierre.id!,
        rut: resultado['rut'],
        monto: resultado['monto'],
        fecha: DateTime.now(),
      );
      await _db.insertBoletaCredito(nuevaBoleta);

      _registrarCorreccion(
        'Agregada Boleta Crédito RUT ${resultado['rut']} de ${_formatCurrency(resultado['monto'])}',
        'Boleta Crédito',
        resultado['rut'],
        'agregado',
        null,
        _formatCurrency(resultado['monto']),
      );
      await _cargarDatos();
    }
  }

  Future<void> _agregarPago() async {
    final rutController = TextEditingController();
    final montoController = TextEditingController();

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rutController,
              decoration: const InputDecoration(labelText: 'RUT'),
              inputFormatters: [RutInputFormatter()],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: montoController,
              decoration:
                  const InputDecoration(labelText: 'Monto', prefixText: '\$'),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final rut = rutController.text;
              final texto =
                  montoController.text.replaceAll('.', '').replaceAll(',', '');
              final monto = double.tryParse(texto);
              if (rut.isNotEmpty && monto != null) {
                Navigator.pop(context, {'rut': rut, 'monto': monto});
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      final nuevoPago = Pago(
        cierreId: widget.cierre.id!,
        rut: resultado['rut'],
        monto: resultado['monto'],
        fecha: DateTime.now(),
      );
      await _db.insertPago(nuevoPago);

      _registrarCorreccion(
        'Agregado Pago RUT ${resultado['rut']} de ${_formatCurrency(resultado['monto'])}',
        'Pago',
        resultado['rut'],
        'agregado',
        null,
        _formatCurrency(resultado['monto']),
      );
      await _cargarDatos();
    }
  }

  Future<void> _agregarMovimiento(String tipo, String tipoNombre) async {
    final montoController = TextEditingController();
    final numeroController = TextEditingController();
    final rutController = TextEditingController();

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Agregar $tipoNombre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tipo == 'cheque' || tipo == 'nota_credito')
              TextField(
                controller: numeroController,
                decoration: InputDecoration(
                    labelText: tipo == 'cheque'
                        ? 'Número de Cheque (opcional)'
                        : 'Número de Nota (opcional)'),
                keyboardType: TextInputType.number,
              ),
            if (tipo == 'cheque') ...[
              const SizedBox(height: 16),
              TextField(
                controller: rutController,
                decoration: const InputDecoration(labelText: 'RUT (opcional)'),
                inputFormatters: [RutInputFormatter()],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: montoController,
              decoration:
                  const InputDecoration(labelText: 'Monto', prefixText: '\$'),
              keyboardType: TextInputType.number,
              inputFormatters: [PesoInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto =
                  montoController.text.replaceAll('.', '').replaceAll(',', '');
              final monto = double.tryParse(texto);
              if (monto != null) {
                Navigator.pop(context, {
                  'monto': monto,
                  'numero': numeroController.text,
                  'rut': rutController.text,
                });
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      final nuevoMovimiento = MovimientoSimple(
        cierreId: widget.cierre.id!,
        tipo: tipo,
        monto: resultado['monto'],
        numero: resultado['numero'].isNotEmpty ? resultado['numero'] : null,
        rut: resultado['rut'].isNotEmpty ? resultado['rut'] : null,
        fecha: DateTime.now(),
      );
      await _db.insertMovimiento(nuevoMovimiento);

      final identificador =
          resultado['numero'].isNotEmpty ? resultado['numero'] : '';
      _registrarCorreccion(
        'Agregado $tipoNombre ${identificador.isNotEmpty ? "#$identificador " : ""}de ${_formatCurrency(resultado['monto'])}',
        tipoNombre,
        identificador.isNotEmpty ? identificador : null,
        'agregado',
        null,
        _formatCurrency(resultado['monto']),
      );
      await _cargarDatos();
    }
  }

  Future<void> _guardarCambios() async {
    try {
      final textoEfectivo =
          _efectivoController.text.replaceAll('.', '').replaceAll(',', '');
      final nuevoEfectivo =
          double.tryParse(textoEfectivo) ?? widget.cierre.efectivo;

      final textoTarjetas =
          _tarjetasController.text.replaceAll('.', '').replaceAll(',', '');
      final nuevoTarjetas =
          double.tryParse(textoTarjetas) ?? widget.cierre.tarjetas;

      if (nuevoEfectivo != widget.cierre.efectivo) {
        _registrarCorreccion(
          'Corrección Efectivo: antes ${_formatCurrency(widget.cierre.efectivo)}, ahora ${_formatCurrency(nuevoEfectivo)}',
          'Efectivo',
          null,
          'monto',
          _formatCurrency(widget.cierre.efectivo),
          _formatCurrency(nuevoEfectivo),
        );
      }

      if (nuevoTarjetas != widget.cierre.tarjetas) {
        _registrarCorreccion(
          'Corrección Tarjetas: antes ${_formatCurrency(widget.cierre.tarjetas)}, ahora ${_formatCurrency(nuevoTarjetas)}',
          'Tarjetas',
          null,
          'monto',
          _formatCurrency(widget.cierre.tarjetas),
          _formatCurrency(nuevoTarjetas),
        );
      }

      final cierreActualizado = widget.cierre
          .copyWith(efectivo: nuevoEfectivo, tarjetas: nuevoTarjetas);
      await _db.updateCierre(cierreActualizado);

      for (final correccion in _correcciones) {
        await _db.insertCorreccion(correccion);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados exitosamente')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar cambios: $e')),
        );
      }
    }
  }

  Future<void> _imprimirDialogo() async {
    try {
      // Cargar preferencias
      final rutaLocal = await PreferencesService.getRutaLocal();
      final rutaServidor = await PreferencesService.getRutaServidor();
      final nombreCaja = await PreferencesService.getNombreCaja();

      // Cargar correcciones y tarjetas
      final correcciones = await _db.getCorreccionesByCierre(widget.cierre.id!);
      final tarjetas = await _db.getTarjetasByCierre(widget.cierre.id!);

      // Combinar otros entrada y salida
      final otros = [..._otrosEntrada, ..._otrosSalida];

      // Generar PDF
      final rutasGuardadas = await PdfService.generarYGuardarPdf(
        widget.cierre,
        _facturas,
        _boletasCredito,
        _pagos,
        _transferencias,
        _cheques,
        _depositos,
        _notasCredito,
        otros,
        [],
        rutaLocal,
        rutaServidor,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      // Generar todos los documentos usando la función unificada
      // SIN mostrar correcciones (igual que la impresión original del cierre)
      final documentos = await ThermalPrintService.generarTodosLosDocumentos(
        cierre: widget.cierre,
        facturas: _facturas,
        boletasCredito: _boletasCredito,
        pagos: _pagos,
        transferencias: _transferencias,
        cheques: _cheques,
        depositos: _depositos,
        notasCredito: _notasCredito,
        nombreCaja: nombreCaja,
        correcciones: correcciones,
        tarjetas: tarjetas,
        donJose: _donJose,
        mostrarCorrecciones: false, // No mostrar correcciones en reimpresión
      );

      // Imprimir cada documento generado
      for (int i = 0; i < documentos.length; i++) {
        final doc = documentos[i];
        String nombreDoc =
            'Cierre_Sesion${widget.cierre.numeroSesion}_Doc${i + 1}';

        await Printing.layoutPdf(
          onLayout: (format) async => doc.save(),
          name: nombreDoc,
        );
      }

      if (!mounted) return;

      String mensaje;
      if (rutasGuardadas.isEmpty) {
        mensaje =
            'Impreso correctamente.\nConfigure las rutas de guardado en Configuración para guardar automáticamente.';
      } else {
        mensaje =
            'Impreso y guardado correctamente:\n${rutasGuardadas.join('\n')}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al imprimir: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _imprimirDirecto() async {
    try {
      // Cargar preferencias
      final rutaLocal = await PreferencesService.getRutaLocal();
      final rutaServidor = await PreferencesService.getRutaServidor();
      final nombreCaja = await PreferencesService.getNombreCaja();

      // Cargar correcciones y tarjetas
      final correcciones = await _db.getCorreccionesByCierre(widget.cierre.id!);
      final tarjetas = await _db.getTarjetasByCierre(widget.cierre.id!);

      // Combinar otros entrada y salida
      final otros = [..._otrosEntrada, ..._otrosSalida];

      // Guardar PDF
      await PdfService.generarYGuardarPdf(
        widget.cierre,
        _facturas,
        _boletasCredito,
        _pagos,
        _transferencias,
        _cheques,
        _depositos,
        _notasCredito,
        otros,
        [],
        rutaLocal,
        rutaServidor,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      // Cargar configuración de impresión
      final configuracion = await _db.getConfiguracionImpresion();

      // Obtener impresora según configuración
      Printer? impresora;
      try {
        final impresoras = await Printing.listPrinters();
        if (impresoras.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se encontraron impresoras disponibles'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        if (configuracion.usarImpresoraPorDefecto) {
          // Usar impresora por defecto del sistema
          impresora = impresoras.firstWhere(
            (p) => p.isDefault,
            orElse: () => impresoras.first,
          );
        } else {
          // Usar impresora específica configurada
          final nombreBuscado = configuracion.impresoraNombre;
          if (nombreBuscado != null && nombreBuscado.isNotEmpty) {
            try {
              impresora = impresoras.firstWhere(
                (p) => p.name == nombreBuscado,
              );
            } catch (e) {
              // Si no se encuentra la impresora configurada, usar la primera disponible
              impresora = impresoras.first;
            }
          } else {
            // Si no hay nombre configurado, usar la primera disponible
            impresora = impresoras.first;
          }
        }
      } catch (e) {
        impresora = null;
      }

      // Generar todos los documentos usando la función unificada
      // SIN mostrar correcciones (igual que la impresión original del cierre)
      final documentos = await ThermalPrintService.generarTodosLosDocumentos(
        cierre: widget.cierre,
        facturas: _facturas,
        boletasCredito: _boletasCredito,
        pagos: _pagos,
        transferencias: _transferencias,
        cheques: _cheques,
        depositos: _depositos,
        notasCredito: _notasCredito,
        nombreCaja: nombreCaja,
        correcciones: correcciones,
        tarjetas: tarjetas,
        donJose: _donJose,
        mostrarCorrecciones: false, // No mostrar correcciones en reimpresión
      );

      if (impresora != null) {
        // Imprimir cada documento generado
        for (int i = 0; i < documentos.length; i++) {
          final doc = documentos[i];
          String nombreDoc =
              'Cierre_Sesion${widget.cierre.numeroSesion}_Doc${i + 1}';

          await Printing.directPrintPdf(
            printer: impresora,
            onLayout: (format) async => doc.save(),
            name: nombreDoc,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impreso en ${impresora.name} y PDF guardado'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontró impresora configurada'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al imprimir: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _guardarPDF() async {
    try {
      // Cargar preferencias
      final rutaLocal = await PreferencesService.getRutaLocal();
      final rutaServidor = await PreferencesService.getRutaServidor();
      final nombreCaja = await PreferencesService.getNombreCaja();

      if (rutaLocal.isEmpty && rutaServidor.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Por favor configure las rutas de guardado en Configuración'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Cargar correcciones y tarjetas
      final correcciones = await _db.getCorreccionesByCierre(widget.cierre.id!);
      final tarjetas = await _db.getTarjetasByCierre(widget.cierre.id!);

      // Combinar otros entrada y salida
      final otros = [..._otrosEntrada, ..._otrosSalida];

      // Guardar PDF
      final rutasGuardadas = await PdfService.generarYGuardarPdf(
        widget.cierre,
        _facturas,
        _boletasCredito,
        _pagos,
        _transferencias,
        _cheques,
        _depositos,
        _notasCredito,
        otros,
        [],
        rutaLocal,
        rutaServidor,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'PDF guardado correctamente:\n${rutasGuardadas.join('\n')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al guardar PDF: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildDocumentoCard(String titulo, IconData icono, Color color,
      List<Widget> items, VoidCallback? onAgregar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, color: color, size: 20),
            const SizedBox(width: 8),
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (onAgregar != null)
              IconButton(
                icon: Icon(Icons.add_circle, color: color),
                onPressed: onAgregar,
                tooltip: 'Agregar $titulo',
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay $titulo registrados',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          )
        else
          ...items,
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('Editar Cierre - ${_dateFormat.format(widget.cierre.fecha)}'),
        actions: [
          if (_hasChanges || _correcciones.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Guardar cambios',
              onPressed: _guardarCambios,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.print),
            tooltip: 'Opciones de impresión',
            onSelected: (value) {
              switch (value) {
                case 'dialogo':
                  _imprimirDialogo();
                  break;
                case 'directo':
                  _imprimirDirecto();
                  break;
                case 'pdf':
                  _guardarPDF();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'dialogo',
                child: Row(
                  children: [
                    Icon(Icons.print, size: 20),
                    SizedBox(width: 8),
                    Text('Imprimir con diálogo'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'directo',
                child: Row(
                  children: [
                    Icon(Icons.print_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Imprimir directo'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, size: 20),
                    SizedBox(width: 8),
                    Text('Guardar PDF'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Información del cierre
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sesión ${widget.cierre.numeroSesion}',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(
                              'Fecha: ${_dateFormat.format(widget.cierre.fecha)}'),
                          if (widget.cierre.nombreCajero != null)
                            Text('Cajero: ${widget.cierre.nombreCajero}'),
                          Text(
                              'Estado: ${widget.cierre.cerrada ? "Cerrada" : "Abierta"}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Efectivo y Tarjetas
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Montos Principales',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _efectivoController,
                            decoration: const InputDecoration(
                                labelText: 'Efectivo',
                                prefixText: '\$',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            inputFormatters: [PesoInputFormatter()],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _tarjetasController,
                            decoration: const InputDecoration(
                                labelText: 'Tarjetas',
                                prefixText: '\$',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            inputFormatters: [PesoInputFormatter()],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Documentos
                  _buildDocumentoCard(
                    'Facturas',
                    Icons.receipt,
                    Colors.blue,
                    _facturas
                        .map((f) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                    f.esCredito
                                        ? Icons.credit_card
                                        : Icons.attach_money,
                                    color: f.esCredito
                                        ? Colors.orange
                                        : Colors.green),
                                title: Text('Factura #${f.numero}'),
                                subtitle: Text(
                                    '${f.esCredito ? "Crédito" : "Contado"} - ${_formatCurrency(f.monto)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editarFactura(f)),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _eliminarFactura(f)),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    _agregarFactura,
                  ),

                  _buildDocumentoCard(
                    'Boletas a Crédito',
                    Icons.credit_score,
                    Colors.orange,
                    _boletasCredito
                        .map((b) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.credit_score,
                                    color: Colors.orange),
                                title: Text('RUT: ${b.rut}'),
                                subtitle: Text(_formatCurrency(b.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () =>
                                            _editarBoletaCredito(b)),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () =>
                                            _eliminarBoletaCredito(b)),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    _agregarBoletaCredito,
                  ),

                  _buildDocumentoCard(
                    'Pagos',
                    Icons.payment,
                    Colors.green,
                    _pagos
                        .map((p) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.payment,
                                    color: Colors.green),
                                title: Text('RUT: ${p.rut}'),
                                subtitle: Text(_formatCurrency(p.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editarPago(p)),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _eliminarPago(p)),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    _agregarPago,
                  ),

                  _buildDocumentoCard(
                    'Transferencias',
                    Icons.swap_horiz,
                    Colors.purple,
                    _transferencias
                        .map((t) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.swap_horiz,
                                    color: Colors.purple),
                                title: Text(_formatCurrency(t.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editarMovimiento(
                                            t, 'Transferencia')),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _eliminarMovimiento(
                                            t, 'Transferencia')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    () => _agregarMovimiento('transferencia', 'Transferencia'),
                  ),

                  _buildDocumentoCard(
                    'Cheques',
                    Icons.card_giftcard,
                    Colors.brown,
                    _cheques
                        .map((c) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.card_giftcard,
                                    color: Colors.brown),
                                title: Text(
                                    '${c.numero != null ? "Cheque #${c.numero}" : "Cheque"}${c.rut != null ? " - RUT: ${c.rut}" : ""}'),
                                subtitle: Text(_formatCurrency(c.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () =>
                                            _editarMovimiento(c, 'Cheque')),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () =>
                                            _eliminarMovimiento(c, 'Cheque')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    () => _agregarMovimiento('cheque', 'Cheque'),
                  ),

                  _buildDocumentoCard(
                    'Depósitos',
                    Icons.account_balance,
                    Colors.teal,
                    _depositos
                        .map((d) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.account_balance,
                                    color: Colors.teal),
                                title: Text(_formatCurrency(d.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () =>
                                            _editarMovimiento(d, 'Depósito')),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () =>
                                            _eliminarMovimiento(d, 'Depósito')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    () => _agregarMovimiento('deposito', 'Depósito'),
                  ),

                  _buildDocumentoCard(
                    'Notas de Crédito',
                    Icons.note,
                    Colors.red,
                    _notasCredito
                        .map((n) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading:
                                    const Icon(Icons.note, color: Colors.red),
                                title: Text(n.numero != null
                                    ? 'Nota #${n.numero}'
                                    : 'Nota de Crédito'),
                                subtitle: Text(_formatCurrency(n.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editarMovimiento(
                                            n, 'Nota Crédito')),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _eliminarMovimiento(
                                            n, 'Nota Crédito')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    () => _agregarMovimiento('nota_credito', 'Nota Crédito'),
                  ),

                  _buildDocumentoCard(
                    'Otros (Entrada)',
                    Icons.add_circle,
                    Colors.indigo,
                    _otrosEntrada
                        .map((o) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.add_circle,
                                    color: Colors.indigo),
                                title: Text(_formatCurrency(o.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editarMovimiento(
                                            o, 'Otros Entrada')),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _eliminarMovimiento(
                                            o, 'Otros Entrada')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    () => _agregarMovimiento('otros_entrada', 'Otros Entrada'),
                  ),

                  _buildDocumentoCard(
                    'Otros (Salida)',
                    Icons.remove_circle,
                    Colors.deepOrange,
                    _otrosSalida
                        .map((o) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.remove_circle,
                                    color: Colors.deepOrange),
                                title: Text(_formatCurrency(o.monto)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editarMovimiento(
                                            o, 'Otros Salida')),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _eliminarMovimiento(
                                            o, 'Otros Salida')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                    () => _agregarMovimiento('otros_salida', 'Otros Salida'),
                  ),

                  // Resumen de correcciones
                  if (_correcciones.isNotEmpty) ...[
                    Card(
                      color: Colors.yellow[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Correcciones pendientes (${_correcciones.length})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.orange[800])),
                            const SizedBox(height: 8),
                            ..._correcciones.map((c) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Text('• ${c.descripcion}',
                                      style: const TextStyle(fontSize: 14)),
                                )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Botón guardar
                  if (_hasChanges || _correcciones.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar Cambios'),
                        onPressed: _guardarCambios,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16)),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
