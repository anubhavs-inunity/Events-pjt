import 'package:flutter/material.dart';
import 'custom_loader.dart';

class FuturisticButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String text;
  final Gradient gradient;

  const FuturisticButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.text,
    required this.gradient,
  });

  @override
  State<FuturisticButton> createState() => _FuturisticButtonState();
}

class _FuturisticButtonState extends State<FuturisticButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return GestureDetector(
          onTapDown: widget.onPressed == null
              ? null
              : (_) => setState(() => _isPressed = true),
          onTapUp: widget.onPressed == null
              ? null
              : (_) {
                  setState(() => _isPressed = false);
                  widget.onPressed?.call();
                },
          onTapCancel: () => setState(() => _isPressed = false),
          child: Transform.scale(
            scale: _isPressed ? 0.95 : 1.0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: widget.gradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (widget.gradient.colors.first as Color)
                        .withOpacity(0.4 + _glowController.value * 0.3),
                    blurRadius: 20 + _glowController.value * 10,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: widget.isLoading
                  ? const Center(
                      child: CustomLoaderSmall(color: Colors.white),
                    )
                  : Center(
                      child: Text(
                        widget.text,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

