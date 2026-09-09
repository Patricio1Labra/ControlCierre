/// Modelo para representar un cierre de caja por sesión
class CierreCaja {
  final int? id;
  final DateTime fecha;
  final int numeroSesion; // Número de sesión del día (1, 2, 3...)
  final String? nombreCajero; // Nombre del cajero (se llena al cerrar)
  final double aperturaCaja;
  final double tarjetas; // Tarjetas Venta - Ingresado manualmente desde POS Transbank
  final double tarjetasPago; // Tarjetas Pago (solo en modo ferretería) - Ingresado manualmente
  final double efectivo; // Ingresado manualmente
  final DateTime fechaCreacion;
  final bool cerrada; // Indica si la sesión está cerrada

  CierreCaja({
    this.id,
    required this.fecha,
    this.numeroSesion = 1,
    this.nombreCajero,
    required this.aperturaCaja,
    this.tarjetas = 0.0,
    this.tarjetasPago = 0.0,
    this.efectivo = 0.0,
    this.cerrada = false,
    DateTime? fechaCreacion,
  }) : fechaCreacion = fechaCreacion ?? DateTime.now();

  // Conversión a Map para SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'numero_sesion': numeroSesion,
      'nombre_cajero': nombreCajero,
      'apertura_caja': aperturaCaja,
      'tarjetas': tarjetas,
      'tarjetas_pago': tarjetasPago,
      'efectivo': efectivo,
      'cerrada': cerrada ? 1 : 0,
      'fecha_creacion': fechaCreacion.toIso8601String(),
    };
  }

  // Conversión desde Map
  factory CierreCaja.fromMap(Map<String, dynamic> map) {
    return CierreCaja(
      id: map['id'] as int?,
      fecha: DateTime.parse(map['fecha'] as String),
      numeroSesion: (map['numero_sesion'] as int?) ?? 1,
      nombreCajero: map['nombre_cajero'] as String?,
      aperturaCaja: (map['apertura_caja'] as num).toDouble(),
      tarjetas: (map['tarjetas'] as num?)?.toDouble() ?? 0.0,
      tarjetasPago: (map['tarjetas_pago'] as num?)?.toDouble() ?? 0.0,
      efectivo: (map['efectivo'] as num?)?.toDouble() ?? 0.0,
      cerrada: ((map['cerrada'] as int?) ?? 0) == 1,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
    );
  }

  // Crear copia con modificaciones
  CierreCaja copyWith({
    int? id,
    DateTime? fecha,
    int? numeroSesion,
    String? nombreCajero,
    double? aperturaCaja,
    double? tarjetas,
    double? tarjetasPago,
    double? efectivo,
    bool? cerrada,
    DateTime? fechaCreacion,
  }) {
    return CierreCaja(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      numeroSesion: numeroSesion ?? this.numeroSesion,
      nombreCajero: nombreCajero ?? this.nombreCajero,
      aperturaCaja: aperturaCaja ?? this.aperturaCaja,
      tarjetas: tarjetas ?? this.tarjetas,
      tarjetasPago: tarjetasPago ?? this.tarjetasPago,
      efectivo: efectivo ?? this.efectivo,
      cerrada: cerrada ?? this.cerrada,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
    );
  }
}
