import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/cierre_diario_screen.dart';
import 'services/logger_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar logger
  await logger.initialize();
  await logger.info('App', 'Aplicación iniciando...');

  // Inicializar sqflite_ffi para Windows/Linux/Mac
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await logger.info('App', 'Inicializando sqflite_ffi para ${Platform.operatingSystem}');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await initializeDateFormatting('es_ES', null);
  await logger.info('App', 'Aplicación iniciada correctamente');
  runApp(const ControlCierreApp());
}

class ControlCierreApp extends StatelessWidget {
  const ControlCierreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Cierre',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: const CierreDiarioScreen(),
    );
  }
}
