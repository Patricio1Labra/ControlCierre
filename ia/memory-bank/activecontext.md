# Contexto Actual - Control Cierre

## Proyecto
**Control Cierre** - Sistema de control de cierre de cajas con generación de PDF para ferretería.

## Estado del Proyecto
- **Versión:** 1.0.7+8
- **Plataforma:** Flutter (Windows)
- **SDK:** Dart >=3.0.0 <4.0.0

## Funcionalidades Principales
1. Cierre diario de caja
2. Generación de PDFs para reportes
3. Impresión térmica
4. Integración con Google Drive
5. Historial de cierres
6. Configuración de impresión
7. Actualización del sistema

## Estructura del Proyecto
```
lib/
├── main.dart
├── models/          # Modelos de datos (Factura, CierreCaja, Pago, etc.)
├── screens/         # Pantallas UI
├── services/        # Servicios (Database, PDF, Google Drive, etc.)
└── widgets/         # Componentes reutilizables
```

## Tecnologías Clave
- **Base de datos:** SQLite (sqflite)
- **PDF:** pdf + printing
- **Impresión térmica:** thermal_print_service
- **Google Drive:** google_drive_service
- **Estado:** provider

## Archivos Importantes
- `lib/services/database_service.dart` - Gestión de base de datos
- `lib/screens/cierre_diario_screen.dart` - Pantalla principal de cierre
- `lib/models/factura.dart` - Modelo de factura
- `memory-bank/architecture.md` - Documentación de arquitectura
