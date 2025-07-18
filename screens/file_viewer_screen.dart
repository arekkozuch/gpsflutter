// screens/file_viewer_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/telemetry_data.dart';
import '../services/file_download_service.dart';

class FileViewerScreen extends StatefulWidget {
  final String filename;
  final String filePath;

  const FileViewerScreen({
    super.key,
    required this.filename,
    required this.filePath,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen>
    with TickerProviderStateMixin {
  List<TelemetryData> _packets = [];
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;
  late MapController _mapController;

  // Session statistics
  SessionStats? _stats;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mapController = MapController();
    _loadFile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final packets = await FileDownloadService().parseGPSLogFile(widget.filePath);
      
      if (packets.isNotEmpty) {
        final stats = _calculateSessionStats(packets);
        
        setState(() {
          _packets = packets;
          _stats = stats;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = "No valid GPS data found in file";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Failed to load file: $e";
        _isLoading = false;
      });
    }
  }

  SessionStats _calculateSessionStats(List<TelemetryData> packets) {
    if (packets.isEmpty) {
      return SessionStats(
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        duration: Duration.zero,
        totalPackets: 0,
        distance: 0.0,
        maxSpeed: 0.0,
        avgSpeed: 0.0,
        maxAcceleration: 0.0,
        avgAcceleration: 0.0,
      );
    }

    final startTime = packets.first.timestamp;
    final endTime = packets.last.timestamp;
    final duration = endTime.difference(startTime);

    double totalDistance = 0.0;
    double maxSpeed = 0.0;
    double totalSpeed = 0.0;
    int speedSamples = 0;
    double maxAccel = 0.0;
    double totalAccel = 0.0;

    const Distance distanceCalc = Distance();

    for (int i = 0; i < packets.length; i++) {
      final packet = packets[i];

      // Speed statistics
      if (packet.speed > maxSpeed) maxSpeed = packet.speed;
      if (packet.speed > 0) {
        totalSpeed += packet.speed;
        speedSamples++;
      }

      // Acceleration statistics
      if (packet.totalAccel > maxAccel) maxAccel = packet.totalAccel;
      totalAccel += packet.totalAccel;

      // Distance calculation
      if (i > 0 && packet.latitude != 0 && packet.longitude != 0) {
        final prevPacket = packets[i - 1];
        if (prevPacket.latitude != 0 && prevPacket.longitude != 0) {
          final distance = distanceCalc.as(
            LengthUnit.Meter,
            LatLng(prevPacket.latitude, prevPacket.longitude),
            LatLng(packet.latitude, packet.longitude),
          );
          totalDistance += distance;
        }
      }
    }

    return SessionStats(
      startTime: startTime,
      endTime: endTime,
      duration: duration,
      totalPackets: packets.length,
      distance: totalDistance,
      maxSpeed: maxSpeed,
      avgSpeed: speedSamples > 0 ? totalSpeed / speedSamples : 0.0,
      maxAcceleration: maxAccel,
      avgAcceleration: packets.isNotEmpty ? totalAccel / packets.length : 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📁 ${widget.filename}'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        bottom: _isLoading || _error != null
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(icon: Icon(Icons.map), text: 'Track'),
                  Tab(icon: Icon(Icons.analytics), text: 'Stats'),
                  Tab(icon: Icon(Icons.list), text: 'Data'),
                ],
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading GPS data...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadFile();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildMapView(),
        _buildStatsView(),
        _buildDataView(),
      ],
    );
  }

