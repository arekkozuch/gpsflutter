import 'package:flutter/material.dart';
import 'screens/device_scanner_screen.dart';

void main() {
  runApp(const GpsLoggerApp());
}

class GpsLoggerApp extends StatelessWidget {
  const GpsLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Logger Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
      ),
      home: const DeviceScannerScreen(),
    );
  }
}
