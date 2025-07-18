// services/file_download_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/telemetry_data.dart';

class FileDownloadService {
  static final FileDownloadService _instance = FileDownloadService._internal();
  factory FileDownloadService() => _instance;
  FileDownloadService._internal();

  final Map<String, FileDownloadProgress> _activeDownloads = {};
  
  // Get download progress for a specific file
  FileDownloadProgress? getDownloadProgress(String filename) {
    return _activeDownloads[filename];
  }

  // Start a new download
  void startDownload(String filename, int totalSize) {
    _activeDownloads[filename] = FileDownloadProgress(
      filename: filename,
      totalBytes: totalSize,
      downloadedBytes: 0,
      status: DownloadStatus.downloading,
      startTime: DateTime.now(),
    );
  }

  // Update download progress
  void updateProgress(String filename, int downloadedBytes) {
    final progress = _activeDownloads[filename];
    if (progress != null) {
      _activeDownloads[filename] = progress.copyWith(
        downloadedBytes: downloadedBytes,
        lastUpdateTime: DateTime.now(),
      );
    }
  }

  // Complete download and save file
  Future<String?> completeDownload(String filename, Uint8List data) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/gps_downloads');
      
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final file = File('${downloadsDir.path}/$filename');
      await file.writeAsBytes(data);

      final progress = _activeDownloads[filename];
      if (progress != null) {
        _activeDownloads[filename] = progress.copyWith(
          status: DownloadStatus.completed,
          filePath: file.path,
        );
      }

