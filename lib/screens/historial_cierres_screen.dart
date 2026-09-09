import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/cierre_caja.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../services/thermal_print_service.dart';
import '../services/preferences_service.dart';
import 'editar_cierre_screen.dart';

class HistorialCierresScreen extends StatefulWidget {
  const HistorialCierresScreen({super.key});

  @override
  State<HistorialCierresScreen> createState() => _HistorialCierresScreenState();
}

class _HistorialCierresScreenState extends State<HistorialCierresScreen> {
  final _db = DatabaseService.instance;
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  final _numberFormat = NumberFormat('#,##0', 'es_CL');

  List<CierreCaja> _cierres = [];
  bool _isLoading = true;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  String _formatCurrency(double amount) {
    return '\$${_numberFormat.format(amount)}';
  }

  @override
  void initState() {
    super.initState();
    _cargarCierres();
  }

  Future<void> _cargarCierres() async {
    setState(() => _isLoading = true);

    try {
      final cierres = await _db.getAllCierres();

      // Filtrar por fecha si se han seleccionado
      List<CierreCaja> cierresFiltrados = cierres;
      if (_fechaInicio != null || _fechaFin != null) {
        cierresFiltrados = cierres.where((cierre) {
          if (_fechaInicio != null && cierre.fecha.isBefore(_fechaInicio!)) {
            return false;
          }
          if (_fechaFin != null && cierre.fecha.isAfter(_fechaFin!.add(const Duration(days: 1)))) {
            return false;
          }
          return true;
        }).toList();
      }

      setState(() {
        _cierres = cierresFiltrados;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar cierres: $e')),
        );
      }
    }
  }

  Future<void> _seleccionarFecha(BuildContext context, bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio ? (_fechaInicio ?? DateTime.now()) : (_fechaFin ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'CL'),
    );

