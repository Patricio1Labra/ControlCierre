class Tarjeta {
  final int? id;
  final int cierreId;
  final String numero; // Últimos 4 dígitos o número de autorización
  final double monto;
  final DateTime fecha;

  Tarjeta({
    this.id,
    required this.cierreId,
    required this.numero,
    required this.monto,
    DateTime? fecha,
  }) : fecha = fecha ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cierre_id': cierreId,
      'numero': numero,
      'monto': monto,
      'fecha': fecha.toIso8601String(),
    };
  }

  factory Tarjeta.fromMap(Map<String, dynamic> map) {
    return Tarjeta(
      id: map['id'] as int?,
      cierreId: map['cierre_id'] as int,
      numero: map['numero'] as String,
      monto: map['monto'] as double,
      fecha: DateTime.parse(map['fecha'] as String),
    );
  }

  Tarjeta copyWith({
    int? id,
    int? cierreId,
    String? numero,
    double? monto,
    DateTime? fecha,
  }) {
    return Tarjeta(
      id: id ?? this.id,
      cierreId: cierreId ?? this.cierreId,
      numero: numero ?? this.numero,
      monto: monto ?? this.monto,
      fecha: fecha ?? this.fecha,
    );
  }
}
