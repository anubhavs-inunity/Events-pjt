import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Custom loader widget that replicates the CSS animation
/// A bouncing square with rotation and shadow effect
class CustomLoader extends StatefulWidget {
  final double size;
  final Color color;
  final Color shadowColor;

  const CustomLoader({
    super.key,
    this.size = 48.0,
    this.color = const Color(0xFFF08080),
    this.shadowColor = const Color(0x80F08080), // 50% opacity
  });

  @override
  State<CustomLoader> createState() => _CustomLoaderState();
}

class _CustomLoaderState extends State<CustomLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bounceAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _shadowScaleAnimation;
  late Animation<double> _scaleYAnimation;
  late Animation<double> _borderRadiusAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat();

    // Bounce animation: moves from 0 to 18px and back
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 9.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 9.0, end: 18.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 18.0, end: 9.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 9.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
    ]).animate(_controller);

    // Rotation animation: 0 to 90 degrees
    _rotationAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 22.5)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 22.5, end: 45.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 45.0, end: 67.5)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 67.5, end: 90.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
    ]).animate(_controller);

    // Shadow scale animation: 1.0 to 1.2 and back
    _shadowScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
    ]).animate(_controller);

    // Scale Y animation: 1.0 to 0.9 when at bottom (50% of animation)
    _scaleYAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.9)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 25.0,
      ),
    ]).animate(_controller);

    // Border radius animation: 4px to 40px at bottom
    _borderRadiusAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween(3.0),
        weight: 15.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween(3.0),
        weight: 10.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 3.0, end: 40.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 40.0, end: 3.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween(3.0),
        weight: 25.0,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final shadowHeight = 5.0 * (size / 48.0); // Proportional shadow height
    final shadowOffset = 12.0 * (size / 48.0); // Proportional shadow offset

    return SizedBox(
      width: size,
      height: size + shadowOffset + shadowHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Shadow (positioned at bottom)
          Positioned(
            top: size + shadowOffset,
            child: AnimatedBuilder(
              animation: _shadowScaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scaleX: _shadowScaleAnimation.value,
                  scaleY: 1.0,
                  child: Container(
                    width: size,
                    height: shadowHeight,
                    decoration: BoxDecoration(
                      color: widget.shadowColor,
                      borderRadius: BorderRadius.circular(shadowHeight / 2),
                    ),
                  ),
                );
              },
            ),
          ),
          // Bouncing square
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _bounceAnimation.value * (size / 48.0)),
                child: Transform.rotate(
                  angle: _rotationAnimation.value * (math.pi / 180),
                  child: Transform.scale(
                    scaleY: _scaleYAnimation.value,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(
                            _borderRadiusAnimation.value * (size / 48.0),
                          ),
                          topLeft: Radius.circular(4.0 * (size / 48.0)),
                          topRight: Radius.circular(4.0 * (size / 48.0)),
                          bottomLeft: Radius.circular(4.0 * (size / 48.0)),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Small loader variant for buttons (20x20)
class CustomLoaderSmall extends StatelessWidget {
  final Color color;

  const CustomLoaderSmall({
    super.key,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomLoader(
        size: 20,
        color: color,
        shadowColor: color.withOpacity(0.3),
      ),
    );
  }
}


