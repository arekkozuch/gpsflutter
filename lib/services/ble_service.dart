// services/ble_service.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_data.dart';
import '../utils/constants.dart';
import 'file_download_service.dart';

class BLEService {
  BluetoothDevice? device;
  BluetoothCharacteristic? telemetryChar;
  BluetoothCharacteristic? configChar;
  BluetoothCharacteristic? fileTransferChar;

  // File transfer state
  String? _currentDownloadFile;
  List<int> _downloadBuffer = [];
  int _expectedFileSize = 0;

  Future<bool> connectToDevice(BluetoothDevice bluetoothDevice) async {
    try {
      device = bluetoothDevice;
      await device!.connect(timeout: const Duration(seconds: 10));
      return await _discoverCharacteristics();
    } catch (e) {
      debugPrint("❌ Connection failed: $e");
      return false;
    }
  }

  Future<bool> _discoverCharacteristics() async {
    try {
      List<BluetoothService> services = await device!.discoverServices();

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == BLEConstants.telemetryServiceUUID) {
          for (var char in service.characteristics) {
            String charUuid = char.uuid.toString().toLowerCase();
            
            if (charUuid == BLEConstants.telemetryCharUUID) {
              telemetryChar = char;
              await char.setNotifyValue(true);
              debugPrint("✅ Telemetry characteristic connected");
            } else if (charUuid == BLEConstants.configCharUUID) {
              configChar = char;
              debugPrint("✅ Config characteristic connected");
            } else if (charUuid == BLEConstants.fileTransferCharUUID) {
              fileTransferChar = char;
              await char.setNotifyValue(true);
              debugPrint("✅ File transfer characteristic connected");
            }
          }
        }
      }
      return telemetryChar != null;
    } catch (e) {
      debugPrint("❌ Service discovery failed: $e");
      return false;
    }
  }

  Stream<TelemetryData>? getTelemetryStream() {
    return telemetryChar?.lastValueStream
        .map((data) => _parseGPSPacket(data))
        .where((data) => data != null)
        .cast<TelemetryData>();
  }

  Stream<String>? getFileTransferStream() {
    return fileTransferChar?.lastValueStream
        .map((data) => _handleFileTransferData(data))
        .where((data) => data.isNotEmpty);
  }

  String _handleFileTransferData(List<int> data) {
    final response = String.fromCharCodes(data);
    debugPrint("📁 File transfer data: $response");

    try {
      if (response.startsWith("START:")) {
        // Parse: "START:filename:filesize"
        final parts = response.split(':');
        if (parts.length >= 3) {
          _currentDownloadFile = parts[1];
          _expectedFileSize = int.tryParse(parts[2]) ?? 0;
          _downloadBuffer.clear();
          
          debugPrint("📥 Starting download: $_currentDownloadFile ($_expectedFileSize bytes)");
          
          // Initialize download tracking
          FileDownloadService().startDownload(_currentDownloadFile!, _expectedFileSize);
        }
        return response;
      } 
      else if (response.startsWith("CHUNK:") && _currentDownloadFile != null) {
        // Parse hex chunk data: "CHUNK:414243..." 
        final hexData = response.substring(6); // Remove "CHUNK:"
        
        // Convert hex string to bytes
        final chunkBytes = <int>[];
        for (int i = 0; i < hexData.length; i += 2) {
          if (i + 1 < hexData.length) {
            final hexByte = hexData.substring(i, i + 2);
            final byte = int.tryParse(hexByte, radix: 16);
            if (byte != null) {
              chunkBytes.add(byte);
            }
          }
        }
        
        // Add to download buffer
        _downloadBuffer.addAll(chunkBytes);
        
        // Update progress
        FileDownloadService().updateProgress(_currentDownloadFile!, _downloadBuffer.length);
        
        debugPrint("📦 Chunk received: ${chunkBytes.length} bytes (${_downloadBuffer.length}/$_expectedFileSize)");
        
        return "PROGRESS:${_downloadBuffer.length}/$_expectedFileSize";
      }
      else if (response.startsWith("COMPLETE:") && _currentDownloadFile != null) {
        debugPrint("✅ Download complete: $_currentDownloadFile (${_downloadBuffer.length} bytes)");
        
        // Save file
        final fileData = Uint8List.fromList(_downloadBuffer);
        FileDownloadService().completeDownload(_currentDownloadFile!, fileData);
        
        final filename = _currentDownloadFile!;
        _currentDownloadFile = null;
        _downloadBuffer.clear();
        _expectedFileSize = 0;
        
        return "COMPLETED:$filename";
      }
      else if (response.startsWith("ERROR:")) {
        if (_currentDownloadFile != null) {
          FileDownloadService().cancelDownload(_currentDownloadFile!);
          _currentDownloadFile = null;
          _downloadBuffer.clear();
        }
        return response;
      }
      
      return response;
    } catch (e) {
      debugPrint("❌ File transfer error: $e");
      if (_currentDownloadFile != null) {
        FileDownloadService().cancelDownload(_currentDownloadFile!);
        _currentDownloadFile = null;
        _downloadBuffer.clear();
      }
      return "ERROR:$e";
    }
  }

  TelemetryData? _parseGPSPacket(List<int> rawData) {
    // Validate packet length
    if (rawData.length != 40) {
      debugPrint("❌ Invalid packet length: ${rawData.length} (expected 40)");
      return null;
    }

    try {
      // Convert to Uint8List for proper byte manipulation
      final bytes = Uint8List.fromList(rawData);
      final data = ByteData.sublistView(bytes);

      // Parse packet according to ESP32 GPSPacket struct
      // All values are little-endian
      
      // Offset 0-3: timestamp (uint32_t) - Unix epoch seconds
      final timestamp = data.getUint32(0, Endian.little);
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
      
      // Offset 4-7: latitude (int32_t) - degrees * 1e7
      final latitudeRaw = data.getInt32(4, Endian.little);
      final latitude = latitudeRaw / 1e7;
      
      // Offset 8-11: longitude (int32_t) - degrees * 1e7
      final longitudeRaw = data.getInt32(8, Endian.little);
      final longitude = longitudeRaw / 1e7;
      
      // Offset 12-15: altitude (int32_t) - millimeters
      final altitudeRaw = data.getInt32(12, Endian.little);
      final altitude = altitudeRaw / 1000.0; // Convert mm to meters
      
      // Offset 16-17: speed (uint16_t) - mm/s
      final speedRaw = data.getUint16(16, Endian.little);
      final speed = speedRaw / 1000.0 * 3.6; // Convert mm/s to km/h
      
      // Offset 18-21: heading (uint32_t) - degrees * 1e5
      final headingRaw = data.getUint32(18, Endian.little);
      final heading = headingRaw / 1e5; // Convert to degrees
      
      // Offset 22: fixType (uint8_t)
      final fixType = data.getUint8(22);
      
      // Offset 23: satellites (uint8_t)
      final satellites = data.getUint8(23);
      
      // Offset 24-25: battery_mv (uint16_t) - millivolts
      final batteryMv = data.getUint16(24, Endian.little);
      final batteryVoltage = batteryMv / 1000.0; // Convert mV to V
      
      // Offset 26: battery_pct (uint8_t) - percentage
      final batteryPercent = data.getUint8(26);
      
      // Offset 27-28: accel_x (int16_t) - milligrams
      final accelXRaw = data.getInt16(27, Endian.little);
      final accelX = accelXRaw / 1000.0; // Convert mg to g
      
      // Offset 29-30: accel_y (int16_t) - milligrams
      final accelYRaw = data.getInt16(29, Endian.little);
      final accelY = accelYRaw / 1000.0; // Convert mg to g
      
      // Offset 31-32: accel_z (int16_t) - milligrams
      final accelZRaw = data.getInt16(31, Endian.little);
      final accelZ = accelZRaw / 1000.0; // Convert mg to g
      
      // Offset 33-34: gyro_x (int16_t) - deg/s * 100
      final gyroXRaw = data.getInt16(33, Endian.little);
      final gyroX = gyroXRaw / 100.0; // Convert to deg/s
      
      // Offset 35-36: gyro_y (int16_t) - deg/s * 100
      final gyroYRaw = data.getInt16(35, Endian.little);
      final gyroY = gyroYRaw / 100.0; // Convert to deg/s
      
      // Offset 37: reserved1 (uint8_t) - padding
      final reserved = data.getUint8(37);
      
      // Offset 38-39: crc (uint16_t) - CRC16
      final crc = data.getUint16(38, Endian.little);
      
      // Calculate derived values
      final totalAccel = math.sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
      final motionClass = _getMotionClass(totalAccel);
      final fixTypeString = _getFixTypeString(fixType);
      
      return TelemetryData(
        timestamp: dateTime,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        speed: speed,
        heading: heading,
        fixType: fixType,
        fixTypeString: fixTypeString,
        satellites: satellites,
        batteryVoltage: batteryVoltage,
        batteryPercent: batteryPercent,
        accelX: accelX,
        accelY: accelY,
        accelZ: accelZ,
        totalAccel: totalAccel,
        motionClass: motionClass,
        gyroX: gyroX,
        gyroY: gyroY,
        receivedCRC: "0x${crc.toRadixString(16).padLeft(4, '0').toUpperCase()}",
        packetCount: 0, // Will be incremented by the calling code
        hasIMU: true,
      );
      
    } catch (e) {
      debugPrint("❌ Packet parsing error: $e");
      return null;
    }
  }

  String _getMotionClass(double totalAccel) {
    if (totalAccel < 0.8) return "🔻 Very Low";
    if (totalAccel < 1.2) return "😴 Stationary";
    if (totalAccel < 1.8) return "🚶 Walking";
    if (totalAccel < 3.0) return "🏃 Running";
    if (totalAccel < 5.0) return "🚗 Vehicle";
    return "💥 High Impact";
  }

  String _getFixTypeString(int fixType) {
    switch (fixType) {
      case 0: return "No Fix";
      case 1: return "Dead Reckoning";
      case 2: return "2D Fix";
      case 3: return "3D Fix";
      case 4: return "GNSS + DR";
      case 5: return "Time Only";
      default: return "Unknown ($fixType)";
    }
  }

  Future<void> sendCommand(String command) async {
    if (configChar != null) {
      try {
        await configChar!.write(command.codeUnits);
        debugPrint("📤 Command sent: $command");
      } catch (e) {
        debugPrint("❌ Failed to send command: $e");
      }
    } else {
      debugPrint("❌ Config characteristic not available");
    }
  }

  Future<void> sendFileCommand(String command) async {
    if (fileTransferChar != null) {
      try {
        await fileTransferChar!.write(command.codeUnits);
        debugPrint("📁 File command sent: $command");
      } catch (e) {
        debugPrint("❌ Failed to send file command: $e");
      }
    } else {
      debugPrint("❌ File transfer characteristic not available");
    }
  }

  bool get isConnected => device?.isConnected ?? false;

  void disconnect() {
    try {
      // Cancel any active downloads
      if (_currentDownloadFile != null) {
        FileDownloadService().cancelDownload(_currentDownloadFile!);
        _currentDownloadFile = null;
        _downloadBuffer.clear();
      }
      
      device?.disconnect();
      debugPrint("📱 Device disconnected");
    } catch (e) {
      debugPrint("❌ Disconnect error: $e");
    }
  }
}