/// Modelo para boletas a crédito
class BoletaCredito {
  final int? id;
  final int cierreId;
  final String rut;
  final double monto;
  final DateTime fecha;

  BoletaCredito({
    this.id,
    required this.cierreId,
    required this.rut,
    required this.monto,
    required this.fecha,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cierre_id': cierreId,
      'rut': rut,
      'monto': monto,
      'fecha': fecha.toIso8601String(),
    };
  }

  factory BoletaCredito.fromMap(Map<String, dynamic> map) {
    return BoletaCredito(
      id: map['id'] as int?,
      cierreId: map['cierre_id'] as int,
      rut: map['rut'] as String,
      monto: (map['monto'] as num).toDouble(),
      fecha: DateTime.parse(map['fecha'] as String),
    );
  }
}