  Widget _buildMapView() {
    final trackPoints = _packets
        .where((p) => p.latitude != 0 && p.longitude != 0)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    if (trackPoints.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No GPS track data found'),
          ],
        ),
      );
    }

    final bounds = _calculateBounds(trackPoints);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(20)),
            minZoom: 3.0,
            maxZoom: 19.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.gps_logger',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: trackPoints,
                  strokeWidth: 4.0,
                  color: Colors.blue,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                // Start marker
                Marker(
                  point: trackPoints.first,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                  ),
                ),
                // End marker
                Marker(
                  point: trackPoints.last,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.stop, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
        // Track info overlay
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Track Overview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Distance: ${(_stats!.distance / 1000).toStringAsFixed(2)} km'),
                      Text('Duration: ${_formatDuration(_stats!.duration)}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Max Speed: ${_stats!.maxSpeed.toStringAsFixed(1)} km/h'),
                      Text('Points: ${trackPoints.length}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsView() {
    if (_stats == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Session Overview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('Session Overview', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStatRow('Start Time', _formatDateTime(_stats!.startTime)),
                  _buildStatRow('End Time', _formatDateTime(_stats!.endTime)),
                  _buildStatRow('Duration', _formatDuration(_stats!.duration)),
                  _buildStatRow('Total Packets', '${_stats!.totalPackets}'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Movement Statistics
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('Movement', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStatRow('Distance', '${(_stats!.distance / 1000).toStringAsFixed(2)} km'),
                  _buildStatRow('Max Speed', '${_stats!.maxSpeed.toStringAsFixed(1)} km/h'),
                  _buildStatRow('Avg Speed', '${_stats!.avgSpeed.toStringAsFixed(1)} km/h'),
                  _buildStatRow('Max G-Force', '${_stats!.maxAcceleration.toStringAsFixed(3)}g'),
                  _buildStatRow('Avg G-Force', '${_stats!.avgAcceleration.toStringAsFixed(3)}g'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _packets.length,
      itemBuilder: (context, index) {
        final packet = _packets[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getFixColor(packet.fixType),
              child: Text('${packet.fixType}', style: const TextStyle(color: Colors.white)),
            ),
            title: Text(
              '${packet.timestamp.toLocal().toString().substring(11, 19)} - ${packet.speed.toStringAsFixed(1)} km/h',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GPS: ${packet.latitude.toStringAsFixed(6)}, ${packet.longitude.toStringAsFixed(6)}'),
                Text('G-Force: ${packet.totalAccel.toStringAsFixed(3)}g, Sats: ${packet.satellites}'),
              ],
            ),
            trailing: Icon(
              _getMotionIcon(packet.motionClass),
              color: _getMotionColor(packet.motionClass),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        const LatLng(0, 0),
        const LatLng(0, 0),
      );
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  Color _getFixColor(int fixType) {
    switch (fixType) {
      case 0: return Colors.red;
      case 1: return Colors.orange;
      case 2: return Colors.yellow;
      case 3: return Colors.green;
      case 4: return Colors.blue;
      case 5: return Colors.purple;
      default: return Colors.grey;
    }
  }

  IconData _getMotionIcon(String motionClass) {
    if (motionClass.contains('Stationary')) return Icons.stop;
    if (motionClass.contains('Walking')) return Icons.directions_walk;
    if (motionClass.contains('Running')) return Icons.directions_run;
    if (motionClass.contains('Vehicle')) return Icons.directions_car;
    if (motionClass.contains('Impact')) return Icons.warning;
    return Icons.help;
  }

  Color _getMotionColor(String motionClass) {
    if (motionClass.contains('Stationary')) return Colors.grey;
    if (motionClass.contains('Walking')) return Colors.green;
    if (motionClass.contains('Running')) return Colors.orange;
    if (motionClass.contains('Vehicle')) return Colors.blue;
    if (motionClass.contains('Impact')) return Colors.red;
    return Colors.grey;
  }

  String _formatDateTime(DateTime dateTime) {
    return dateTime.toLocal().toString().substring(0, 19);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

// Session statistics model
class SessionStats {
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final int totalPackets;
  final double distance; // meters
  final double maxSpeed; // km/h
  final double avgSpeed; // km/h
  final double maxAcceleration; // g
  final double avgAcceleration; // g

  SessionStats({
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.totalPackets,
    required this.distance,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.maxAcceleration,
    required this.avgAcceleration,
  });
}