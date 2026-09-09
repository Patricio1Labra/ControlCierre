/// Modelo para facturas (contado, crédito o mixto)
class Factura {
  final int? id;
  final int cierreId;
  final String numero;
  final double montoContado;
  final double montoCredito;
  final DateTime fecha;

  Factura({
    this.id,
    required this.cierreId,
    required this.numero,
    this.montoContado = 0,
    this.montoCredito = 0,
    required this.fecha,
  });

  /// Monto total (contado + crédito)
  double get monto => montoContado + montoCredito;

  /// Indica si tiene componente de crédito
  bool get esCredito => montoCredito > 0;

  /// Indica si tiene componente de contado
  bool get esContado => montoContado > 0;

  /// Indica si es mixto (tiene ambos componentes)
  bool get esMixto => montoContado > 0 && montoCredito > 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cierre_id': cierreId,
      'numero': numero,
      'monto': monto,
      'es_credito': esCredito ? 1 : 0,
      'monto_contado': montoContado,
      'monto_credito': montoCredito,
      'fecha': fecha.toIso8601String(),
    };
  }

  factory Factura.fromMap(Map<String, dynamic> map) {
    double montoContado = 0;
    double montoCredito = 0;

    if (map.containsKey('monto_contado') && map['monto_contado'] != null) {
      montoContado = (map['monto_contado'] as num).toDouble();
    }
    if (map.containsKey('monto_credito') && map['monto_credito'] != null) {
      montoCredito = (map['monto_credito'] as num).toDouble();
    }

    // If new columns are both 0, fall back to old behavior (pre-migration data)
    if (montoContado == 0 && montoCredito == 0 && map.containsKey('monto')) {
      final monto = (map['monto'] as num).toDouble();
      final esCredito = (map['es_credito'] as int) == 1;
      montoContado = esCredito ? 0 : monto;
      montoCredito = esCredito ? monto : 0;
    }

    return Factura(
      id: map['id'] as int?,
      cierreId: map['cierre_id'] as int,
      numero: map['numero'] as String,
      montoContado: montoContado,
      montoCredito: montoCredito,
      fecha: DateTime.parse(map['fecha'] as String),
    );
  }
}
