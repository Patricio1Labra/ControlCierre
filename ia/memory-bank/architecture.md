# Arquitectura - Control Cierre

## Estructura del Proyecto

```
lib/
├── main.dart                    # Punto de entrada, configuración inicial
├── models/                      # Modelos de datos (clases con anotaciones JSON)
│   ├── factura.dart             # Factura con items y totales
│   ├── cierre_caja.dart         # Cierre de caja con movimientos
│   ├── pago.dart                # Registro de pagos
│   ├── tarjeta.dart             # Tarjetas de crédito/débito
│   ├── boleta_credito.dart      # Boletas de crédito
│   ├── correccion_cierre.dart    # Correcciones a cierres
│   ├── movimiento_simple.dart   # Movimientos simples
│   ├── configuracion_impresion.dart  # Configuración de impresora
│   └── google_drive_config.dart  # Configuración de Google Drive
├── screens/                     # Pantallas (Widgets StatefulWidget)
│   ├── cierre_diario_screen.dart    # Cierre diario principal
│   ├── detalle_cierre_screen.dart   # Detalle de un cierre específico
│   ├── editar_cierre_screen.dart    # Edición de cierres
│   ├── historial_cierres_screen.dart# Historial de cierres
│   ├── configuracion_impresion_screen.dart  # Configuración de impresión
│   ├── configuracion_google_drive_screen.dart# Google Drive config
│   └── home_screen.dart            # Pantalla principal
├── services/                    # Servicios (Singletons)
│   ├── database_service.dart      # Acceso a base de datos SQLite
│   ├── pdf_service.dart           # Generación de PDFs
│   ├── thermal_print_service.dart # Impresión térmica
│   ├── google_drive_service.dart  # Integración con Google Drive
│   ├── preferences_service.dart   # SharedPreferences
│   ├── update_service.dart        # Verificación de actualizaciones
│   └── logger_service.dart        # Logging
└── widgets/                     # Componentes reutilizables
    └── update_dialog.dart         # Diálogo de actualizaciones
```

## Patrón de Diseño

### 1. Modelo (Models)
- **Patrón:** Data Class con JSON Serialization
- **Características:**
  - Clases `final` con constructores `const`
  - Anotación `@JsonSerializable()` para serialización/deserialización
  - Métodos `fromJson()` y `toJson()` generados automáticamente

### 2. Servicios (Services)
- **Patrón:** Singleton
- **Características:**
  - Instancias únicas por aplicación
  - Gestión de estado asíncrona
  - Uso de `Future` para operaciones asíncronas

### 3. UI (Screens & Widgets)
- **Patrón:** StatefulWidget
- **Gestión de Estado:** Provider
- **Características:**
  - Pantallas como StatefulWidget con state management
  - Widgets reutilizables para componentes comunes

## Flujo de Datos

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   UI Screen │────▶│   Provider   │◀───│   Service    │
└─────────────┘     └──────────────┘     └─────────────┘
                              │
                              ▼
                      ┌──────────────┐
                      │  Database    │
                      │  (SQLite)    │
                      └──────────────┘
```

## Base de Datos (SQLite)

### Tablas Principales

#### `cierre_caja`
- `id`: Primary key
- `fecha`: Fecha del cierre
- `total_ingresos`: Total de ingresos
- `total_egresos`: Total de egresos
- `saldo_final`: Saldo final
- `estado`: Estado del cierre (completado, corregido)

#### `factura`
- `id`: Primary key
- `cierre_id`: Foreign key a cierre_caja
- `numero_factura`: Número de factura
- `total`: Total de la factura
- `fecha`: Fecha de la factura

#### `pago`
- `id`: Primary key
- `factura_id`: Foreign key a factura
- `monto`: Monto pagado
- `tipo_pago`: Tipo de pago (efectivo, tarjeta)
- `fecha`: Fecha del pago

## Generación de PDF

### Servicio: `pdf_service.dart`
- Usa la librería `pdf` para crear documentos PDF
- Soporta:
  - Tablas de datos
  - Imágenes
  - Texto formateado
  - Encabezados y pies de página

### Impresión
- Usa la librería `printing` para imprimir PDFs
- Soporte para impresoras térmicas
- Configuración de márgenes y tamaño de papel

## Integración con Google Drive

### Servicio: `google_drive_service.dart`
- Autenticación OAuth2
- Sincronización de cierres a carpetas específicas
- Configuración guardada en SharedPreferences

## Actualizaciones

### Servicio: `update_service.dart`
- Verifica nuevas versiones desde servidor
- Descarga paquetes de actualización
- Instala actualizaciones (requiere reinicio)

## Configuración Inicial

### `main.dart`
```dart
// Configuración de providers
// Inicialización de servicios
// Configuración de plataforma (Windows)
```

## Dependencias Clave

| Dependencia | Uso |
|------------|-----|
| sqflite | Base de datos local |
| pdf | Generación de PDFs |
| printing | Impresión de PDFs |
| share_plus | Compartir archivos |
| file_picker | Selección de archivos/carpetas |
| shared_preferences | Almacenamiento local |
| http | Verificación de actualizaciones |
| url_launcher | Lanzar URLs (Google Drive) |
| archive | Manejo de archivos ZIP |
