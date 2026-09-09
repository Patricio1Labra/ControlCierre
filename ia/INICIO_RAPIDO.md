# 🚀 Inicio Rápido - Control de Cierre de Cajas

## ⏱️ 5 minutos para estar funcionando

### 1️⃣ Instalar Flutter (Primera vez - 10-15 min)

#### Windows
```bash
# 1. Descargar Flutter
# Ir a: https://flutter.dev/docs/get-started/install/windows
# Descargar ZIP y extraer en C:\src\flutter

# 2. Agregar al PATH
# Abrir "Editar variables de entorno del sistema"
# Agregar: C:\src\flutter\bin

# 3. Verificar
flutter doctor
```

#### Linux
```bash
# Instalar con snap (más fácil)
sudo snap install flutter --classic

# O descargar manualmente
# https://flutter.dev/docs/get-started/install/linux

# Verificar
flutter doctor
```

#### macOS
```bash
# Descargar de: https://flutter.dev/docs/get-started/install/macos
# O usar homebrew:
brew install --cask flutter

# Verificar
flutter doctor
```

### 2️⃣ Instalar Dependencias (1 minuto)

```bash
cd c:\Datas\Super\ControlCierre
flutter pub get
```

### 3️⃣ Ejecutar la Aplicación (30 segundos)

#### En Windows
```bash
flutter run -d windows
```

#### En Linux
```bash
flutter run -d linux
```

#### En Navegador (cualquier plataforma)
```bash
flutter run -d chrome
```

#### En Android/iOS
```bash
# Conectar dispositivo o iniciar emulador
flutter devices

# Ejecutar
flutter run
```

---

## 📱 Primera Vez Usando la App

### Paso 1: Crear un Cierre de Prueba
1. Presiona el botón **"+ Nuevo Cierre"** (abajo a la derecha)
2. Llena los datos:
   - **Cajero**: Juan Pérez
   - **Fecha**: Hoy
   - **Efectivo Inicial**: 1000
   - **Ventas Efectivo**: 5000
   - **Ventas Tarjeta**: 3000
   - **Ventas Transferencia**: 2000
   - **Gastos**: 500
   - **Retiros**: 1000
   - **Efectivo Final**: 4500
3. La app calculará automáticamente la diferencia
4. Presiona **"Guardar Cierre"**

### Paso 2: Ver el PDF
1. Toca el cierre que acabas de crear
2. Presiona **"Ver PDF"**
3. Verás una vista previa profesional
4. Opciones:
   - **Compartir**: Enviar por email/WhatsApp
   - **Imprimir**: Imprimir directamente
   - **Guardar**: Se guarda automáticamente

---

## 🛠️ Compilar para Distribución

### Windows (Ejecutable .exe)
```bash
flutter build windows --release

# El ejecutable estará en:
# build\windows\runner\Release\control_cierre.exe
```

### Linux (AppImage/Ejecutable)
```bash
flutter build linux --release

# El ejecutable estará en:
# build/linux/x64/release/bundle/control_cierre
```

### Android (APK)
```bash
flutter build apk --release

# El APK estará en:
# build/app/outputs/flutter-apk/app-release.apk
```

### Instalador Windows (Avanzado)
```bash
# Usar Inno Setup para crear instalador
# https://jrsoftware.org/isinfo.php
```

---

## 🎨 Personalización Rápida

### Cambiar nombre de la empresa en el PDF

Edita `lib/services/pdf_service.dart` línea 41:

```dart
pw.Text(
  'FERRETERÍA',  // ← Cambiar aquí
  style: pw.TextStyle(
    fontSize: 16,
    color: PdfColors.grey700,
  ),
),
```

### Agregar logo al PDF

1. Crea carpeta `assets/images/`
2. Guarda tu logo como `logo.png`
3. Actualiza `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/images/logo.png
```
4. En `pdf_service.dart`, agrega:
```dart
final logoImage = await rootBundle.load('assets/images/logo.png');
final logoBytes = logoImage.buffer.asUint8List();
final logo = pw.MemoryImage(logoBytes);

// Luego en el PDF:
pw.Image(logo, width: 100, height: 100),
```

---

## ❓ Problemas Comunes

### "flutter: command not found"
**Solución**: Agrega Flutter al PATH del sistema y reinicia la terminal.

### Error al compilar en Windows
**Solución**: Instala Visual Studio 2022 con "Desktop development with C++".

### App no inicia
**Solución**:
```bash
flutter clean
flutter pub get
flutter run
```

### PDFs no se generan
**Solución**: Verifica permisos de almacenamiento (especialmente en Android).

---

## 📊 Estructura de Archivos Importantes

```
ControlCierre/
├── lib/
│   ├── main.dart                 ← App principal
│   ├── models/
│   │   └── cierre_caja.dart     ← Datos del cierre
│   ├── services/
│   │   ├── database_service.dart ← SQLite
│   │   └── pdf_service.dart      ← Generación PDF ⭐
│   └── screens/
│       ├── home_screen.dart      ← Lista de cierres
│       ├── nuevo_cierre_screen.dart  ← Formulario
│       └── detalle_cierre_screen.dart ← Ver/Compartir PDF
├── pubspec.yaml                  ← Dependencias
└── README.md                     ← Documentación completa
```

---

## 🎯 Próximos Pasos

1. ✅ **Probar la aplicación**
2. ✅ **Personalizar nombre de empresa**
3. ✅ **Agregar logo (opcional)**
4. ✅ **Compilar versión release**
5. ✅ **Distribuir a los usuarios**

---

## 💡 Consejos

- **Desarrollo**: Usa `flutter run` para cambios en caliente
- **Testing**: Crea varios cierres de prueba con diferencias
- **Backup**: La base de datos está en `Documents/databases/`
- **Actualizar**: `flutter pub upgrade` para nuevas versiones

---

## 🆘 Ayuda

- **Documentación Flutter**: https://flutter.dev/docs
- **Reporte de bugs**: Revisa los logs con `flutter logs`
- **Comunidad**: Discord de Flutter

---

**¡Listo! Tu sistema de control de cierres está funcionando.** 🎉
