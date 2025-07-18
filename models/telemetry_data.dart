class TelemetryData {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double heading;
  final int fixType;
  final String fixTypeString;
  final int satellites;
  final double batteryVoltage;
  final int batteryPercent;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double totalAccel;
  final String motionClass;
  final double gyroX;
  final double gyroY;
  final String receivedCRC;
  final int? intervalMs;
  final int packetCount;
  final bool hasIMU;

  TelemetryData({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.fixType,
    required this.fixTypeString,
    required this.satellites,
    required this.batteryVoltage,
    required this.batteryPercent,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.totalAccel,
    required this.motionClass,
    required this.gyroX,
    required this.gyroY,
    required this.receivedCRC,
    this.intervalMs,
    required this.packetCount,
    required this.hasIMU,
  });

  factory TelemetryData.fromMap(Map<String, dynamic> map) {
    return TelemetryData(
      timestamp: DateTime.parse(map['timestamp']),
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      altitude: map['altitude']?.toDouble() ?? 0.0,
      speed: map['speed']?.toDouble() ?? 0.0,
      heading: map['heading']?.toDouble() ?? 0.0,
      fixType: map['fixType'] ?? 0,
      fixTypeString: map['fixTypeString'] ?? 'No Fix',
      satellites: map['satellites'] ?? 0,
      batteryVoltage: map['batteryVoltage']?.toDouble() ?? 0.0,
      batteryPercent: map['batteryPercent'] ?? 0,
      accelX: map['accelX']?.toDouble() ?? 0.0,
      accelY: map['accelY']?.toDouble() ?? 0.0,
      accelZ: map['accelZ']?.toDouble() ?? 0.0,
      totalAccel: map['totalAccel']?.toDouble() ?? 0.0,
      motionClass: map['motionClass'] ?? 'Unknown',
      gyroX: map['gyroX']?.toDouble() ?? 0.0,
      gyroY: map['gyroY']?.toDouble() ?? 0.0,
      receivedCRC: map['receivedCRC'] ?? '',
      intervalMs: map['intervalMs'],
      packetCount: map['packetCount'] ?? 0,
      hasIMU: map['hasIMU'] ?? false,
    );
  }
}