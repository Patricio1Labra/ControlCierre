/// Modelo para representar una corrección realizada en un cierre
class CorreccionCierre {
  final int? id;
  final int cierreId; // ID del cierre al que pertenece esta corrección
  final DateTime fechaCorreccion;
  final String tipoDocumento; // Ej: "Factura", "Boleta Crédito", "Pago", "Efectivo", etc.
  final String? numeroDocumento; // Número del documento si aplica
  final String campoModificado; // Ej: "monto", "documento agregado", "documento eliminado"
  final String? valorAnterior;
  final String? valorNuevo;
  final String descripcion; // Descripción completa: "Corrección Factura #1: antes $500, ahora $1000"

  CorreccionCierre({
    this.id,
    required this.cierreId,
    required this.fechaCorreccion,
    required this.tipoDocumento,
    this.numeroDocumento,
    required this.campoModificado,
    this.valorAnterior,
    this.valorNuevo,
    required this.descripcion,
  });

  // Conversión a Map para SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cierre_id': cierreId,
      'fecha_correccion': fechaCorreccion.toIso8601String(),
      'tipo_documento': tipoDocumento,
      'numero_documento': numeroDocumento,
      'campo_modificado': campoModificado,
      'valor_anterior': valorAnterior,
      'valor_nuevo': valorNuevo,
      'descripcion': descripcion,
    };
  }

  // Conversión desde Map
  factory CorreccionCierre.fromMap(Map<String, dynamic> map) {
    return CorreccionCierre(
      id: map['id'] as int?,
      cierreId: map['cierre_id'] as int,
      fechaCorreccion: DateTime.parse(map['fecha_correccion'] as String),
      tipoDocumento: map['tipo_documento'] as String,
      numeroDocumento: map['numero_documento'] as String?,
      campoModificado: map['campo_modificado'] as String,
      valorAnterior: map['valor_anterior'] as String?,
      valorNuevo: map['valor_nuevo'] as String?,
      descripcion: map['descripcion'] as String,
    );
  }

  // Crear copia con modificaciones
  CorreccionCierre copyWith({
    int? id,
    int? cierreId,
    DateTime? fechaCorreccion,
    String? tipoDocumento,
    String? numeroDocumento,
    String? campoModificado,
    String? valorAnterior,
    String? valorNuevo,
    String? descripcion,
  }) {
    return CorreccionCierre(
      id: id ?? this.id,
      cierreId: cierreId ?? this.cierreId,
      fechaCorreccion: fechaCorreccion ?? this.fechaCorreccion,
      tipoDocumento: tipoDocumento ?? this.tipoDocumento,
      numeroDocumento: numeroDocumento ?? this.numeroDocumento,
      campoModificado: campoModificado ?? this.campoModificado,
      valorAnterior: valorAnterior ?? this.valorAnterior,
      valorNuevo: valorNuevo ?? this.valorNuevo,
      descripcion: descripcion ?? this.descripcion,
    );
  }
}
