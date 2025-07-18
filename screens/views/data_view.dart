import 'package:flutter/material.dart';
import '../../models/telemetry_data.dart';

class DataView extends StatelessWidget {
  final TelemetryData telemetryData;
  final int packetCount;
  final int trackPointsCount;
  final bool isLogging;

  const DataView({
    super.key,
    required this.telemetryData,
    required this.packetCount,
    required this.trackPointsCount,
    required this.isLogging,
  });

  @override
  Widget build(BuildContext context) {
    Color fixColor = telemetryData.fixType >= 3 ? Colors.green : Colors.red;
    Color satColor = telemetryData.satellites >= 4 ? Colors.green : Colors.orange;
    Color battColor = telemetryData.batteryPercent >= 30 ? Colors.green : Colors.red;

    return RefreshIndicator(
      onRefresh: () async {
        // Refresh logic can be implemented here
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    context,
                    "Fix Type", 
                    telemetryData.fixTypeString, 
                    valueColor: fixColor, 
                    icon: Icons.gps_fixed
                  ),
                ),
                Expanded(
                  child: _buildInfoCard(
                    context,
                    "Satellites", 
                    "${telemetryData.satellites}", 
                    valueColor: satColor, 
                    icon: Icons.satellite_alt
                  ),
                ),
                Expanded(
                  child: _buildInfoCard(
                    context,
                    "Battery", 
                    "${telemetryData.batteryPercent}%", 
                    valueColor: battColor, 
                    icon: Icons.battery_std
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    context,
                    "Speed", 
                    "${telemetryData.speed.toStringAsFixed(1)} km/h", 
                    valueColor: Colors.blue, 
                    icon: Icons.speed
                  ),
                ),
                Expanded(
                  child: _buildInfoCard(
                    context,
                    "Altitude", 
                    "${telemetryData.altitude.toStringAsFixed(1)} m", 
                    valueColor: Colors.green, 
                    icon: Icons.terrain
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 8),
                        Text("Location", style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDataRow("Lat", "${telemetryData.latitude.toStringAsFixed(7)}°"),
                    _buildDataRow("Lon", "${telemetryData.longitude.toStringAsFixed(7)}°"),
                    _buildDataRow("Heading", "${telemetryData.heading.toStringAsFixed(1)}°"),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // IMU Data Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.compass_calibration, color: Colors.purple),
                        const SizedBox(width: 8),
                        Text("Motion", style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDataRow("Motion Class", telemetryData.motionClass),
                    _buildDataRow("Total Accel", "${telemetryData.totalAccel.toStringAsFixed(3)}g"),
                    _buildDataRow("Accel X", "${telemetryData.accelX.toStringAsFixed(3)}g"),
                    _buildDataRow("Accel Y", "${telemetryData.accelY.toStringAsFixed(3)}g"),
                    _buildDataRow("Accel Z", "${telemetryData.accelZ.toStringAsFixed(3)}g"),
                    _buildDataRow("Gyro X", "${telemetryData.gyroX.toStringAsFixed(1)}°/s"),
                    _buildDataRow("Gyro Y", "${telemetryData.gyroY.toStringAsFixed(1)}°/s"),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text("Technical Info", style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDataRow("Timestamp", telemetryData.timestamp.toString()),
                    _buildDataRow("Battery Voltage", "${telemetryData.batteryVoltage.toStringAsFixed(2)} V"),
                    _buildDataRow("Packet Interval", "${telemetryData.intervalMs ?? '—'} ms"),
                    _buildDataRow("Total Packets", "$packetCount"),
                    _buildDataRow("Track Points", "$trackPointsCount"),
                    _buildDataRow("Packet Type", "Enhanced (38 bytes)"),
                    _buildDataRow("CRC", telemetryData.receivedCRC),
                    _buildDataRow("Logging Status", isLogging ? "🔴 Recording" : "⚪ Stopped"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, String value, 
      {Color? valueColor, IconData? icon}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 24, color: valueColor ?? Colors.grey),
              const SizedBox(height: 8),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
