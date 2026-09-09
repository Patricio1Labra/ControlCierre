import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _keyModoFerreteria = 'modo_ferreteria';
  static const String _keyUltimoNumeroFactura = 'ultimo_numero_factura';
  static const String _keyModoDonJose = 'modo_don_jose';
  static const String _keyRutaLocal = 'ruta_guardado_local';
  static const String _keyRutaServidor = 'ruta_guardado_servidor';
  static const String _keyNombreCaja = 'nombre_caja';
  static const String _keyPrinterName = 'printer_name';
  static const String _keyNombreCajero = 'nombre_cajero';
  static const String _keyPanelesVisibles = 'paneles_visibles';

  // Guardar configuración
  static Future<void> saveModoFerreteria(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyModoFerreteria, value);
  }

  static Future<void> saveUltimoNumeroFactura(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUltimoNumeroFactura, value);
  }

  static Future<void> saveModoDonJose(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyModoDonJose, value);
  }

  static Future<void> saveRutaLocal(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRutaLocal, value);
  }

  static Future<void> saveRutaServidor(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRutaServidor, value);
  }

  static Future<void> saveNombreCaja(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombreCaja, value);
  }

  // Cargar configuración
  static Future<bool> getModoFerreteria() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyModoFerreteria) ?? false;
  }

  static Future<int> getUltimoNumeroFactura() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUltimoNumeroFactura) ?? 0;
  }

  static Future<bool> getModoDonJose() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyModoDonJose) ?? false;
  }

  static Future<String> getRutaLocal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRutaLocal) ?? '';
  }

  static Future<String> getRutaServidor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRutaServidor) ?? '';
  }

  static Future<String> getNombreCaja() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNombreCaja) ?? '';
  }

  static Future<void> savePrinterName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrinterName, value);
  }

  static Future<String> getPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrinterName) ?? '';
  }

  static Future<void> saveNombreCajero(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombreCajero, value);
  }

  static Future<String> getNombreCajero() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNombreCajero) ?? '';
  }

  // Guardar y cargar visibilidad de paneles
  static Future<void> savePanelesVisibles(Map<String, bool> paneles) async {
    final prefs = await SharedPreferences.getInstance();
    // Guardar solo los nombres de los paneles visibles
    final panelesVisibles = paneles.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();
    await prefs.setStringList(_keyPanelesVisibles, panelesVisibles);
  }

  static Future<Map<String, bool>> getPanelesVisibles() async {
    final prefs = await SharedPreferences.getInstance();
    final panelesVisibles = prefs.getStringList(_keyPanelesVisibles);

    // Si no hay preferencias guardadas, devolver todos visibles por defecto
    if (panelesVisibles == null) {
      return {
        'factura': true,
        'boleta_credito': true,
        'pago': true,
        'transferencia': true,
        'cheque': true,
        'deposito': true,
        'nota_credito': true,
        'otros': true,
        'don_jose': true,
      };
    }

    // Crear mapa con todos los paneles en false
    final Map<String, bool> resultado = {
      'factura': false,
      'boleta_credito': false,
      'pago': false,
      'transferencia': false,
      'cheque': false,
      'deposito': false,
      'nota_credito': false,
      'otros': false,
      'don_jose': false,
    };

    // Marcar como true solo los que están en la lista guardada
    for (final panel in panelesVisibles) {
      resultado[panel] = true;
    }

    return resultado;
  }
}
