import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/cierre_caja.dart';
import '../models/factura.dart';
import '../models/boleta_credito.dart';
import '../models/pago.dart';
import '../models/movimiento_simple.dart';
import '../models/correccion_cierre.dart';
import '../models/tarjeta.dart';
import 'logger_service.dart';

class PdfService {
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static String _formatCurrency(double value) {
    final formatter = NumberFormat('#,##0', 'es_CL');
    return '\$${formatter.format(value)}';
  }

  static Future<List<String>> generarYGuardarPdf(
    CierreCaja cierre,
    List<Factura> facturas,
    List<BoletaCredito> boletasCredito,
    List<Pago> pagos,
    List<MovimientoSimple> transferencias,
    List<MovimientoSimple> cheques,
    List<MovimientoSimple> depositos,
    List<MovimientoSimple> notasCredito,
    List<MovimientoSimple> otros,
    List<MovimientoSimple> donJose,
    String? rutaLocal,
    String? rutaServidor,
    String nombreCaja,
    List<CorreccionCierre> correcciones,
    List<Tarjeta> tarjetas,
  ) async {
    try {
      await logger.info(
          'PDF', 'Generando PDF para cierre sesión ${cierre.numeroSesion}');

      final pdf = await _generarPdf(
        cierre,
        facturas,
        boletasCredito,
        pagos,
        transferencias,
        cheques,
        depositos,
        notasCredito,
        otros,
        donJose,
        nombreCaja,
        correcciones,
        tarjetas,
      );

      final bytes = await pdf.save();
      await logger.info('PDF', 'PDF generado, tamaño: ${bytes.length} bytes');

      // Crear nombre de archivo con fecha y sesión
      final fechaStr = DateFormat('yyyy-MM-dd').format(cierre.fecha);
      final nombreArchivo =
          'Cierre_${fechaStr}_Sesion${cierre.numeroSesion}.pdf';

      // Obtener datos para la estructura de carpetas
      final nombreCajero = cierre.nombreCajero ?? 'SinNombre';
      final anio = cierre.fecha.year.toString();
      final mes = DateFormat('MM_MMMM', 'es_ES').format(cierre.fecha);

      final List<String> rutasGuardadas = [];

      // Guardar en ruta local si está configurada
      if (rutaLocal != null && rutaLocal.isNotEmpty) {
        final carpetaLocal =
            '$rutaLocal${Platform.pathSeparator}$nombreCajero${Platform.pathSeparator}$anio${Platform.pathSeparator}$mes';
        final dirLocal = Directory(carpetaLocal);
        if (!await dirLocal.exists()) {
          await dirLocal.create(recursive: true);
          await logger.info('PDF', 'Carpeta local creada: $carpetaLocal');
        }
        final archivoLocal =
            File('$carpetaLocal${Platform.pathSeparator}$nombreArchivo');
        await archivoLocal.writeAsBytes(bytes);
        await logger.logFileOperation('Guardar PDF local', archivoLocal.path);
        rutasGuardadas.add(archivoLocal.path);
      }

      // Guardar en ruta servidor si está configurada
      if (rutaServidor != null && rutaServidor.isNotEmpty) {
        final carpetaServidor =
            '$rutaServidor${Platform.pathSeparator}$nombreCajero${Platform.pathSeparator}$anio${Platform.pathSeparator}$mes';
        final dirServidor = Directory(carpetaServidor);
        if (!await dirServidor.exists()) {
          await dirServidor.create(recursive: true);
          await logger.info('PDF', 'Carpeta servidor creada: $carpetaServidor');
        }
        final archivoServidor =
            File('$carpetaServidor${Platform.pathSeparator}$nombreArchivo');
        await archivoServidor.writeAsBytes(bytes);
        await logger.logFileOperation(
            'Guardar PDF servidor', archivoServidor.path);
        rutasGuardadas.add(archivoServidor.path);
      }

      await logger.info('PDF',
          'PDF guardado exitosamente en ${rutasGuardadas.length} ubicaciones');
      return rutasGuardadas;
    } catch (e, stackTrace) {
      await logger.logFileError('Generar y guardar PDF',
          'Cierre sesión ${cierre.numeroSesion}', e, stackTrace);
      rethrow;
    }
  }

