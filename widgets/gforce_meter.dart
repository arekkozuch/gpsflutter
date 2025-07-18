// widgets/gforce_meter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class GForceMeter extends StatefulWidget {
  final double accelX;
  final double accelY;
  final double accelZ;
  final double totalAccel;
  final double speed;
  final bool isRecording;
  final VoidCallback? onRecordingToggle;

  const GForceMeter({
    super.key,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.totalAccel,
    required this.speed,
    required this.isRecording,
    this.onRecordingToggle,
  });

  @override
  State<GForceMeter> createState() => _GForceMeterState();
}

class _GForceMeterState extends State<GForceMeter>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _dotAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _dotAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(GForceMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.totalAccel != oldWidget.totalAccel) {
      _animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade900,
            Colors.black,
            Colors.grey.shade800,
            Colors.black,
          ],
          stops: const [0.0, 0.25, 0.75, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Status Bar
            _buildTopStatusBar(),
            
            // Main G-Force Display
            Expanded(
              child: Center(
                child: _buildGForceMeter(),
              ),
            ),
            
            // Bottom Controls
            _buildBottomControls(),
            
            // Bottom Navigation
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Carrier',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '8:25 PM',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            width: 24,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGForceMeter() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Speed and G-Force Values
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                Text(
                  'km/h',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${widget.speed.round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
            Column(
              children: [
                Text(
                  'g',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 16,
                  ),
                ),
                Text(
                  widget.totalAccel.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ],
        ),
        
        const SizedBox(height: 40),
        
        // Circular G-Force Meter
        SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: GForceMeterPainter(
              accelX: widget.accelX,
              accelY: widget.accelY,
              totalAccel: widget.totalAccel,
              animation: _dotAnimation,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: GestureDetector(
        onTap: widget.onRecordingToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.isRecording ? 'Stop Recording' : 'Start Recording',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.radio_button_checked, 'G-Force', true),
          _buildNavItem(Icons.timeline, 'Plot', false),
          _buildNavItem(Icons.access_time, 'Laptime', false),
          _buildNavItem(Icons.folder, 'Archive', false),
          _buildNavItem(Icons.settings, 'Settings', false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isSelected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: isSelected ? Colors.blue : Colors.white.withOpacity(0.6),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.blue : Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class GForceMeterPainter extends CustomPainter {
  final double accelX;
  final double accelY;
  final double totalAccel;
  final Animation<double> animation;

  GForceMeterPainter({
    required this.accelX,
    required this.accelY,
    required this.totalAccel,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 20;

    // Draw concentric circles (radar rings)
    _drawConcentricCircles(canvas, center, radius);
    
    // Draw crosshairs
    _drawCrosshairs(canvas, center, radius);
    
    // Draw scale markings
    _drawScaleMarkings(canvas, center, radius);
    
    // Draw G-force dot
    _drawGForceDot(canvas, center, radius);
    
    // Draw center G
    _drawCenterLabel(canvas, center);
  }

  void _drawConcentricCircles(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw 4 concentric circles
    for (int i = 1; i <= 4; i++) {
      final radius = (maxRadius / 4) * i;
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawCrosshairs(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
  }

  void _drawScaleMarkings(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw scale numbers on the left
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w300,
    );

    for (int i = 1; i <= 4; i++) {
      final y = center.dy - (radius / 4) * i;
      
      // Draw tick mark
      canvas.drawLine(
        Offset(center.dx - radius - 10, y),
        Offset(center.dx - radius - 5, y),
        paint,
      );

      // Draw scale number
      final textPainter = TextPainter(
        text: TextSpan(text: '+${i * 0.25}', style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - radius - 35, y - textPainter.height / 2),
      );
    }

    // Draw negative scale
    for (int i = 1; i <= 4; i++) {
      final y = center.dy + (radius / 4) * i;
      
      // Draw tick mark
      canvas.drawLine(
        Offset(center.dx - radius - 10, y),
        Offset(center.dx - radius - 5, y),
        paint,
      );

      // Draw scale number
      final textPainter = TextPainter(
        text: TextSpan(text: '-${i * 0.25}', style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - radius - 35, y - textPainter.height / 2),
      );
    }
  }

  void _drawGForceDot(Canvas canvas, Offset center, double radius) {
    // Calculate position based on acceleration
    const maxG = 1.0; // 1G corresponds to outer ring
    
    // Clamp values to reasonable range
    final clampedX = (accelX / maxG).clamp(-1.0, 1.0);
    final clampedY = (-accelY / maxG).clamp(-1.0, 1.0); // Negative Y for correct orientation
    
    final dotPosition = Offset(
      center.dx + clampedX * radius * 0.8,
      center.dy + clampedY * radius * 0.8,
    );

    // Orange dot (main indicator)
    final dotPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    // Draw animated dot with glow effect
    final glowPaint = Paint()
      ..color = Colors.orange.withOpacity(0.3 * animation.value)
      ..style = PaintingStyle.fill;

    // Glow effect
    canvas.drawCircle(dotPosition, 12 * animation.value, glowPaint);
    
    // Main dot
    canvas.drawCircle(dotPosition, 6, dotPaint);

    // White center dot
    final centerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dotPosition, 2, centerDotPaint);
  }

  void _drawCenterLabel(Canvas canvas, Offset center) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 32,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      text: const TextSpan(text: 'G', style: textStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant GForceMeterPainter oldDelegate) {
    return oldDelegate.accelX != accelX ||
           oldDelegate.accelY != accelY ||
           oldDelegate.totalAccel != totalAccel ||
           oldDelegate.animation != animation;
  }
}
