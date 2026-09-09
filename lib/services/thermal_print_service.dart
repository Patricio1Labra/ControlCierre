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
import '../models/configuracion_impresion.dart';
import 'logger_service.dart';

class ThermalPrintService {
  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  static String _formatCurrency(double value) {
    final formatter = NumberFormat('#,##0', 'es_CL');
    return '\$${formatter.format(value)}';
  }

  /// Genera un PDF para impresión térmica de 80mm con solo el resumen
  static Future<pw.Document> generarTicketResumen(
    CierreCaja cierre,
    List<Factura> facturas,
    List<BoletaCredito> boletasCredito,
    List<Pago> pagos,
    List<MovimientoSimple> transferencias,
    List<MovimientoSimple> cheques,
    List<MovimientoSimple> depositos,
    List<MovimientoSimple> notasCredito,
    String nombreCaja,
    List<CorreccionCierre> correcciones,
    List<Tarjeta> tarjetas,
    List<MovimientoSimple> otrosEntrada,
    List<MovimientoSimple> otrosSalida,
  ) async {
    final pdf = pw.Document();

    // Calcular totales
    final facturasContado = facturas.where((f) => !f.esCredito).toList();
    final facturasCredito = facturas.where((f) => f.esCredito).toList();

    final totalFacturasContado = facturasContado.fold<double>(0, (sum, f) => sum + f.monto);
    final totalFacturasCredito = facturasCredito.fold<double>(0, (sum, f) => sum + f.monto);
    final totalBoletasCredito = boletasCredito.fold<double>(0, (sum, b) => sum + b.monto);
    final totalPagos = pagos.fold<double>(0, (sum, p) => sum + p.monto);
    final totalTransferencias = transferencias.fold<double>(0, (sum, t) => sum + t.monto);
    final totalCheques = cheques.fold<double>(0, (sum, c) => sum + c.monto);
    final totalDepositos = depositos.fold<double>(0, (sum, d) => sum + d.monto);
    final totalNotasCredito = notasCredito.fold<double>(0, (sum, n) => sum + n.monto);
    final totalTarjetasIndividuales = tarjetas.fold<double>(0, (sum, t) => sum + t.monto);
    final totalOtrosEntrada = otrosEntrada.fold<double>(0, (sum, o) => sum + o.monto);
    final totalOtrosSalida = otrosSalida.fold<double>(0, (sum, o) => sum + o.monto);
    // Si hay tarjetas individuales, usar su total; sino usar los valores manuales (POS + Pago)
    final totalTarjetas = tarjetas.isNotEmpty ? totalTarjetasIndividuales : (cierre.tarjetas + cierre.tarjetasPago);

    // Cálculos del resumen
    // INGRESOS: depositos, boletas credito, facturas credito, cheques, transferencias, notas de credito, tarjetas, efectivo, otros entrada
    final ingresosTotales = totalDepositos + totalBoletasCredito + totalFacturasCredito +
                           totalCheques + totalTransferencias + totalNotasCredito +
                           totalTarjetas + cierre.efectivo + totalOtrosEntrada;

    // SALIDAS: pagos, total de facturas (todas: contado + credito), fondo caja (apertura), otros salida
    final totalFacturas = totalFacturasContado + totalFacturasCredito;
    final salidasTotales = totalPagos + totalFacturas + cierre.aperturaCaja + totalOtrosSalida;

    final total = ingresosTotales - salidasTotales;

    // Formato de papel térmico 80mm (ancho: 72mm de impresión efectiva)
    const pdfPageFormat = PdfPageFormat(
      72 * PdfPageFormat.mm, // 72mm de ancho efectivo
      double.infinity, // altura infinita (se ajusta al contenido)
      marginAll: 2 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado
            pw.Center(
              child: pw.Text(
                'CONTROL DE CIERRE',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                nombreCaja.isEmpty ? 'RESUMEN' : 'RESUMEN - $nombreCaja',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Información
            _buildLineaThermal('Fecha:', _dateFormat.format(cierre.fecha)),
            if (cierre.nombreCajero != null)
              _buildLineaThermal('Cajero:', cierre.nombreCajero!),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // INGRESOS
            pw.Text(
              'INGRESOS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            _buildLineaThermal('Depósitos:', _formatCurrency(totalDepositos)),
            _buildLineaThermal('Boletas a Crédito:', _formatCurrency(totalBoletasCredito)),
            _buildLineaThermal('Facturas Crédito:', _formatCurrency(totalFacturasCredito)),
            _buildLineaThermal('Cheques:', _formatCurrency(totalCheques)),
            _buildLineaThermal('Transferencias:', _formatCurrency(totalTransferencias)),
            _buildLineaThermal('Notas de Crédito:', _formatCurrency(totalNotasCredito)),

            // Otros con desglose
            if (otrosEntrada.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              _buildLineaThermal('Otros:', _formatCurrency(totalOtrosEntrada)),
              ...otrosEntrada.map((o) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 10),
                      child: pw.Text(
                        o.numero ?? "Sin motivo",
                        style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text(
                        _formatCurrency(o.monto),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
                      ),
                    ),
                  ),
                ],
              )),
            ],

            // Tarjetas individuales o valores manuales
            if (tarjetas.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'Tarjetas Venta:',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              ...tarjetas.map((t) => _buildLineaThermal(
                '  ${t.numero}',
                _formatCurrency(t.monto),
                fontSize: 7,
              )),
              _buildLineaThermal(
                'Total Tarjetas:',
                _formatCurrency(totalTarjetas),
                fontSize: 8,
              ),
            ] else ...[
              _buildLineaThermal('Tarjetas Venta:', _formatCurrency(cierre.tarjetas)),
              if (cierre.tarjetasPago > 0)
                _buildLineaThermal('Tarjetas Pago:', _formatCurrency(cierre.tarjetasPago)),
            ],

            _buildLineaThermal('Efectivo:', _formatCurrency(cierre.efectivo)),
            pw.Divider(thickness: 0.5),
            _buildLineaThermal(
              'TOTAL INGRESOS:',
              _formatCurrency(ingresosTotales),
              bold: true,
              fontSize: 9,
            ),

            pw.SizedBox(height: 4),

            // SALIDAS
            pw.Text(
              'SALIDAS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            _buildLineaThermal('Pagos:', _formatCurrency(totalPagos)),
            _buildLineaThermal('Total Facturas:', _formatCurrency(totalFacturas)),
            _buildLineaThermal('Fondo Caja:', _formatCurrency(cierre.aperturaCaja)),

            // Otros con desglose
            if (otrosSalida.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              _buildLineaThermal('Otros:', _formatCurrency(totalOtrosSalida)),
              ...otrosSalida.map((o) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 10),
                      child: pw.Text(
                        o.numero ?? "Sin motivo",
                        style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text(
                        _formatCurrency(o.monto),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
                      ),
                    ),
                  ),
                ],
              )),
            ],

            pw.Divider(thickness: 0.5),
            _buildLineaThermal(
              'TOTAL SALIDAS:',
              _formatCurrency(salidasTotales),
              bold: true,
              fontSize: 9,
            ),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 2),

            // TOTALES FINALES
            pw.Divider(thickness: 1),
            _buildLineaThermal(
              'TOTAL:',
              _formatCurrency(total),
              bold: true,
              fontSize: 10,
            ),

            // CORRECCIONES
            if (correcciones.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  '⚠ CORRECCIONES',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              ...correcciones.map((corr) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '• ${corr.descripcion}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                  pw.SizedBox(height: 2),
                ],
              )),
            ],

            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                '================================',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  /// Genera un PDF para facturas de contado
  static Future<pw.Document> generarTicketFacturasContado(
    CierreCaja cierre,
    List<Factura> facturas,
    String nombreCaja,
  ) async {
    final pdf = pw.Document();
    final facturasContado = facturas.where((f) => !f.esCredito).toList();

    if (facturasContado.isEmpty) {
      return pdf; // Retorna PDF vacío si no hay facturas de contado
    }

    final totalFacturasContado = facturasContado.fold<double>(0, (sum, f) => sum + f.monto);

    const pdfPageFormat = PdfPageFormat(
      72 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 2 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado
            pw.Center(
              child: pw.Text(
                'FACTURAS DE CONTADO',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                nombreCaja.isEmpty ? '' : nombreCaja,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Información
            _buildLineaThermal('Fecha:', _dateFormat.format(cierre.fecha)),
            if (cierre.nombreCajero != null)
              _buildLineaThermal('Cajero:', cierre.nombreCajero!),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Lista de facturas
            pw.Text(
              'DETALLE DE FACTURAS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            ...facturasContado.map((f) => _buildLineaThermal(
              f.numero,
              _formatCurrency(f.monto),
              fontSize: 8,
            )),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 2),

            // Total
            _buildLineaThermal(
              'TOTAL CONTADO:',
              _formatCurrency(totalFacturasContado),
              bold: true,
              fontSize: 10,
            ),

            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                '================================',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  /// Genera un PDF para facturas a crédito
  static Future<pw.Document> generarTicketFacturasCredito(
    CierreCaja cierre,
    List<Factura> facturas,
    String nombreCaja,
  ) async {
    final pdf = pw.Document();
    final facturasCredito = facturas.where((f) => f.esCredito).toList();

    if (facturasCredito.isEmpty) {
      return pdf; // Retorna PDF vacío si no hay facturas a crédito
    }

    final totalFacturasCredito = facturasCredito.fold<double>(0, (sum, f) => sum + f.monto);

    const pdfPageFormat = PdfPageFormat(
      72 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 2 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado
            pw.Center(
              child: pw.Text(
                'FACTURAS A CRÉDITO',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                nombreCaja.isEmpty ? '' : nombreCaja,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Información
            _buildLineaThermal('Fecha:', _dateFormat.format(cierre.fecha)),
            if (cierre.nombreCajero != null)
              _buildLineaThermal('Cajero:', cierre.nombreCajero!),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Lista de facturas
            pw.Text(
              'DETALLE DE FACTURAS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            ...facturasCredito.map((f) => _buildLineaThermal(
              f.numero,
              _formatCurrency(f.monto),
              fontSize: 8,
            )),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 2),

            // Total
            _buildLineaThermal(
              'TOTAL CRÉDITO:',
              _formatCurrency(totalFacturasCredito),
              bold: true,
              fontSize: 10,
            ),

            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                '================================',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  /// Genera un PDF para el ticket de entrega (Total, Depósitos, Entregó)
  static Future<pw.Document> generarTicketEntrega(
    CierreCaja cierre,
    List<Factura> facturas,
    List<BoletaCredito> boletasCredito,
    List<Pago> pagos,
    List<MovimientoSimple> transferencias,
    List<MovimientoSimple> cheques,
    List<MovimientoSimple> depositos,
    List<MovimientoSimple> notasCredito,
    List<Tarjeta> tarjetas,
    String nombreCaja,
    List<MovimientoSimple> otrosEntrada,
    List<MovimientoSimple> otrosSalida,
  ) async {
    final pdf = pw.Document();

    // Calcular totales
    final facturasContado = facturas.where((f) => !f.esCredito).toList();
    final facturasCredito = facturas.where((f) => f.esCredito).toList();

    final totalFacturasContado = facturasContado.fold<double>(0, (sum, f) => sum + f.monto);
    final totalFacturasCredito = facturasCredito.fold<double>(0, (sum, f) => sum + f.monto);
    final totalBoletasCredito = boletasCredito.fold<double>(0, (sum, b) => sum + b.monto);
    final totalPagos = pagos.fold<double>(0, (sum, p) => sum + p.monto);
    final totalTransferencias = transferencias.fold<double>(0, (sum, t) => sum + t.monto);
    final totalCheques = cheques.fold<double>(0, (sum, c) => sum + c.monto);
    final totalDepositos = depositos.fold<double>(0, (sum, d) => sum + d.monto);
    final totalNotasCredito = notasCredito.fold<double>(0, (sum, n) => sum + n.monto);
    final totalTarjetasIndividuales = tarjetas.fold<double>(0, (sum, t) => sum + t.monto);
    final totalOtrosEntrada = otrosEntrada.fold<double>(0, (sum, o) => sum + o.monto);
    final totalOtrosSalida = otrosSalida.fold<double>(0, (sum, o) => sum + o.monto);
    // Si hay tarjetas individuales, usar su total; sino usar los valores manuales (POS + Pago)
    final totalTarjetas = tarjetas.isNotEmpty ? totalTarjetasIndividuales : (cierre.tarjetas + cierre.tarjetasPago);

    // Cálculos del resumen
    // INGRESOS: depositos, boletas credito, facturas credito, cheques, transferencias, notas de credito, tarjetas, efectivo, otros entrada
    final ingresosTotales = totalDepositos + totalBoletasCredito + totalFacturasCredito +
                           totalCheques + totalTransferencias + totalNotasCredito +
                           totalTarjetas + cierre.efectivo + totalOtrosEntrada;

    // SALIDAS: pagos, total de facturas (todas: contado + credito), fondo caja (apertura), otros salida
    final totalFacturas = totalFacturasContado + totalFacturasCredito;
    final salidasTotales = totalPagos + totalFacturas + cierre.aperturaCaja + totalOtrosSalida;

    final total = ingresosTotales - salidasTotales;

    // Efectivo que entregó (restando 150.000)
    final entrego = cierre.efectivo - 150000;

    const pdfPageFormat = PdfPageFormat(
      72 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 2 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado
            pw.Center(
              child: pw.Text(
                'ENTREGA',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                nombreCaja.isEmpty ? '' : nombreCaja,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Información
            _buildLineaThermal('Fecha:', _dateFormat.format(cierre.fecha)),
            if (cierre.nombreCajero != null)
              _buildLineaThermal('Cajero:', cierre.nombreCajero!),

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Valores
            _buildLineaThermal(
              'Total:',
              _formatCurrency(total),
              bold: true,
              fontSize: 10,
            ),
            pw.SizedBox(height: 4),
            _buildLineaThermal(
              'Depósitos:',
              _formatCurrency(totalDepositos),
              bold: true,
              fontSize: 10,
            ),
            pw.SizedBox(height: 4),
            _buildLineaThermal(
              'Entregó:',
              _formatCurrency(entrego),
              bold: true,
              fontSize: 10,
            ),

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                '================================',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  /// Genera un PDF para impresión térmica de 80mm con solo el resumen de Don José
  static Future<pw.Document> generarTicketDonJose(
    CierreCaja cierre,
    List<MovimientoSimple> donJose,
    String nombreCaja,
  ) async {
    final pdf = pw.Document();

    // Separar boletas y facturas
    final boletas = donJose.where((d) => d.numero != null && d.numero!.startsWith('Boleta')).toList();
    final facturas = donJose.where((d) => d.numero != null && d.numero!.startsWith('Factura')).toList();

    final totalBoletas = boletas.fold<double>(0, (sum, b) => sum + b.monto);
    final totalFacturas = facturas.fold<double>(0, (sum, f) => sum + f.monto);
    final totalGeneral = totalBoletas + totalFacturas;

    // Formato de papel térmico 80mm (ancho: 72mm de impresión efectiva)
    const pdfPageFormat = PdfPageFormat(
      72 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 2 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado
            pw.Center(
              child: pw.Text(
                'CONTROL DE CIERRE',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                nombreCaja.isEmpty ? 'DON JOSÉ' : 'DON JOSÉ - $nombreCaja',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // Información
            _buildLineaThermal('Fecha:', _dateFormat.format(cierre.fecha)),
            if (cierre.nombreCajero != null)
              _buildLineaThermal('Cajero:', cierre.nombreCajero!),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // BOLETAS
            if (boletas.isNotEmpty) ...[
              pw.Text(
                'BOLETAS',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              ...boletas.map((item) {
                final numeroDoc = item.numero!.contains(' ')
                    ? item.numero!.replaceFirst('Boleta ', 'N° ')
                    : 'S/N';
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(numeroDoc, style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(_formatCurrency(item.monto), style: const pw.TextStyle(fontSize: 8)),
                  ],
                );
              }),
              pw.SizedBox(height: 2),
              _buildLineaThermal('Subtotal Boletas:', _formatCurrency(totalBoletas), bold: true),
              pw.SizedBox(height: 4),
            ],

            // FACTURAS
            if (facturas.isNotEmpty) ...[
              pw.Text(
                'FACTURAS',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              ...facturas.map((item) {
                final numeroDoc = item.numero!.contains(' ')
                    ? item.numero!.replaceFirst('Factura ', 'N° ')
                    : 'S/N';
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(numeroDoc, style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(_formatCurrency(item.monto), style: const pw.TextStyle(fontSize: 8)),
                  ],
                );
              }),
              pw.SizedBox(height: 2),
              _buildLineaThermal('Subtotal Facturas:', _formatCurrency(totalFacturas), bold: true),
              pw.SizedBox(height: 4),
            ],

            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // TOTAL GENERAL
            _buildLineaThermal('TOTAL DON JOSÉ:', _formatCurrency(totalGeneral), bold: true, fontSize: 10),

            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                '================================',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  static pw.Widget _buildLineaThermal(
    String label,
    String valor, {
    bool bold = false,
    double fontSize = 8,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Text(
            valor,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  /// Genera e imprime todos los documentos del cierre (facturas contado, crédito y resumen)
  /// Esta función se usa tanto al cerrar la sesión como al reimprimir desde el historial
  ///
  /// [mostrarCorrecciones] determina si se incluyen las correcciones (false para reimpresiones desde historial)
  /// [configuracion] determina qué documentos generar según las preferencias del usuario
  static Future<List<pw.Document>> generarTodosLosDocumentos({
    required CierreCaja cierre,
    required List<Factura> facturas,
    required List<BoletaCredito> boletasCredito,
    required List<Pago> pagos,
    required List<MovimientoSimple> transferencias,
    required List<MovimientoSimple> cheques,
    required List<MovimientoSimple> depositos,
    required List<MovimientoSimple> notasCredito,
    required String nombreCaja,
    List<CorreccionCierre> correcciones = const [],
    List<Tarjeta> tarjetas = const [],
    List<MovimientoSimple> donJose = const [],
    List<MovimientoSimple> otrosEntrada = const [],
    List<MovimientoSimple> otrosSalida = const [],
    bool mostrarCorrecciones = true,
    ConfiguracionImpresion? configuracion,
  }) async {
    try {
      // Si no hay configuración, usar valores por defecto (todo activado)
      final config = configuracion ?? ConfiguracionImpresion();

      await logger.info('ThermalPrint', 'Generando documentos para sesión ${cierre.numeroSesion}');
      await logger.debug('ThermalPrint', 'Configuración: Contado=${config.imprimirFacturasContado}, Crédito=${config.imprimirFacturasCredito}, Resumen=${config.imprimirResumen}, Entrega=${config.imprimirTicketEntrega}, DonJosé=${config.imprimirDonJose}');

      final documentos = <pw.Document>[];

      // 1. Facturas de contado (si está habilitado)
      if (config.imprimirFacturasContado) {
        await logger.debug('ThermalPrint', 'Generando ticket facturas contado');
        final pdfContado = await generarTicketFacturasContado(
          cierre,
          facturas,
          nombreCaja,
        );
        documentos.add(pdfContado);
      } else {
        await logger.debug('ThermalPrint', 'Facturas contado: deshabilitado en configuración');
      }

      // 2. Facturas a crédito (si está habilitado)
      if (config.imprimirFacturasCredito) {
        await logger.debug('ThermalPrint', 'Generando ticket facturas crédito');
        final pdfCredito = await generarTicketFacturasCredito(
          cierre,
          facturas,
          nombreCaja,
        );
        documentos.add(pdfCredito);
      } else {
        await logger.debug('ThermalPrint', 'Facturas crédito: deshabilitado en configuración');
      }

      // 3. Resumen general (si está habilitado)
      if (config.imprimirResumen) {
        await logger.debug('ThermalPrint', 'Generando ticket resumen');
        final pdfResumen = await generarTicketResumen(
          cierre,
          facturas,
          boletasCredito,
          pagos,
          transferencias,
          cheques,
          depositos,
          notasCredito,
          nombreCaja,
          mostrarCorrecciones ? correcciones : [], // Solo mostrar correcciones si se solicita
          tarjetas,
          otrosEntrada,
          otrosSalida,
        );
        documentos.add(pdfResumen);
      } else {
        await logger.debug('ThermalPrint', 'Resumen general: deshabilitado en configuración');
      }

      // 4. Ticket de entrega (si está habilitado)
      if (config.imprimirTicketEntrega) {
        await logger.debug('ThermalPrint', 'Generando ticket entrega');
        final pdfEntrega = await generarTicketEntrega(
          cierre,
          facturas,
          boletasCredito,
          pagos,
          transferencias,
          cheques,
          depositos,
          notasCredito,
          tarjetas,
          nombreCaja,
          otrosEntrada,
          otrosSalida,
        );
        documentos.add(pdfEntrega);
      } else {
        await logger.debug('ThermalPrint', 'Ticket entrega: deshabilitado en configuración');
      }

      // 5. Don José (si está habilitado y hay datos)
      if (config.imprimirDonJose && donJose.isNotEmpty) {
        await logger.debug('ThermalPrint', 'Generando ticket Don José');
        await logger.info('ThermalPrint', 'Don José: ${donJose.length} registros encontrados');
        final pdfDonJose = await generarTicketDonJose(
          cierre,
          donJose,
          nombreCaja,
        );
        documentos.add(pdfDonJose);
      } else if (!config.imprimirDonJose) {
        await logger.debug('ThermalPrint', 'Don José: deshabilitado en configuración');
      } else {
        await logger.debug('ThermalPrint', 'Don José: sin datos, no se generará ticket');
      }

      await logger.info('ThermalPrint', '${documentos.length} documentos térmicos generados exitosamente');
      await logger.logPrintOperation('Documentos térmicos', documentCount: documentos.length);
      return documentos;
    } catch (e, stackTrace) {
      await logger.logPrintError('Documentos térmicos', e, stackTrace);
      rethrow;
    }
  }
}