    if (fecha != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = fecha;
        } else {
          _fechaFin = fecha;
        }
      });
      await _cargarCierres();
    }
  }

  Future<void> _limpiarFiltros() async {
    setState(() {
      _fechaInicio = null;
      _fechaFin = null;
    });
    await _cargarCierres();
  }

  Future<void> _editarCierre(CierreCaja cierre) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditarCierreScreen(cierre: cierre),
      ),
    );

    if (resultado == true) {
      await _cargarCierres();
    }
  }

  Future<void> _verCorrecciones(CierreCaja cierre) async {
    final correcciones = await _db.getCorreccionesByCierre(cierre.id!);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Correcciones - Sesión ${cierre.numeroSesion}'),
        content: SizedBox(
          width: double.maxFinite,
          child: correcciones.isEmpty
              ? const Text('No hay correcciones registradas.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: correcciones.length,
                  itemBuilder: (context, index) {
                    final correccion = correcciones[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(correccion.descripcion),
                        subtitle: Text(
                          _dateTimeFormat.format(correccion.fechaCorreccion),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimirDialogo(CierreCaja cierre) async {
    try {
      // Cargar todos los datos del cierre
      final correcciones = await _db.getCorreccionesByCierre(cierre.id!);
      final facturas = await _db.getFacturasByCierre(cierre.id!);
      final boletasCredito = await _db.getBoletasCreditoByCierre(cierre.id!);
      final pagos = await _db.getPagosByCierre(cierre.id!);
      final transferencias = await _db.getMovimientosByCierre(cierre.id!, tipo: 'transferencia');
      final cheques = await _db.getMovimientosByCierre(cierre.id!, tipo: 'cheque');
      final depositos = await _db.getMovimientosByCierre(cierre.id!, tipo: 'deposito');
      final notasCredito = await _db.getMovimientosByCierre(cierre.id!, tipo: 'nota_credito');
      final otrosEntrada = await _db.getMovimientosByCierre(cierre.id!, tipo: 'otros_entrada');
      final otrosSalida = await _db.getMovimientosByCierre(cierre.id!, tipo: 'otros_salida');
      final donJose = await _db.getDonJoseByCierre(cierre.id!);
      final tarjetas = await _db.getTarjetasByCierre(cierre.id!);

      // Cargar configuración
      final rutaLocal = await PreferencesService.getRutaLocal();
      final rutaServidor = await PreferencesService.getRutaServidor();
      final nombreCaja = await PreferencesService.getNombreCaja();

      // Combinar otros entrada y salida
      final otros = [...otrosEntrada, ...otrosSalida];

      // Generar y guardar PDF
      await PdfService.generarYGuardarPdf(
        cierre,
        facturas,
        boletasCredito,
        pagos,
        transferencias,
        cheques,
        depositos,
        notasCredito,
        otros,
        [],
        rutaLocal,
        rutaServidor,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      // Generar todos los documentos usando la función unificada
      // SIN mostrar correcciones (igual que la impresión original)
      final documentos = await ThermalPrintService.generarTodosLosDocumentos(
        cierre: cierre,
        facturas: facturas,
        boletasCredito: boletasCredito,
        pagos: pagos,
        transferencias: transferencias,
        cheques: cheques,
        depositos: depositos,
        notasCredito: notasCredito,
        nombreCaja: nombreCaja,
        correcciones: correcciones,
        tarjetas: tarjetas,
        donJose: donJose,
        mostrarCorrecciones: false, // No mostrar correcciones en reimpresión
      );

      // Mostrar diálogo de impresión para cada documento
      if (!mounted) return;
      for (int i = 0; i < documentos.length; i++) {
        final doc = documentos[i];
        String nombreDoc = 'Cierre_${cierre.numeroSesion}_Doc${i + 1}_${DateFormat('ddMMyyyy').format(cierre.fecha)}.pdf';

        await Printing.layoutPdf(
          onLayout: (format) async => doc.save(),
          name: nombreDoc,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generado y guardado exitosamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar documentos: $e')),
      );
    }
  }

  Future<void> _imprimirDirecto(CierreCaja cierre) async {
    try {
      // Cargar todos los datos del cierre
      final correcciones = await _db.getCorreccionesByCierre(cierre.id!);
      final facturas = await _db.getFacturasByCierre(cierre.id!);
      final boletasCredito = await _db.getBoletasCreditoByCierre(cierre.id!);
      final pagos = await _db.getPagosByCierre(cierre.id!);
      final transferencias = await _db.getMovimientosByCierre(cierre.id!, tipo: 'transferencia');
      final cheques = await _db.getMovimientosByCierre(cierre.id!, tipo: 'cheque');
      final depositos = await _db.getMovimientosByCierre(cierre.id!, tipo: 'deposito');
      final notasCredito = await _db.getMovimientosByCierre(cierre.id!, tipo: 'nota_credito');
      final otrosEntrada = await _db.getMovimientosByCierre(cierre.id!, tipo: 'otros_entrada');
      final otrosSalida = await _db.getMovimientosByCierre(cierre.id!, tipo: 'otros_salida');
      final donJose = await _db.getDonJoseByCierre(cierre.id!);
      final tarjetas = await _db.getTarjetasByCierre(cierre.id!);

      // Cargar configuración
      final rutaLocal = await PreferencesService.getRutaLocal();
      final rutaServidor = await PreferencesService.getRutaServidor();
      final nombreCaja = await PreferencesService.getNombreCaja();
      final printerName = await PreferencesService.getPrinterName();

      // Combinar otros entrada y salida
      final otros = [...otrosEntrada, ...otrosSalida];

      // Generar y guardar PDF
      await PdfService.generarYGuardarPdf(
        cierre,
        facturas,
        boletasCredito,
        pagos,
        transferencias,
        cheques,
        depositos,
        notasCredito,
        otros,
        [],
        rutaLocal,
        rutaServidor,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      // Obtener impresora
      Printer? impresora;
      if (printerName.isNotEmpty) {
        try {
          final impresoras = await Printing.listPrinters();
          if (impresoras.isNotEmpty) {
            impresora = impresoras.firstWhere(
              (p) => p.name == printerName,
              orElse: () => impresoras.first,
            );
          }
        } catch (e) {
          impresora = null;
        }
      }

      // Generar todos los documentos usando la función unificada
      // SIN mostrar correcciones (igual que la impresión original)
      final documentos = await ThermalPrintService.generarTodosLosDocumentos(
        cierre: cierre,
        facturas: facturas,
        boletasCredito: boletasCredito,
        pagos: pagos,
        transferencias: transferencias,
        cheques: cheques,
        depositos: depositos,
        notasCredito: notasCredito,
        nombreCaja: nombreCaja,
        correcciones: correcciones,
        tarjetas: tarjetas,
        donJose: donJose,
        mostrarCorrecciones: false, // No mostrar correcciones en reimpresión
      );

      if (impresora != null) {
        // Imprimir cada documento generado
        for (int i = 0; i < documentos.length; i++) {
          final doc = documentos[i];
          String nombreDoc = 'Cierre_Sesion${cierre.numeroSesion}_Doc${i + 1}';

          await Printing.directPrintPdf(
            printer: impresora,
            onLayout: (format) async => doc.save(),
            name: nombreDoc,
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impresión enviada y PDF guardado exitosamente')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay impresora configurada. PDF guardado exitosamente.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al imprimir: $e')),
      );
    }
  }

  Future<void> _guardarPDF(CierreCaja cierre) async {
    try {
      // Cargar todos los datos del cierre
      final correcciones = await _db.getCorreccionesByCierre(cierre.id!);
      final facturas = await _db.getFacturasByCierre(cierre.id!);
      final boletasCredito = await _db.getBoletasCreditoByCierre(cierre.id!);
      final pagos = await _db.getPagosByCierre(cierre.id!);
      final transferencias = await _db.getMovimientosByCierre(cierre.id!, tipo: 'transferencia');
      final cheques = await _db.getMovimientosByCierre(cierre.id!, tipo: 'cheque');
      final depositos = await _db.getMovimientosByCierre(cierre.id!, tipo: 'deposito');
      final notasCredito = await _db.getMovimientosByCierre(cierre.id!, tipo: 'nota_credito');
      final otrosEntrada = await _db.getMovimientosByCierre(cierre.id!, tipo: 'otros_entrada');
      final otrosSalida = await _db.getMovimientosByCierre(cierre.id!, tipo: 'otros_salida');
      final tarjetas = await _db.getTarjetasByCierre(cierre.id!);

      // Cargar configuración
      final rutaLocal = await PreferencesService.getRutaLocal();
      final rutaServidor = await PreferencesService.getRutaServidor();
      final nombreCaja = await PreferencesService.getNombreCaja();

      // Combinar otros entrada y salida
      final otros = [...otrosEntrada, ...otrosSalida];

      // Generar y guardar PDF
      final rutasGuardadas = await PdfService.generarYGuardarPdf(
        cierre,
        facturas,
        boletasCredito,
        pagos,
        transferencias,
        cheques,
        depositos,
        notasCredito,
        otros,
        [],
        rutaLocal,
        rutaServidor,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      if (!mounted) return;
      if (rutasGuardadas.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF guardado en ${rutasGuardadas.length} ubicación(es)')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No hay rutas configuradas para guardar el PDF')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Cierres'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_off),
            tooltip: 'Limpiar filtros',
            onPressed: _fechaInicio != null || _fechaFin != null ? _limpiarFiltros : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros de fecha
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _fechaInicio != null
                          ? 'Desde: ${_dateFormat.format(_fechaInicio!)}'
                          : 'Fecha inicio',
                    ),
                    onPressed: () => _seleccionarFecha(context, true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _fechaFin != null
                          ? 'Hasta: ${_dateFormat.format(_fechaFin!)}'
                          : 'Fecha fin',
                    ),
                    onPressed: () => _seleccionarFecha(context, false),
                  ),
                ),
              ],
            ),
          ),

          // Lista de cierres
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _cierres.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay cierres registrados',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _cierres.length,
                        itemBuilder: (context, index) {
                          final cierre = _cierres[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cierre.cerrada ? Colors.green : Colors.orange,
                                child: Text(
                                  cierre.numeroSesion.toString(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                _dateFormat.format(cierre.fecha),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sesión ${cierre.numeroSesion} - ${cierre.cerrada ? "Cerrada" : "Abierta"}',
                                  ),
                                  if (cierre.nombreCajero != null)
                                    Text('Cajero: ${cierre.nombreCajero}'),
                                  Text(
                                    'Efectivo: ${_formatCurrency(cierre.efectivo)} | Tarjetas: ${_formatCurrency(cierre.tarjetas)}',
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'editar') {
                                    await _editarCierre(cierre);
                                  } else if (value == 'correcciones') {
                                    await _verCorrecciones(cierre);
                                  } else if (value == 'imprimir_dialogo') {
                                    await _imprimirDialogo(cierre);
                                  } else if (value == 'imprimir_directo') {
                                    await _imprimirDirecto(cierre);
                                  } else if (value == 'guardar_pdf') {
                                    await _guardarPDF(cierre);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'editar',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit),
                                        SizedBox(width: 8),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'correcciones',
                                    child: Row(
                                      children: [
                                        Icon(Icons.history),
                                        SizedBox(width: 8),
                                        Text('Ver correcciones'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'imprimir_dialogo',
                                    child: Row(
                                      children: [
                                        Icon(Icons.print),
                                        SizedBox(width: 8),
                                        Text('Imprimir con diálogo'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'imprimir_directo',
                                    child: Row(
                                      children: [
                                        Icon(Icons.print_outlined),
                                        SizedBox(width: 8),
                                        Text('Imprimir directo'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'guardar_pdf',
                                    child: Row(
                                      children: [
                                        Icon(Icons.picture_as_pdf),
                                        SizedBox(width: 8),
                                        Text('Guardar PDF'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