  static Future<pw.Document> _generarPdf(
    CierreCaja cierre,
    List<Factura> facturas,
    List<BoletaCredito> boletasCredito,
    List<Pago> pagos,
    List<MovimientoSimple> transferencias,
    List<MovimientoSimple> cheques,
    List<MovimientoSimple> depositos,
    List<MovimientoSimple> notasCredito,
    List<MovimientoSimple> otros,
    List<MovimientoSimple> donJose,
    String nombreCaja,
    List<CorreccionCierre> correcciones,
    List<Tarjeta> tarjetas,
  ) async {
    final pdf = pw.Document();

    // Calcular totales por componente (contado y crédito) sobre TODAS las facturas
    final facturasContado = facturas.where((f) => f.esContado).toList();
    final facturasCredito = facturas.where((f) => f.esCredito).toList();

    final totalFacturasContado =
        facturas.fold<double>(0, (sum, f) => sum + f.montoContado);
    final totalFacturasCredito =
        facturas.fold<double>(0, (sum, f) => sum + f.montoCredito);
    final totalBoletasCredito =
        boletasCredito.fold<double>(0, (sum, b) => sum + b.monto);
    final totalPagos = pagos.fold<double>(0, (sum, p) => sum + p.monto);
    final totalTransferencias =
        transferencias.fold<double>(0, (sum, t) => sum + t.monto);
    final totalCheques = cheques.fold<double>(0, (sum, c) => sum + c.monto);
    final totalDepositos = depositos.fold<double>(0, (sum, d) => sum + d.monto);
    final totalNotasCredito =
        notasCredito.fold<double>(0, (sum, n) => sum + n.monto);
    final totalTarjetasIndividuales =
        tarjetas.fold<double>(0, (sum, t) => sum + t.monto);
    // Si hay tarjetas individuales, usar su total; sino usar los valores manuales (POS + Pago)
    final totalTarjetas = tarjetas.isNotEmpty
        ? totalTarjetasIndividuales
        : (cierre.tarjetas + cierre.tarjetasPago);

    // Separar otros por entrada y salida
    final otrosEntrada = otros.where((o) => o.tipo == 'otros_entrada').toList();
    final otrosSalida = otros.where((o) => o.tipo == 'otros_salida').toList();
    final totalOtrosEntrada =
        otrosEntrada.fold<double>(0, (sum, o) => sum + o.monto);
    final totalOtrosSalida =
        otrosSalida.fold<double>(0, (sum, o) => sum + o.monto);

    // Separar Don José por tipo
    final donJoseBoletas = donJose.where((d) => d.numero == 'Boleta').toList();
    final donJoseFacturas =
        donJose.where((d) => d.numero == 'Factura').toList();

    // Cálculos del resumen
    // INGRESOS: depositos, boletas credito, facturas credito, cheques, transferencias, notas de credito, tarjetas, efectivo, otros entrada
    final ingresosTotales = totalDepositos +
        totalBoletasCredito +
        totalFacturasCredito +
        totalCheques +
        totalTransferencias +
        totalNotasCredito +
        totalTarjetas +
        cierre.efectivo +
        totalOtrosEntrada;

    // SALIDAS: pagos, total de facturas (todas: contado + credito), fondo caja (apertura), otros salida
    final totalFacturas = totalFacturasContado + totalFacturasCredito;
    final salidasTotales =
        totalPagos + totalFacturas + cierre.aperturaCaja + totalOtrosSalida;

    final total = ingresosTotales - salidasTotales;

    // Página 1: Resumen
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildEncabezado('CONTROL DE CIERRE DIARIO', cierre),
            pw.SizedBox(height: 20),
            _buildSeccionResumen(
                cierre, ingresosTotales, salidasTotales, total, nombreCaja),
            pw.SizedBox(height: 20),
            _buildSeccionIngresos(
              totalDepositos,
              totalBoletasCredito,
              totalFacturasCredito,
              totalCheques,
              totalTransferencias,
              totalNotasCredito,
              cierre.tarjetas,
              cierre.tarjetasPago,
              cierre.efectivo,
              totalOtrosEntrada,
              otrosEntrada,
            ),
            pw.SizedBox(height: 20),
            _buildSeccionSalidas(totalPagos, totalFacturas, cierre.aperturaCaja,
                totalOtrosSalida, otrosSalida),
            if (correcciones.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              _buildSeccionCorrecciones(correcciones),
            ],
          ],
        ),
      ),
    );

    // Página 2: Facturas y Boletas
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildEncabezado('FACTURAS Y BOLETAS', cierre),
            pw.SizedBox(height: 20),
            _buildTablaFacturas('FACTURAS CONTADO', facturasContado,
                esContado: true),
            pw.SizedBox(height: 15),
            _buildTablaFacturas('FACTURAS CRÉDITO', facturasCredito,
                esContado: false),
            pw.SizedBox(height: 15),
            _buildTablaBoletasCredito('BOLETAS CRÉDITO', boletasCredito),
          ],
        ),
      ),
    );

    // Página 3: Pagos y Movimientos
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildEncabezado('PAGOS Y MOVIMIENTOS', cierre),
            pw.SizedBox(height: 20),
            _buildTablaPagos('PAGOS', pagos),
            pw.SizedBox(height: 15),
            _buildTablaMovimientos('TRANSFERENCIAS', transferencias),
            pw.SizedBox(height: 15),
            _buildTablaMovimientos('CHEQUES', cheques),
          ],
        ),
      ),
    );

    // Página 4: Depósitos, Notas y Don José
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildEncabezado('DEPÓSITOS, NOTAS Y DON JOSÉ', cierre),
            pw.SizedBox(height: 20),
            _buildTablaMovimientos('DEPÓSITOS', depositos),
            pw.SizedBox(height: 15),
            _buildTablaMovimientos('NOTAS DE CRÉDITO', notasCredito),
            if (donJose.isNotEmpty) ...[
              pw.SizedBox(height: 15),
              _buildTablaDonJose('DON JOSÉ', donJoseBoletas, donJoseFacturas),
            ],
            pw.Spacer(),
            _buildFirmas(),
          ],
        ),
      ),
    );

    return pdf;
  }

  static pw.Widget _buildEncabezado(String titulo, CierreCaja cierre) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Fecha: ${_dateFormat.format(cierre.fecha)}',
          style: const pw.TextStyle(fontSize: 14),
        ),
        if (cierre.nombreCajero != null)
          pw.Text(
            'Cajero: ${cierre.nombreCajero}',
            style: const pw.TextStyle(fontSize: 14),
          ),
        pw.Divider(thickness: 2),
      ],
    );
  }

  static pw.Widget _buildSeccionResumen(
    CierreCaja cierre,
    double ingresosTotales,
    double salidasTotales,
    double total,
    String nombreCaja,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 2),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            nombreCaja.isEmpty ? 'RESUMEN' : 'RESUMEN - $nombreCaja',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Divider(),
          _buildFilaResumen('Total Ingresos:', ingresosTotales, bold: true),
          _buildFilaResumen('Total Salidas:', salidasTotales, bold: true),
          pw.Divider(),
          _buildFilaResumen('TOTAL:', total, bold: true, fontSize: 14),
        ],
      ),
    );
  }

  static pw.Widget _buildSeccionIngresos(
    double depositos,
    double boletasCredito,
    double facturasCredito,
    double cheques,
    double transferencias,
    double notasCredito,
    double tarjetasPOS,
    double tarjetasPago,
    double efectivo,
    double otrosEntrada,
    List<MovimientoSimple> otrosEntradaDetalle,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('INGRESOS',
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          _buildFilaResumen('Depósitos:', depositos),
          _buildFilaResumen('Boletas Crédito:', boletasCredito),
          _buildFilaResumen('Facturas Crédito:', facturasCredito),
          _buildFilaResumen('Cheques:', cheques),
          _buildFilaResumen('Transferencias:', transferencias),
          _buildFilaResumen('Notas de Crédito:', notasCredito),
          _buildFilaResumen('Tarjetas Venta:', tarjetasPOS),
          if (tarjetasPago > 0)
            _buildFilaResumen('Tarjetas Pago:', tarjetasPago),
          _buildFilaResumen('Efectivo:', efectivo),
          if (otrosEntradaDetalle.isNotEmpty) ...[
            _buildFilaResumen('Otros:', otrosEntrada),
            ...otrosEntradaDetalle.map((o) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 30),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        o.numero ?? "Sin motivo",
                        style: pw.TextStyle(
                            fontSize: 10, fontStyle: pw.FontStyle.italic),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 30),
                        child: pw.Text(
                          _formatCurrency(o.monto),
                          style: pw.TextStyle(
                              fontSize: 10, fontStyle: pw.FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildSeccionSalidas(
    double pagos,
    double totalFacturas,
    double fondoCaja,
    double otrosSalida,
    List<MovimientoSimple> otrosSalidaDetalle,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SALIDAS',
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          _buildFilaResumen('Pagos:', pagos),
          _buildFilaResumen('Total Facturas:', totalFacturas),
          _buildFilaResumen('Fondo Caja:', fondoCaja),
          if (otrosSalidaDetalle.isNotEmpty) ...[
            _buildFilaResumen('Otros:', otrosSalida),
            ...otrosSalidaDetalle.map((o) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 30),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        o.numero ?? "Sin motivo",
                        style: pw.TextStyle(
                            fontSize: 10, fontStyle: pw.FontStyle.italic),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 30),
                        child: pw.Text(
                          _formatCurrency(o.monto),
                          style: pw.TextStyle(
                              fontSize: 10, fontStyle: pw.FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildSeccionCorrecciones(
      List<CorreccionCierre> correcciones) {
    final dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange),
        color: PdfColors.orange50,
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                '⚠ CORRECCIONES REALIZADAS',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange900),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.orange300),
          pw.SizedBox(height: 5),
          ...correcciones.map((corr) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            corr.descripcion,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                          pw.Text(
                            dateTimeFormat.format(corr.fechaCorreccion),
                            style: const pw.TextStyle(
                                fontSize: 8, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  static pw.Widget _buildFilaResumen(String label, double valor,
      {bool bold = false, double fontSize = 12}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: bold ? pw.FontWeight.bold : null)),
        pw.Text(
          _formatCurrency(valor),
          style: pw.TextStyle(
              fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      ],
    );
  }

  static pw.Widget _buildTablaFacturas(String titulo, List<Factura> items,
      {required bool esContado}) {
    final total = items.fold<double>(
        0, (sum, f) => sum + (esContado ? f.montoContado : f.montoCredito));
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellHeight: 20,
          data: [
            ['N° Factura', 'Fecha', 'Monto'],
            ...items.map((f) => [
                  f.numero,
                  _dateFormat.format(f.fecha),
                  _formatCurrency(esContado ? f.montoContado : f.montoCredito),
                ]),
            ['', 'TOTAL:', _formatCurrency(total)],
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaBoletasCredito(
      String titulo, List<BoletaCredito> items) {
    final total = items.fold<double>(0, (sum, b) => sum + b.monto);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellHeight: 20,
          data: [
            ['RUT', 'Fecha', 'Monto'],
            ...items.map((b) => [
                  b.rut,
                  _dateFormat.format(b.fecha),
                  _formatCurrency(b.monto),
                ]),
            ['', 'TOTAL:', _formatCurrency(total)],
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaPagos(String titulo, List<Pago> items) {
    final total = items.fold<double>(0, (sum, p) => sum + p.monto);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellHeight: 20,
          data: [
            ['RUT', 'Fecha', 'Monto'],
            ...items.map((p) => [
                  p.rut,
                  _dateFormat.format(p.fecha),
                  _formatCurrency(p.monto),
                ]),
            ['', 'TOTAL:', _formatCurrency(total)],
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaMovimientos(
      String titulo, List<MovimientoSimple> items) {
    final total = items.fold<double>(0, (sum, m) => sum + m.monto);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellHeight: 20,
          data: [
            ['Número/RUT', 'Fecha', 'Monto'],
            ...items.map((m) => [
                  m.numero ?? m.rut ?? '-',
                  _dateFormat.format(m.fecha),
                  _formatCurrency(m.monto),
                ]),
            ['', 'TOTAL:', _formatCurrency(total)],
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaDonJose(String titulo,
      List<MovimientoSimple> boletas, List<MovimientoSimple> facturas) {
    final totalBoletas = boletas.fold<double>(0, (sum, b) => sum + b.monto);
    final totalFacturas = facturas.fold<double>(0, (sum, f) => sum + f.monto);
    final totalGeneral = totalBoletas + totalFacturas;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(),
          ),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Boletas
              if (boletas.isNotEmpty) ...[
                pw.Text('BOLETAS',
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue)),
                pw.SizedBox(height: 5),
                ...boletas.map((b) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(_dateFormat.format(b.fecha),
                              style: const pw.TextStyle(fontSize: 9)),
                          pw.Text(_formatCurrency(b.monto),
                              style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    )),
                pw.Divider(),
                pw.Text('Subtotal Boletas: ${_formatCurrency(totalBoletas)}',
                    style: pw.TextStyle(
                        fontSize: 10, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 8),
              ],

              // Facturas
              if (facturas.isNotEmpty) ...[
                pw.Text('FACTURAS',
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green)),
                pw.SizedBox(height: 5),
                ...facturas.map((f) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(_dateFormat.format(f.fecha),
                              style: const pw.TextStyle(fontSize: 9)),
                          pw.Text(_formatCurrency(f.monto),
                              style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    )),
                pw.Divider(),
                pw.Text('Subtotal Facturas: ${_formatCurrency(totalFacturas)}',
                    style: pw.TextStyle(
                        fontSize: 10, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 8),
              ],

              pw.Divider(thickness: 2),
              pw.Text('TOTAL: ${_formatCurrency(totalGeneral)}',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFirmas() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        pw.Column(
          children: [
            pw.Container(
              width: 200,
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 5),
            pw.Text('Firma Cajero', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.Column(
          children: [
            pw.Container(
              width: 200,
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 5),
            pw.Text('Firma Supervisor',
                style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
