import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/cierre_caja.dart';
import '../models/factura.dart';
import '../models/boleta_credito.dart';
import '../models/pago.dart';
import '../models/movimiento_simple.dart';
import '../models/correccion_cierre.dart';
import '../models/tarjeta.dart';
import '../models/configuracion_impresion.dart';
import '../models/google_drive_config.dart';
import 'logger_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('control_cierre.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 12,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Agregar nuevas columnas para sesiones
      await db.execute(
          'ALTER TABLE cierres_caja ADD COLUMN numero_sesion INTEGER NOT NULL DEFAULT 1');
      await db
          .execute('ALTER TABLE cierres_caja ADD COLUMN nombre_cajero TEXT');
      await db.execute(
          'ALTER TABLE cierres_caja ADD COLUMN cerrada INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      // Agregar tabla de correcciones
      await db.execute('''
        CREATE TABLE correcciones_cierre (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cierre_id INTEGER NOT NULL,
          fecha_correccion TEXT NOT NULL,
          tipo_documento TEXT NOT NULL,
          numero_documento TEXT,
          campo_modificado TEXT NOT NULL,
          valor_anterior TEXT,
          valor_nuevo TEXT,
          descripcion TEXT NOT NULL,
          FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      // Agregar tabla de tarjetas
      await db.execute('''
        CREATE TABLE tarjetas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cierre_id INTEGER NOT NULL,
          numero TEXT NOT NULL,
          monto REAL NOT NULL,
          fecha TEXT NOT NULL,
          FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 5) {
      // Agregar tabla de configuración de impresión
      await db.execute('''
        CREATE TABLE configuracion_impresion (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          impresora_nombre TEXT,
          imprimir_facturas_contado INTEGER NOT NULL DEFAULT 1,
          imprimir_facturas_credito INTEGER NOT NULL DEFAULT 1,
          imprimir_resumen INTEGER NOT NULL DEFAULT 1,
          imprimir_ticket_entrega INTEGER NOT NULL DEFAULT 1,
          imprimir_don_jose INTEGER NOT NULL DEFAULT 1
        )
      ''');
      // Insertar configuración por defecto
      await db.execute('''
        INSERT INTO configuracion_impresion (
          imprimir_facturas_contado,
          imprimir_facturas_credito,
          imprimir_resumen,
          imprimir_ticket_entrega,
          imprimir_don_jose
        ) VALUES (1, 1, 1, 1, 1)
      ''');
    }
    if (oldVersion < 6) {
      // Agregar columna tarjetas_pago para modo ferretería
      await db.execute(
          'ALTER TABLE cierres_caja ADD COLUMN tarjetas_pago REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      // Agregar tabla de configuración de Google Drive
      await db.execute('''
        CREATE TABLE google_drive_config (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          habilitado INTEGER NOT NULL DEFAULT 0,
          credenciales_json TEXT,
          carpeta_id TEXT,
          subir_automaticamente INTEGER NOT NULL DEFAULT 1
        )
      ''');
      // Insertar configuración por defecto
      await db.execute('''
        INSERT INTO google_drive_config (habilitado, subir_automaticamente)
        VALUES (0, 1)
      ''');
    }
    if (oldVersion < 8) {
      // Migrar de Service Account a OAuth2
      // Eliminar tabla antigua y crear nueva con campos OAuth2
      await db.execute('DROP TABLE IF EXISTS google_drive_config');
      await db.execute('''
        CREATE TABLE google_drive_config (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          habilitado INTEGER NOT NULL DEFAULT 0,
          client_id TEXT,
          client_secret TEXT,
          access_token TEXT,
          refresh_token TEXT,
          token_expiry INTEGER,
          carpeta_id TEXT,
          subir_automaticamente INTEGER NOT NULL DEFAULT 1
        )
      ''');
      // Insertar configuración por defecto
      await db.execute('''
        INSERT INTO google_drive_config (habilitado, subir_automaticamente)
        VALUES (0, 1)
      ''');
    }
    if (oldVersion < 9) {
      // Agregar columnas monto_contado y monto_credito a facturas para soporte de doble método
      await db.execute(
          'ALTER TABLE facturas ADD COLUMN monto_contado REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE facturas ADD COLUMN monto_credito REAL NOT NULL DEFAULT 0');

      // Migrar datos existentes: convertir es_credito y monto a los nuevos campos
      await db.execute(
          'UPDATE facturas SET monto_contado = CASE WHEN es_credito = 0 THEN monto ELSE 0 END, monto_credito = CASE WHEN es_credito = 1 THEN monto ELSE 0 END');
    }
    if (oldVersion < 10) {
      // Agregar opción de imprimir facturas mixtas
      await db.execute(
          'ALTER TABLE configuracion_impresion ADD COLUMN imprimir_facturas_mixtas INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 11) {
      // Agregar opción de usar impresora por defecto
      await db.execute(
          'ALTER TABLE configuracion_impresion ADD COLUMN usar_impresora_por_defecto INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 12) {
      // Agregar columna hora_deposito para depósitos
      await db.execute(
          'ALTER TABLE movimientos_simples ADD COLUMN hora_deposito TEXT');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla principal de cierres
    await db.execute('''
      CREATE TABLE cierres_caja (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        numero_sesion INTEGER NOT NULL DEFAULT 1,
        nombre_cajero TEXT,
        apertura_caja REAL NOT NULL,
        tarjetas REAL NOT NULL DEFAULT 0,
        tarjetas_pago REAL NOT NULL DEFAULT 0,
        efectivo REAL NOT NULL DEFAULT 0,
        cerrada INTEGER NOT NULL DEFAULT 0,
        fecha_creacion TEXT NOT NULL
      )
    ''');

    // Tabla de facturas (contado, crédito o mixto)
    await db.execute('''
      CREATE TABLE facturas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cierre_id INTEGER NOT NULL,
        numero TEXT NOT NULL,
        monto REAL NOT NULL,
        es_credito INTEGER NOT NULL,
        monto_contado REAL NOT NULL DEFAULT 0,
        monto_credito REAL NOT NULL DEFAULT 0,
        fecha TEXT NOT NULL,
        FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de boletas a crédito
    await db.execute('''
      CREATE TABLE boletas_credito (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cierre_id INTEGER NOT NULL,
        rut TEXT NOT NULL,
        monto REAL NOT NULL,
        fecha TEXT NOT NULL,
        FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de pagos
    await db.execute('''
      CREATE TABLE pagos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cierre_id INTEGER NOT NULL,
        rut TEXT NOT NULL,
        monto REAL NOT NULL,
        fecha TEXT NOT NULL,
        FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de movimientos simples (transferencias, cheques, depósitos, notas de crédito)
    await db.execute('''
      CREATE TABLE movimientos_simples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cierre_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        numero TEXT,
        rut TEXT,
        monto REAL NOT NULL,
        fecha TEXT NOT NULL,
        FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de correcciones de cierre
    await db.execute('''
      CREATE TABLE correcciones_cierre (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cierre_id INTEGER NOT NULL,
        fecha_correccion TEXT NOT NULL,
        tipo_documento TEXT NOT NULL,
        numero_documento TEXT,
        campo_modificado TEXT NOT NULL,
        valor_anterior TEXT,
        valor_nuevo TEXT,
        descripcion TEXT NOT NULL,
        FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de tarjetas
    await db.execute('''
      CREATE TABLE tarjetas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cierre_id INTEGER NOT NULL,
        numero TEXT NOT NULL,
        monto REAL NOT NULL,
        fecha TEXT NOT NULL,
        FOREIGN KEY (cierre_id) REFERENCES cierres_caja (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de configuración de impresión
    await db.execute('''
      CREATE TABLE configuracion_impresion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        impresora_nombre TEXT,
        imprimir_facturas_contado INTEGER NOT NULL DEFAULT 1,
        imprimir_facturas_credito INTEGER NOT NULL DEFAULT 1,
        imprimir_resumen INTEGER NOT NULL DEFAULT 1,
        imprimir_ticket_entrega INTEGER NOT NULL DEFAULT 1,
        imprimir_don_jose INTEGER NOT NULL DEFAULT 1,
        imprimir_facturas_mixtas INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Insertar configuración por defecto
    await db.execute('''
      INSERT INTO configuracion_impresion (
        imprimir_facturas_contado,
        imprimir_facturas_credito,
        imprimir_resumen,
        imprimir_ticket_entrega,
        imprimir_don_jose,
        imprimir_facturas_mixtas
      ) VALUES (1, 1, 1, 1, 1, 1)
    ''');

    // Tabla de configuración de Google Drive (OAuth2)
    await db.execute('''
      CREATE TABLE google_drive_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        habilitado INTEGER NOT NULL DEFAULT 0,
        client_id TEXT,
        client_secret TEXT,
        access_token TEXT,
        refresh_token TEXT,
        token_expiry INTEGER,
        carpeta_id TEXT,
        subir_automaticamente INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Insertar configuración por defecto de Google Drive
    await db.execute('''
      INSERT INTO google_drive_config (habilitado, subir_automaticamente)
      VALUES (0, 1)
    ''');

    // Índices para acelerar queries por cierre_id
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_facturas_cierre ON facturas(cierre_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_boletas_cierre ON boletas_credito(cierre_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pagos_cierre ON pagos(cierre_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_movimientos_cierre ON movimientos_simples(cierre_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_movimientos_tipo ON movimientos_simples(cierre_id, tipo)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_correcciones_cierre ON correcciones_cierre(cierre_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tarjetas_cierre ON tarjetas(cierre_id)');
  }

  // CRUD para CierreCaja
  Future<int> insertCierre(CierreCaja cierre) async {
    try {
      await logger.logDatabaseOperation('INSERT', 'cierres_caja', data: {
        'numeroSesion': cierre.numeroSesion,
        'cajero': cierre.nombreCajero
      });
      final db = await database;
      final id = await db.insert('cierres_caja', cierre.toMap());
      await logger.info('Database', 'Cierre creado con ID: $id');
      return id;
    } catch (e, stackTrace) {
      await logger.logDatabaseError('INSERT', 'cierres_caja', e, stackTrace);
      rethrow;
    }
  }

  Future<CierreCaja?> getCierre(int id) async {
    final db = await database;
    final maps = await db.query(
      'cierres_caja',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return CierreCaja.fromMap(maps.first);
  }

  Future<List<CierreCaja>> getAllCierres() async {
    final db = await database;
    final maps = await db.query(
      'cierres_caja',
      orderBy: 'fecha DESC',
    );
    return maps.map((map) => CierreCaja.fromMap(map)).toList();
  }

  Future<CierreCaja?> getCierreByDate(DateTime fecha) async {
    final db = await database;
    final fechaStr = fecha.toIso8601String().split('T')[0];
    final maps = await db.query(
      'cierres_caja',
      where: 'date(fecha) = date(?) AND cerrada = 0',
      whereArgs: [fechaStr],
      orderBy: 'numero_sesion DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return CierreCaja.fromMap(maps.first);
  }

  Future<int> getNextSessionNumber(DateTime fecha) async {
    final db = await database;
    final fechaStr = fecha.toIso8601String().split('T')[0];
    final result = await db.rawQuery(
      'SELECT MAX(numero_sesion) as max_session FROM cierres_caja WHERE date(fecha) = date(?)',
      [fechaStr],
    );
    return ((result.first['max_session'] as int?) ?? 0) + 1;
  }

  Future<List<CierreCaja>> getCierresByDate(DateTime fecha) async {
    final db = await database;
    final fechaStr = fecha.toIso8601String().split('T')[0];
    final maps = await db.query(
      'cierres_caja',
      where: 'date(fecha) = date(?)',
      whereArgs: [fechaStr],
      orderBy: 'numero_sesion ASC',
    );
    return maps.map((map) => CierreCaja.fromMap(map)).toList();
  }

  Future<int> updateCierre(CierreCaja cierre) async {
    try {
      await logger.logDatabaseOperation('UPDATE', 'cierres_caja',
          data: {'id': cierre.id, 'cerrada': cierre.cerrada});
      final db = await database;
      final result = await db.update(
        'cierres_caja',
        cierre.toMap(),
        where: 'id = ?',
        whereArgs: [cierre.id],
      );
      await logger.info('Database', 'Cierre ID ${cierre.id} actualizado');
      return result;
    } catch (e, stackTrace) {
      await logger.logDatabaseError('UPDATE', 'cierres_caja', e, stackTrace);
      rethrow;
    }
  }

  Future<int> deleteCierre(int id) async {
    try {
      await logger
          .logDatabaseOperation('DELETE', 'cierres_caja', data: {'id': id});
      final db = await database;
      final result = await db.delete(
        'cierres_caja',
        where: 'id = ?',
        whereArgs: [id],
      );
      await logger.warning('Database', 'Cierre ID $id eliminado');
      return result;
    } catch (e, stackTrace) {
      await logger.logDatabaseError('DELETE', 'cierres_caja', e, stackTrace);
      rethrow;
    }
  }

  // CRUD para Facturas
  Future<int> insertFactura(Factura factura) async {
    try {
      await logger.logDatabaseOperation('INSERT', 'facturas', data: {
        'numero': factura.numero,
        'montoContado': factura.montoContado,
        'montoCredito': factura.montoCredito
      });
      final db = await database;
      final id = await db.insert('facturas', factura.toMap());
      await logger.info(
          'Database', 'Factura ${factura.numero} creada con ID: $id');
      return id;
    } catch (e, stackTrace) {
      await logger.logDatabaseError('INSERT', 'facturas', e, stackTrace);
      rethrow;
    }
  }

  Future<List<Factura>> getFacturasByCierre(int cierreId) async {
    final db = await database;
    final maps = await db.query(
      'facturas',
      where: 'cierre_id = ?',
      whereArgs: [cierreId],
      orderBy: 'fecha DESC',
    );
    return maps.map((map) => Factura.fromMap(map)).toList();
  }

  Future<int> updateFactura(Factura factura) async {
    try {
      await logger.logDatabaseOperation('UPDATE', 'facturas',
          data: {'id': factura.id, 'numero': factura.numero});
      final db = await database;
      return await db.update(
        'facturas',
        factura.toMap(),
        where: 'id = ?',
        whereArgs: [factura.id],
      );
    } catch (e, stackTrace) {
      await logger.logDatabaseError('UPDATE', 'facturas', e, stackTrace);
      rethrow;
    }
  }

  Future<int> deleteFactura(int id) async {
    try {
      await logger.logDatabaseOperation('DELETE', 'facturas', data: {'id': id});
      final db = await database;
      return await db.delete(
        'facturas',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stackTrace) {
      await logger.logDatabaseError('DELETE', 'facturas', e, stackTrace);
      rethrow;
    }
  }

  // CRUD para Boletas de Crédito
  Future<int> insertBoletaCredito(BoletaCredito boleta) async {
    final db = await database;
    return await db.insert('boletas_credito', boleta.toMap());
  }

  Future<List<BoletaCredito>> getBoletasCreditoByCierre(int cierreId) async {
    final db = await database;
    final maps = await db.query(
      'boletas_credito',
      where: 'cierre_id = ?',
      whereArgs: [cierreId],
      orderBy: 'fecha DESC',
    );
    return maps.map((map) => BoletaCredito.fromMap(map)).toList();
  }

  Future<int> updateBoletaCredito(BoletaCredito boleta) async {
    final db = await database;
    return await db.update(
      'boletas_credito',
      boleta.toMap(),
      where: 'id = ?',
      whereArgs: [boleta.id],
    );
  }

  Future<int> deleteBoletaCredito(int id) async {
    final db = await database;
    return await db.delete(
      'boletas_credito',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD para Pagos
  Future<int> insertPago(Pago pago) async {
    try {
      await logger.logDatabaseOperation('INSERT', 'pagos',
          data: {'rut': pago.rut, 'monto': pago.monto});
      final db = await database;
      return await db.insert('pagos', pago.toMap());
    } catch (e, stackTrace) {
      await logger.logDatabaseError('INSERT', 'pagos', e, stackTrace);
      rethrow;
    }
  }

  Future<List<Pago>> getPagosByCierre(int cierreId) async {
    final db = await database;
    final maps = await db.query(
      'pagos',
      where: 'cierre_id = ?',
      whereArgs: [cierreId],
      orderBy: 'fecha DESC',
    );
    return maps.map((map) => Pago.fromMap(map)).toList();
  }

  Future<int> updatePago(Pago pago) async {
    final db = await database;
    return await db.update(
      'pagos',
      pago.toMap(),
      where: 'id = ?',
      whereArgs: [pago.id],
    );
  }

  Future<int> deletePago(int id) async {
    final db = await database;
    return await db.delete(
      'pagos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD para Movimientos Simples
  Future<int> insertMovimiento(MovimientoSimple movimiento) async {
    try {
      await logger.logDatabaseOperation('INSERT', 'movimientos_simples', data: {
        'tipo': movimiento.tipo,
        'numero': movimiento.numero,
        'monto': movimiento.monto
      });
      final db = await database;
      return await db.insert('movimientos_simples', movimiento.toMap());
    } catch (e, stackTrace) {
      await logger.logDatabaseError(
          'INSERT', 'movimientos_simples', e, stackTrace);
      rethrow;
    }
  }

  Future<List<MovimientoSimple>> getMovimientosByCierre(int cierreId,
      {String? tipo}) async {
    final db = await database;
    final maps = await db.query(
      'movimientos_simples',
      where: tipo != null ? 'cierre_id = ? AND tipo = ?' : 'cierre_id = ?',
      whereArgs: tipo != null ? [cierreId, tipo] : [cierreId],
      orderBy: 'fecha DESC',
    );
    return maps.map((map) => MovimientoSimple.fromMap(map)).toList();
  }

  Future<int> updateMovimiento(MovimientoSimple movimiento) async {
    final db = await database;
    return await db.update(
      'movimientos_simples',
      movimiento.toMap(),
      where: 'id = ?',
      whereArgs: [movimiento.id],
    );
  }

  Future<int> deleteMovimiento(int id) async {
    final db = await database;
    return await db.delete(
      'movimientos_simples',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD para Correcciones de Cierre
  Future<int> insertCorreccion(CorreccionCierre correccion) async {
    final db = await database;
    return await db.insert('correcciones_cierre', correccion.toMap());
  }

  Future<List<CorreccionCierre>> getCorreccionesByCierre(int cierreId) async {
    final db = await database;
    final maps = await db.query(
      'correcciones_cierre',
      where: 'cierre_id = ?',
      whereArgs: [cierreId],
      orderBy: 'fecha_correccion DESC',
    );
    return maps.map((map) => CorreccionCierre.fromMap(map)).toList();
  }

  Future<int> deleteCorreccion(int id) async {
    final db = await database;
    return await db.delete(
      'correcciones_cierre',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD para Tarjetas
  Future<int> insertTarjeta(Tarjeta tarjeta) async {
    final db = await database;
    return await db.insert('tarjetas', tarjeta.toMap());
  }

  Future<List<Tarjeta>> getTarjetasByCierre(int cierreId) async {
    final db = await database;
    final maps = await db.query(
      'tarjetas',
      where: 'cierre_id = ?',
      whereArgs: [cierreId],
      orderBy: 'fecha ASC',
    );
    return maps.map((map) => Tarjeta.fromMap(map)).toList();
  }

  Future<int> deleteTarjeta(int id) async {
    final db = await database;
    return await db.delete(
      'tarjetas',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateTarjeta(Tarjeta tarjeta) async {
    final db = await database;
    return await db.update(
      'tarjetas',
      tarjeta.toMap(),
      where: 'id = ?',
      whereArgs: [tarjeta.id],
    );
  }

  // CRUD para ConfiguracionImpresion
  Future<ConfiguracionImpresion> getConfiguracionImpresion() async {
    try {
      await logger.logDatabaseOperation('SELECT', 'configuracion_impresion');
      final db = await database;
      final maps = await db.query(
        'configuracion_impresion',
        limit: 1,
      );

      if (maps.isEmpty) {
        // Si no existe, crear configuración por defecto
        final config = ConfiguracionImpresion();
        await insertConfiguracionImpresion(config);
        return config;
      }

      return ConfiguracionImpresion.fromMap(maps.first);
    } catch (e, stackTrace) {
      await logger.logDatabaseError(
          'SELECT', 'configuracion_impresion', e, stackTrace);
      rethrow;
    }
  }

  Future<int> insertConfiguracionImpresion(
      ConfiguracionImpresion config) async {
    try {
      await logger.logDatabaseOperation('INSERT', 'configuracion_impresion');
      final db = await database;
      final id = await db.insert('configuracion_impresion', config.toMap());
      await logger.info(
          'Database', 'Configuración de impresión creada con ID: $id');
      return id;
    } catch (e, stackTrace) {
      await logger.logDatabaseError(
          'INSERT', 'configuracion_impresion', e, stackTrace);
      rethrow;
    }
  }

  Future<int> updateConfiguracionImpresion(
      ConfiguracionImpresion config) async {
    try {
      await logger.logDatabaseOperation('UPDATE', 'configuracion_impresion',
          data: {'id': config.id});
      final db = await database;
      final count = await db.update(
        'configuracion_impresion',
        config.toMap(),
        where: 'id = ?',
        whereArgs: [config.id],
      );
      await logger.info('Database', 'Configuración de impresión actualizada');
      return count;
    } catch (e, stackTrace) {
      await logger.logDatabaseError(
          'UPDATE', 'configuracion_impresion', e, stackTrace);
      rethrow;
    }
  }

  // Métodos de conveniencia para Don José (usa movimientos_simples con tipo='don_jose')
  Future<List<MovimientoSimple>> getDonJoseByCierre(int cierreId) async {
    return await getMovimientosByCierre(cierreId, tipo: 'don_jose');
  }

  Future<int> insertDonJose(MovimientoSimple donJose) async {
    return await insertMovimiento(donJose);
  }

  Future<int> deleteDonJose(int id) async {
    return await deleteMovimiento(id);
  }

  // CRUD para Google Drive Config
  Future<GoogleDriveConfig?> getGoogleDriveConfig() async {
    try {
      final db = await database;
      final result = await db.query(
        'google_drive_config',
        limit: 1,
      );

      if (result.isEmpty) {
        return null;
      }

      return GoogleDriveConfig.fromMap(result.first);
    } catch (e, stackTrace) {
      await logger.error('DB', 'Error al obtener configuración de Google Drive',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<int> updateGoogleDriveConfig(GoogleDriveConfig config) async {
    try {
      final db = await database;

      // Primero verificar si existe
      final existing = await getGoogleDriveConfig();

      if (existing == null) {
        // Si no existe, insertar
        return await db.insert('google_drive_config', config.toMap());
      } else {
        // Si existe, actualizar
        return await db.update(
          'google_drive_config',
          config.toMap(),
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      }
    } catch (e, stackTrace) {
      await logger.error(
          'DB', 'Error al actualizar configuración de Google Drive',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
