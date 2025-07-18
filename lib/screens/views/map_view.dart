// screens/views/map_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/telemetry_data.dart';

class MapView extends StatefulWidget {
  final LatLng? currentPosition;
  final List<LatLng> trackPoints;
  final TelemetryData telemetryData;

  const MapView({
    super.key,
    required this.currentPosition,
    required this.trackPoints,
    required this.telemetryData,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late MapController _mapController;
  bool _mapInitialized = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentPosition == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Waiting for GPS fix...'),
            SizedBox(height: 8),
            Text('Move to open area with sky view'),
          ],
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.currentPosition!,
            initialZoom: 16.0,
            minZoom: 3.0,
            maxZoom: 19.0,
            onMapReady: () {
              setState(() {
                _mapInitialized = true;
              });
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.gps_logger',
              maxZoom: 19,
            ),
            
            if (widget.trackPoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.trackPoints,
                    strokeWidth: 4.0,
                    color: Colors.blue.withValues(alpha: 0.8),
                  ),
                ],
              ),
            
            MarkerLayer(
              markers: [
                Marker(
                  point: widget.currentPosition!,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        
        // Info overlay
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.telemetryData.speed.toStringAsFixed(1)} km/h',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${widget.telemetryData.satellites} sats',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  widget.telemetryData.motionClass,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Center on location button
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            onPressed: () {
              if (_mapInitialized && widget.currentPosition != null) {
                _mapController.move(widget.currentPosition!, 16.0);
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}