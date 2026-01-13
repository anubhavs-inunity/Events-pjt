import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../widgets/custom_loader.dart';
import '../services/fcm_service.dart';
import 'admin_dashboard_page.dart';
import 'student_dashboard_page.dart';

class UnifiedLoginPage extends StatefulWidget {
  const UnifiedLoginPage({super.key});

  @override
  State<UnifiedLoginPage> createState() => _UnifiedLoginPageState();
}

class _UnifiedLoginPageState extends State<UnifiedLoginPage>
    with SingleTickerProviderStateMixin {
  // State Management
  bool isAdminLogin = true;
  bool rememberMe = false;
  bool showPassword = false;
  bool isLoading = false;

  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController rollNumberController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  // Focus Nodes
  final FocusNode nameFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();
  final FocusNode rollNumberFocus = FocusNode();

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Color Scheme
  static const Color primaryGreen = Color(0xFFC4E76E);
  static const Color inactiveGray = Color(0xFFF3F4F6);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textGray = Color(0xFF6B7280);
  static const Color borderGray = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    nameController.dispose();
    passwordController.dispose();
    rollNumberController.dispose();
    nameFocus.dispose();
    passwordFocus.dispose();
    rollNumberFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _switchTab(bool isAdmin) {
    if (isAdminLogin != isAdmin) {
      HapticFeedback.selectionClick();
      setState(() {
        isAdminLogin = isAdmin;
        formKey.currentState?.reset();
        showPassword = false;
      });
      _animationController.reset();
      _animationController.forward();
    }
  }

  Future<void> _handleLogin() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    HapticFeedback.mediumImpact();

    try {
      if (isAdminLogin) {
        await _handleAdminLogin();
      } else {
        await _handleStudentLogin();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAdminLogin() async {
    final username = nameController.text.trim();
    final password = passwordController.text.trim();

    final response = await http.post(
      Uri.parse(ApiConfig.adminLogin),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'username': username,
        'password': password,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        final adminData = data['admin'] as Map<String, dynamic>?;
        final adminId = adminData?['id'] as String?;
        final adminUsername = adminData?['username'] as String?;
        
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AdminDashboardPage(
                adminId: adminId,
                adminUsername: adminUsername,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error'] ?? 'Invalid credentials'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleStudentLogin() async {
    final studentId = rollNumberController.text.trim().toUpperCase();
    final studentName = nameController.text.trim();

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
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFEFF6FF), // light blue
                Colors.white,
                const Color(0xFFFAF5FF), // light purple
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    // Logo
                    _buildLogo(),
                    const SizedBox(height: 32),
                    // Title
                    _buildTitle(),
                    const SizedBox(height: 8),
                    // Subtitle
                    _buildSubtitle(),
                    const SizedBox(height: 48),
                    // Tab Selection
                    _buildTabSelection(),
                    const SizedBox(height: 32),
                    // Login Form
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: isAdminLogin
                            ? _buildAdminForm()
                            : _buildStudentForm(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Remember Me & Forgot Password (Admin only)
                    if (isAdminLogin) _buildRememberMeRow(),
                    const SizedBox(height: 24),
                    // Login Button
                    _buildLoginButton(),
                    const SizedBox(height: 32),
                    // Footer
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue[400]!,
              Colors.purple[400]!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: const Icon(
          Icons.location_on,
          size: 50,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const Text(
      'Location-Based Attendance System',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textDark,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Secure access to your attendance portal',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        color: textGray,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTabSelection() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: inactiveGray,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              isActive: isAdminLogin,
              icon: Icons.person,
              label: 'Admin Login',
              onTap: () => _switchTab(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTabButton(
              isActive: !isAdminLogin,
              icon: Icons.school,
              label: 'Student Login',
              onTap: () => _switchTab(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required bool isActive,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: primaryGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? textDark : textGray,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isActive ? textDark : textGray,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminForm() {
    return Column(
      key: const ValueKey('admin'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: nameController,
          focusNode: nameFocus,
          label: 'Full Name',
          hint: 'Enter your name',
          icon: Icons.person,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your name';
            }
            if (value.trim().length < 2) {
              return 'Name must be at least 2 characters';
            }
            return null;
          },
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 20),
        _buildPasswordField(),
      ],
    );
  }

  Widget _buildStudentForm() {
    return Column(
      key: const ValueKey('student'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: rollNumberController,
          focusNode: rollNumberFocus,
          label: 'Roll Number',
          hint: 'Enter your roll number',
          icon: Icons.badge,
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your roll number';
            }
            if (!RegExp(r'^[A-Z0-9]+$').hasMatch(value.trim().toUpperCase())) {
              return 'Please enter a valid roll number';
            }
            return null;
          },
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => nameFocus.requestFocus(),
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: nameController,
          focusNode: nameFocus,
          label: 'Full Name',
          hint: 'Enter your name',
          icon: Icons.person,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your name';
            }
            if (value.trim().length < 2) {
              return 'Name must be at least 2 characters';
            }
            return null;
          },
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleLogin(),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.blue[700]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: passwordController,
      focusNode: passwordFocus,
      obscureText: !showPassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _handleLogin(),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter your password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Password',
        hintText: 'Enter your password',
        prefixIcon: Icon(Icons.lock, color: Colors.blue[700]),
        suffixIcon: IconButton(
          icon: Icon(
            showPassword ? Icons.visibility_off : Icons.visibility,
            color: textGray,
          ),
          onPressed: () {
            setState(() {
              showPassword = !showPassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildRememberMeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Checkbox(
              value: rememberMe,
              onChanged: (value) {
                setState(() {
                  rememberMe = value ?? false;
                });
              },
              activeColor: primaryGreen,
            ),
            Text(
              'Remember me',
              style: TextStyle(
                color: textDark,
                fontSize: 14,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Please contact administrator'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          },
          child: Text(
            'Forgot password?',
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: textDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const CustomLoaderSmall(color: Colors.white)
            : Text(
                isAdminLogin ? 'Log In as Admin' : 'Log In as Student',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }


  Widget _buildFooter() {
    return Center(
      child: Text.rich(
        TextSpan(
          text: "Don't have an account? ",
          style: TextStyle(color: textGray, fontSize: 14),
          children: [
            WidgetSpan(
              child: TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please contact administrator'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Sign Up',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

