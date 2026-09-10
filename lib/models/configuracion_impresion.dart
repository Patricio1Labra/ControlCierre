class ConfiguracionImpresion {
  final int? id;
  final String? impresoraNombre;
  final bool usarImpresoraPorDefecto;
  final bool imprimirFacturasContado;
  final bool imprimirFacturasCredito;
  final bool imprimirFacturasMixtas;
  final bool imprimirResumen;
  final bool imprimirTicketEntrega;
  final bool imprimirDonJose;

  ConfiguracionImpresion({
    this.id,
    this.impresoraNombre,
    this.usarImpresoraPorDefecto = true,
    this.imprimirFacturasContado = true,
    this.imprimirFacturasCredito = true,
    this.imprimirFacturasMixtas = true,
    this.imprimirResumen = true,
    this.imprimirTicketEntrega = true,
    this.imprimirDonJose = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'impresora_nombre': impresoraNombre,
      'usar_impresora_por_defecto': usarImpresoraPorDefecto ? 1 : 0,
      'imprimir_facturas_contado': imprimirFacturasContado ? 1 : 0,
      'imprimir_facturas_credito': imprimirFacturasCredito ? 1 : 0,
      'imprimir_facturas_mixtas': imprimirFacturasMixtas ? 1 : 0,
      'imprimir_resumen': imprimirResumen ? 1 : 0,
      'imprimir_ticket_entrega': imprimirTicketEntrega ? 1 : 0,
      'imprimir_don_jose': imprimirDonJose ? 1 : 0,
    };
  }

  factory ConfiguracionImpresion.fromMap(Map<String, dynamic> map) {
    return ConfiguracionImpresion(
      id: map['id'] as int?,
      impresoraNombre: map['impresora_nombre'] as String?,
      usarImpresoraPorDefecto:
          ((map['usar_impresora_por_defecto'] as int?) ?? 1) == 1,
      imprimirFacturasContado: (map['imprimir_facturas_contado'] as int) == 1,
      imprimirFacturasCredito: (map['imprimir_facturas_credito'] as int) == 1,
      imprimirFacturasMixtas:
          ((map['imprimir_facturas_mixtas'] as int?) ?? 1) == 1,
      imprimirResumen: (map['imprimir_resumen'] as int) == 1,
      imprimirTicketEntrega: (map['imprimir_ticket_entrega'] as int) == 1,
      imprimirDonJose: (map['imprimir_don_jose'] as int) == 1,
    );
  }

  ConfiguracionImpresion copyWith({
    int? id,
    String? impresoraNombre,
    bool? usarImpresoraPorDefecto,
    bool? imprimirFacturasContado,
    bool? imprimirFacturasCredito,
    bool? imprimirFacturasMixtas,
    bool? imprimirResumen,
    bool? imprimirTicketEntrega,
    bool? imprimirDonJose,
  }) {
    return ConfiguracionImpresion(
      id: id ?? this.id,
      impresoraNombre: impresoraNombre ?? this.impresoraNombre,
      usarImpresoraPorDefecto:
          usarImpresoraPorDefecto ?? this.usarImpresoraPorDefecto,
      imprimirFacturasContado:
          imprimirFacturasContado ?? this.imprimirFacturasContado,
      imprimirFacturasCredito:
          imprimirFacturasCredito ?? this.imprimirFacturasCredito,
      imprimirFacturasMixtas:
          imprimirFacturasMixtas ?? this.imprimirFacturasMixtas,
      imprimirResumen: imprimirResumen ?? this.imprimirResumen,
      imprimirTicketEntrega:
          imprimirTicketEntrega ?? this.imprimirTicketEntrega,
      imprimirDonJose: imprimirDonJose ?? this.imprimirDonJose,
    );
  }
}
