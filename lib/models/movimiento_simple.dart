/// Modelo para movimientos simples (Transferencias, Cheques, Depósitos, Notas de Crédito)
class MovimientoSimple {
  final int? id;
  final int cierreId;
  final String tipo; // 'transferencia', 'cheque', 'deposito', 'nota_credito'
  final String? numero; // Para notas de crédito y cheques
  final String? rut; // Para cheques
  final double monto;
  final DateTime fecha;
  final String?
      horaDeposito; // Hora que el usuario ingresa del depósito (HH:mm)

  MovimientoSimple({
    this.id,
    required this.cierreId,
    required this.tipo,
    this.numero,
    this.rut,
    required this.monto,
    required this.fecha,
    this.horaDeposito,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cierre_id': cierreId,
      'tipo': tipo,
      'numero': numero,
      'rut': rut,
      'monto': monto,
      'fecha': fecha.toIso8601String(),
      'hora_deposito': horaDeposito,
    };
  }

  factory MovimientoSimple.fromMap(Map<String, dynamic> map) {
    return MovimientoSimple(
      id: map['id'] as int?,
      cierreId: map['cierre_id'] as int,
      tipo: map['tipo'] as String,
      numero: map['numero'] as String?,
      rut: map['rut'] as String?,
      monto: (map['monto'] as num).toDouble(),
      fecha: DateTime.parse(map['fecha'] as String),
      horaDeposito: map['hora_deposito'] as String?,
    );
  }
}
