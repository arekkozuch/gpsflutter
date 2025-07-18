import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'telemetry_screen.dart';

class DeviceScannerScreen extends StatefulWidget {
  const DeviceScannerScreen({super.key});

  @override
  State<DeviceScannerScreen> createState() => _DeviceScannerScreenState();
}

class _DeviceScannerScreenState extends State<DeviceScannerScreen> {
  final List<ScanResult> scanResults = [];
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    initBluetooth();
  }

  Future<void> initBluetooth() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    startScan();
  }

  Future<void> startScan() async {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) async {
      if (!mounted) return;

      List<ScanResult> filteredResults = [];

      for (var result in results) {
        try {
          var deviceName = result.device.platformName;
          debugPrint("🔍 Found: $deviceName");

          if (deviceName == "ESP32_GPS" || deviceName == "ESP32_GPS_Logger") {
            filteredResults.add(result);
          }

          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          debugPrint("⚠️ Error parsing device: $e");
        }
      }

      if (mounted) {
        setState(() {
          scanResults.clear();
          scanResults.addAll(filteredResults);
        });
      }
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛰️ GPS Logger Scanner'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
                      size: 48,
                      color: isScanning ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isScanning ? 'Scanning for GPS Loggers...' : 'Scan Complete',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: isScanning ? null : startScan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Scan Again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gps_off, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No GPS Loggers Found',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure your ESP32 GPS Logger is powered on',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      final result = scanResults[index];
                      final device = result.device;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: Icon(Icons.gps_fixed, color: Colors.green.shade700),
                          ),
                          title: Text(
                            device.platformName.isNotEmpty ? device.platformName : 'Unnamed GPS Logger',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('MAC: ${device.remoteId.str}'),
                              Text('RSSI: ${result.rssi} dBm'),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () async {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TelemetryScreen(device: device),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}