      debugPrint("✅ File saved: ${file.path}");
      return file.path;
    } catch (e) {
      debugPrint("❌ Failed to save file: $e");
      final progress = _activeDownloads[filename];
      if (progress != null) {
        _activeDownloads[filename] = progress.copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
        );
      }
      return null;
    }
  }

  // Cancel download
  void cancelDownload(String filename) {
    final progress = _activeDownloads[filename];
    if (progress != null) {
      _activeDownloads[filename] = progress.copyWith(
        status: DownloadStatus.cancelled,
      );
    }
  }

  // Clear completed downloads
  void clearCompleted() {
    _activeDownloads.removeWhere((key, value) => 
      value.status == DownloadStatus.completed ||
      value.status == DownloadStatus.failed ||
      value.status == DownloadStatus.cancelled
    );
  }

  // Get all downloaded files
  Future<List<DownloadedFile>> getDownloadedFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/gps_downloads');
      
      if (!await downloadsDir.exists()) {
        return [];
      }

      final files = await downloadsDir.list().toList();
      List<DownloadedFile> downloadedFiles = [];

      for (var fileEntity in files) {
        if (fileEntity is File) {
          final file = File(fileEntity.path);
          final stat = await file.stat();
          final filename = file.path.split('/').last;
          
          downloadedFiles.add(DownloadedFile(
            filename: filename,
            filePath: file.path,
            size: stat.size,
            downloadDate: stat.modified,
          ));
        }
      }

      return downloadedFiles;
    } catch (e) {
      debugPrint("❌ Failed to get downloaded files: $e");
      return [];
    }
  }

  // Parse GPS log file
  Future<List<TelemetryData>> parseGPSLogFile(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      List<TelemetryData> packets = [];
      const packetSize = 40;
      
      // Skip file header if present
      int offset = 0;
      if (bytes.length > 13) {
        final header = String.fromCharCodes(bytes.sublist(0, 13));
        if (header == "GPS_LOG_V1.0\n") {
          offset = 13;
        }
      }

      // Parse packets
      while (offset + packetSize <= bytes.length) {
        final packetBytes = bytes.sublist(offset, offset + packetSize);
        final packet = _parseGPSPacket(packetBytes);
        if (packet != null) {
          packets.add(packet);
        }
        offset += packetSize;
      }

      debugPrint("✅ Parsed ${packets.length} packets from $filePath");
      return packets;
    } catch (e) {
      debugPrint("❌ Failed to parse GPS log: $e");
      return [];
    }
  }

  // Parse individual GPS packet (similar to BLE service)
  TelemetryData? _parseGPSPacket(List<int> rawData) {
    if (rawData.length != 40) return null;

    try {
      final bytes = Uint8List.fromList(rawData);
      final data = ByteData.sublistView(bytes);

      final timestamp = data.getUint32(0, Endian.little);
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
      
      final latitude = data.getInt32(4, Endian.little) / 1e7;
      final longitude = data.getInt32(8, Endian.little) / 1e7;
      final altitude = data.getInt32(12, Endian.little) / 1000.0;
      final speed = data.getUint16(16, Endian.little) / 1000.0 * 3.6;
      final heading = data.getUint32(18, Endian.little) / 1e5;
      
      final fixType = data.getUint8(22);
      final satellites = data.getUint8(23);
      final batteryVoltage = data.getUint16(24, Endian.little) / 1000.0;
      final batteryPercent = data.getUint8(26);
      
      final accelX = data.getInt16(27, Endian.little) / 1000.0;
      final accelY = data.getInt16(29, Endian.little) / 1000.0;
      final accelZ = data.getInt16(31, Endian.little) / 1000.0;
      final gyroX = data.getInt16(33, Endian.little) / 100.0;
      final gyroY = data.getInt16(35, Endian.little) / 100.0;
      
      final crc = data.getUint16(38, Endian.little);
      
      final totalAccel = math.sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
      
      return TelemetryData(
        timestamp: dateTime,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        speed: speed,
        heading: heading,
        fixType: fixType,
        fixTypeString: _getFixTypeString(fixType),
        satellites: satellites,
        batteryVoltage: batteryVoltage,
        batteryPercent: batteryPercent,
        accelX: accelX,
        accelY: accelY,
        accelZ: accelZ,
        totalAccel: totalAccel,
        motionClass: _getMotionClass(totalAccel),
        gyroX: gyroX,
        gyroY: gyroY,
        receivedCRC: "0x${crc.toRadixString(16).padLeft(4, '0').toUpperCase()}",
        packetCount: 0,
        hasIMU: true,
      );
    } catch (e) {
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
}

// Data models for file downloads
enum DownloadStatus { downloading, completed, failed, cancelled }

class FileDownloadProgress {
  final String filename;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final DateTime startTime;
  final DateTime? lastUpdateTime;
  final String? filePath;
  final String? error;

  FileDownloadProgress({
    required this.filename,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.status,
    required this.startTime,
    this.lastUpdateTime,
    this.filePath,
    this.error,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  Duration get elapsedTime => (lastUpdateTime ?? DateTime.now()).difference(startTime);

  double get speedBytesPerSecond {
    final elapsed = elapsedTime.inMilliseconds;
    return elapsed > 0 ? downloadedBytes / (elapsed / 1000.0) : 0.0;
  }

  String get speedFormatted {
    final speed = speedBytesPerSecond;
    if (speed < 1024) return "${speed.toStringAsFixed(0)} B/s";
    if (speed < 1024 * 1024) return "${(speed / 1024).toStringAsFixed(1)} KB/s";
    return "${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  FileDownloadProgress copyWith({
    String? filename,
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    DateTime? startTime,
    DateTime? lastUpdateTime,
    String? filePath,
    String? error,
  }) {
    return FileDownloadProgress(
      filename: filename ?? this.filename,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      filePath: filePath ?? this.filePath,
      error: error ?? this.error,
    );
  }
}

class DownloadedFile {
  final String filename;
  final String filePath;
  final int size;
  final DateTime downloadDate;

  DownloadedFile({
    required this.filename,
    required this.filePath,
    required this.size,
    required this.downloadDate,
  });

  String get sizeFormatted {
    if (size < 1024) return "$size B";
    if (size < 1024 * 1024) return "${(size / 1024).toStringAsFixed(1)} KB";
    return "${(size / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
}