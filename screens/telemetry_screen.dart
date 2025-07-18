import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import '../models/telemetry_data.dart';
import '../services/ble_service.dart';
import '../widgets/gforce_meter.dart';
import 'views/map_view.dart';
import 'views/data_view.dart';
import 'views/sessions_view.dart';

class TelemetryScreen extends StatefulWidget {
  final BluetoothDevice device;

  const TelemetryScreen({super.key, required this.device});

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen>
    with TickerProviderStateMixin {
  final BLEService _bleService = BLEService();
  TelemetryData? _currentData;
  bool _isLogging = false;
  int _packetCount = 0;
  Timer? _connectionTimer;
  
  final List<LatLng> _trackPoints = [];
  LatLng? _currentPosition;
  late TabController _tabController;
  
  List<Map<String, dynamic>> _sessionFiles = [];
  bool _isLoadingSessions = false;
  String _lastCommandResponse = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _connectToDevice();
    
    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (!_bleService.isConnected && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📱 Device disconnected"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    _tabController.dispose();
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    final success = await _bleService.connectToDevice(widget.device);
    if (success) {
      _bleService.getTelemetryStream()?.listen((data) {
        if (mounted) {
          setState(() {
            _currentData = data;
            _packetCount++;
            
            if (data.latitude != 0.0 && data.longitude != 0.0) {
              _currentPosition = LatLng(data.latitude, data.longitude);
              _trackPoints.add(_currentPosition!);
              
              if (_trackPoints.length > 1000) {
                _trackPoints.removeAt(0);
              }
            }
          });
        }
      });

      _bleService.getFileTransferStream()?.listen((response) {
        if (mounted) {
          _handleFileTransferResponse(response);
        }
      });
    }
  }

  void _handleFileTransferResponse(String response) {
    setState(() {
      _lastCommandResponse = "File: $response";
    });

    if (response.startsWith("FILES:")) {
      _parseFileList(response);
    }
  }

  void _parseFileList(String response) {
    try {
      final fileData = response.substring(6);
      final files = fileData.split(';');
      
      List<Map<String, dynamic>> parsedFiles = [];
      
      for (String file in files) {
        if (file.isNotEmpty) {
          final parts = file.split(':');
          if (parts.length >= 2) {
            final filename = parts[0];
            final size = parts[1];
            
            String date = "Unknown";
            if (filename.startsWith("gps_") && filename.contains("_")) {
              try {
                final datePart = filename.substring(4, 12);
                final timePart = filename.substring(13, 19);
                final dateTime = DateTime.parse("${datePart}T$timePart");
                date = "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
              } catch (e) {
                // Keep "Unknown" if parsing fails
              }
            }
            
            parsedFiles.add({
              "name": filename,
              "size": "${(int.tryParse(size) ?? 0) ~/ 1024} KB",
              "packets": "Unknown",
              "duration": "Unknown", 
              "date": date,
            });
          }
        }
      }
      
      setState(() {
        _sessionFiles = parsedFiles;
        _isLoadingSessions = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoadingSessions = false;
      });
    }
  }

  Future<void> _sendCommand(String command) async {
    await _bleService.sendCommand(command);
    if (mounted) {
      setState(() {
        _lastCommandResponse = "Sent: $command";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("📝 Sent: $command"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _toggleLogging() async {
    if (_isLogging) {
      await _sendCommand("STOP_LOG");
      setState(() {
        _isLogging = false;
      });
    } else {
      await _sendCommand("START_LOG");
      setState(() {
        _isLogging = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('🛰️ GPS Logger'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to GPS logger...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🛰️ GPS Logger'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isLogging ? Icons.stop : Icons.play_arrow),
            onPressed: _toggleLogging,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.speed), text: 'G-Force'),
            Tab(icon: Icon(Icons.map), text: 'Map'),
            Tab(icon: Icon(Icons.dashboard), text: 'Data'),
            Tab(icon: Icon(Icons.folder), text: 'Sessions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // G-Force Tab
          GForceMeter(
            accelX: _currentData!.accelX,
            accelY: _currentData!.accelY,
            accelZ: _currentData!.accelZ,
            totalAccel: _currentData!.totalAccel,
            speed: _currentData!.speed,
            isRecording: _isLogging,
            onRecordingToggle: _toggleLogging,
          ),
          // Map Tab
          MapView(
            currentPosition: _currentPosition,
            trackPoints: _trackPoints,
            telemetryData: _currentData!,
          ),
          // Data Tab
          DataView(
            telemetryData: _currentData!,
            packetCount: _packetCount,
            trackPointsCount: _trackPoints.length,
            isLogging: _isLogging,
          ),
          // Sessions Tab
          SessionsView(
            sessionFiles: _sessionFiles,
            isLoadingSessions: _isLoadingSessions,
            lastCommandResponse: _lastCommandResponse,
            isLogging: _isLogging,
            onSendCommand: _sendCommand,
            onRefreshFiles: () {
              _bleService.sendFileCommand("LIST");
              setState(() {
                _isLoadingSessions = true;
              });
            },
            onDownloadFile: (filename) async {
              await _bleService.sendFileCommand("GET:$filename");
            },
            onDeleteFile: (filename) async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete File'),
                  content: Text('Are you sure you want to delete "$filename"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await _bleService.sendFileCommand("DEL:$filename");
                setState(() {
                  _sessionFiles.removeWhere((file) => file["name"] == filename);
                });
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleLogging,
        icon: Icon(_isLogging ? Icons.stop : Icons.play_arrow),
        label: Text(_isLogging ? "Stop Logging" : "Start Logging"),
        backgroundColor: _isLogging ? Colors.red : Colors.green,
      ),
    );
  }
}