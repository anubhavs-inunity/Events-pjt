import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../widgets/custom_loader.dart';
import 'login_selection_page.dart';
import 'student_dashboard_page.dart';

class StudentLoginPage extends StatefulWidget {
  const StudentLoginPage({super.key});

  @override
  State<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends State<StudentLoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _studentNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FocusNode _studentIdFocus = FocusNode();
  final FocusNode _studentNameFocus = FocusNode();
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final studentId = _studentIdController.text.trim().toUpperCase();
      final studentName = _studentNameController.text.trim();

      try {
        final response = await http.post(
          Uri.parse(ApiConfig.studentLogin),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'student_id': studentId,
            'student_name': studentName,
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            final studentData = data['student'];
            final studentNameFromApi = studentData['student_name'] ?? studentName;
            
            // Success - navigate to dashboard
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => StudentDashboardPage(
                    studentId: studentId,
                    studentName: studentNameFromApi,
                  ),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(data['error'] ?? 'Login failed'),
                  backgroundColor: const Color(0xFFF44336),
                ),
              );
            }
          }
        } else {
          final data = json.decode(response.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['error'] ?? 'Login failed'),
                backgroundColor: const Color(0xFFF44336),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection error. Please check your network.'),
              backgroundColor: Color(0xFFF44336),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();

    // Enter key navigation
    _studentIdFocus.addListener(() {
      if (!_studentIdFocus.hasFocus && _studentIdController.text.isNotEmpty) {
        _studentNameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _studentNameController.dispose();
    _studentIdFocus.dispose();
    _studentNameFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              Colors.purple[900]!,
              Colors.pink[900]!,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      // Back Button
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.purple.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  const LoginSelectionPage(),
                              transitionsBuilder:
                                  (context, animation, secondaryAnimation, child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(-1.0, 0.0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 40),

                      // Animated Icon
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1500),
                        curve: Curves.elasticOut,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.purple[400]!,
                                    Colors.pink[600]!,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.purple.withOpacity(0.6),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.school,
                                size: 50,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 40),

                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            Colors.purple[300]!,
                            Colors.pink[300]!,
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'Student Login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 50),

                      // Student ID Field with Futuristic Design
                      _FuturisticTextField(
                        controller: _studentIdController,
                        focusNode: _studentIdFocus,
                        label: 'Student ID',
                        hint: 'e.g., ST001',
                        icon: Icons.badge,
                        textCapitalization: TextCapitalization.characters,
                        onFieldSubmitted: (_) {
                          _studentNameFocus.requestFocus();
                        },
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your Student ID';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Student Name Field with Futuristic Design
                      _FuturisticTextField(
                        controller: _studentNameController,
                        focusNode: _studentNameFocus,
                        label: 'Student Name',
                        hint: 'Enter your full name',
                        icon: Icons.person,
                        textCapitalization: TextCapitalization.words,
                        onFieldSubmitted: (_) {
                          if (_formKey.currentState!.validate()) {
                            _handleLogin();
                          }
                        },
                        textInputAction: TextInputAction.done,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 40),

                      // Login Button
                      _FuturisticLoginButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        isLoading: _isLoading,
                        text: 'Login',
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple[400]!,
                            Colors.pink[600]!,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FuturisticTextField extends StatefulWidget {
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

  const _FuturisticTextField({
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
  });

  @override
  State<_FuturisticTextField> createState() => _FuturisticTextFieldState();
}

class _FuturisticTextFieldState extends State<_FuturisticTextField>
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
                      color: Colors.purple.withOpacity(0.3 + _glowController.value * 0.2),
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
                color: _isFocused ? Colors.purple[300] : Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
              prefixIcon: Icon(
                widget.icon,
                color: _isFocused ? Colors.purple[300] : Colors.white.withOpacity(0.7),
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
                  color: Colors.purple[400]!,
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

class _FuturisticLoginButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String text;
  final Gradient gradient;

  const _FuturisticLoginButton({
    required this.onPressed,
    required this.isLoading,
    required this.text,
    required this.gradient,
  });

  @override
  State<_FuturisticLoginButton> createState() => _FuturisticLoginButtonState();
}

class _FuturisticLoginButtonState extends State<_FuturisticLoginButton>
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

