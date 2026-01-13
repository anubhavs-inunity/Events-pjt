import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';

class AnimatedMessageNotification extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback onClose;
  final VoidCallback? onTap;

  const AnimatedMessageNotification({
    super.key,
    required this.title,
    required this.message,
    required this.onClose,
    this.onTap,
  });

  @override
  State<AnimatedMessageNotification> createState() => _AnimatedMessageNotificationState();
}

class _AnimatedMessageNotificationState extends State<AnimatedMessageNotification>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late AnimationController _entranceController;
  late Animation<double> _flipAnimation;
  late Animation<double> _tooltipOpacityAnimation;
  late Animation<Offset> _tooltipSlideAnimation;
  late Animation<double> _entranceScaleAnimation;
  late Animation<Offset> _entranceSlideAnimation;
  late Animation<double> _entranceOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    // Entrance animation controller for letter popup effect - optimized for mobile
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Triangle flip animation (from 150deg to 0deg - opens downward/opposite side)
    _flipAnimation = Tween<double>(begin: 150.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Tooltip (message) opacity animation
    _tooltipOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    // Tooltip slide animation
    _tooltipSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Letter entrance animations - optimized for faster performance
    _entranceScaleAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOut,
      ),
    );

    _entranceSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOut,
      ),
    );

    _entranceOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOut,
      ),
    );

    // Start entrance animation automatically
    _entranceController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_isExpanded) {
      setState(() {
        _isExpanded = true;
      });
      _controller.forward();
      // Don't call onTap - just expand to show message
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back button from dismissing
      child: Material(
        color: Colors.transparent,
      child: Stack(
        children: [
            // Blocking background overlay - always visible and blocks all interaction
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  // Block background taps - user must interact with notification
                },
              child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3), // Reduced blur for better performance
                child: Container(
                    color: Colors.black.withOpacity(0.6),
                ),
              ),
            ),
          ),
          
            // Notification card container with entrance animation - optimized with RepaintBoundary
          Center(
              child: GestureDetector(
                onTap: _isExpanded ? null : _handleTap,
                child: RepaintBoundary(
            child: AnimatedBuilder(
                    animation: Listenable.merge([_controller, _entranceController]),
              builder: (context, child) {
                      return SlideTransition(
                        position: _entranceSlideAnimation,
                        child: FadeTransition(
                          opacity: _entranceOpacityAnimation,
                          child: ScaleTransition(
                            scale: _entranceScaleAnimation,
                            child: _buildCard(),
                          ),
                        ),
                      );
              },
                  ),
                ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Message card - appears above when expanded (letter opens)
        if (_isExpanded)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _tooltipSlideAnimation,
              child: Opacity(
                opacity: _tooltipOpacityAnimation.value,
                child: Center(
                child: Container(
                  constraints: const BoxConstraints(
                      minWidth: 110,
                      maxWidth: 300,
                    minHeight: 70,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 40, 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                      color: Colors.white,
                    border: Border.all(color: const Color(0xFFCECCCC), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                        // Lined paper background
                        CustomPaint(
                          painter: LinedPaperPainter(),
                          child: Container(),
                        ),
                        // Content
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF201E1E),
                              letterSpacing: 0.5,
                            ),
                                textAlign: TextAlign.left,
                          ),
                              if (widget.message.isNotEmpty) ...[
                          const SizedBox(height: 8),
                                Text(
                              widget.message,
                              style: const TextStyle(
                                fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                color: Color(0xFF201E1E),
                              ),
                                  textAlign: TextAlign.left,
                            ),
                              ],
                            ],
                          ),
                      ),
                      // Close button
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: widget.onClose,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        
        // Main envelope container (the heart icon card)
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 110,
          height: 70,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isExpanded
                  ? [
                      Colors.white,
                      Colors.white,
                    ]
                  : [
                      const Color(0xFFF2F5F8),
                      const Color(0xFFECF1F2),
                      const Color(0xFFE7ECEB),
                      const Color(0xFFE3E7E4),
                      const Color(0xFFE1E2DE),
                    ],
            ),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.151),
                blurRadius: 10,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main content
              Center(
                child: _isExpanded ? _buildExpandedContent() : _buildCollapsedContent(),
                ),
            ],
          ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedContent() {
    return const Icon(
      Icons.favorite,
            color: Color(0xFF201E1E),
      size: 40,
    );
  }

  Widget _buildExpandedContent() {
    return const SizedBox.shrink(); // Empty when expanded, content is in the tooltip above
  }
}

// Custom clipper for triangle shape
class TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// Custom painter for lined paper effect
class LinedPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFAAAAAA).withOpacity(0.1)
      ..strokeWidth = 1;

    // Draw horizontal lines (lined paper effect)
    for (double y = 20; y < size.height; y += 20) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    // Draw vertical lines (grid effect)
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint..color = const Color(0xFFAAAAAA).withOpacity(0.05),
      );
    }
  }

  @override
  bool shouldRepaint(LinedPaperPainter oldDelegate) => false;
}
