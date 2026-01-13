import 'package:flutter/material.dart';

class FuturisticTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final TextInputAction textInputAction;
  final Color glowColor;

  const FuturisticTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction = TextInputAction.next,
    this.glowColor = Colors.cyan,
  });

  @override
  State<FuturisticTextField> createState() => _FuturisticTextFieldState();
}

class _FuturisticTextFieldState extends State<FuturisticTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    widget.focusNode.addListener(() {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    });
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
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: widget.glowColor.withOpacity(0.3 + _glowController.value * 0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: widget.obscureText,
            textCapitalization: widget.textCapitalization,
            validator: widget.validator,
            onFieldSubmitted: widget.onFieldSubmitted,
            textInputAction: widget.textInputAction,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              labelStyle: TextStyle(
                color: _isFocused ? widget.glowColor : Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
              prefixIcon: Icon(
                widget.icon,
                color: _isFocused ? widget.glowColor : Colors.white.withOpacity(0.7),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: widget.glowColor,
                  width: 2.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Colors.red,
                  width: 1.5,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Colors.red,
                  width: 2.5,
                ),
              ),
              errorStyle: const TextStyle(color: Colors.red),
            ),
          ),
        );
      },
    );
  }
}

