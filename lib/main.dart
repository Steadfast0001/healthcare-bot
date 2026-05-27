import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'chat_screen.dart';
import 'emergency_screen.dart';
import 'health_tips_screen.dart';
import 'medication_screen.dart';
import 'symptom_checker_screen.dart';
import 'profile_screen.dart';
import 'responsive.dart';
import 'local_notification_service.dart';
import 'health_tracker_screen.dart';
import 'reports_records_screen.dart';
import 'reminders_alerts_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'flutter.env');
  await LocalNotificationService.initialize();
  runApp(const WadoctaApp());
}

class WadoctaApp extends StatelessWidget {
  const WadoctaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: LocalNotificationService.navigatorKey,
      title: 'Wadocta',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF1F6E4A),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6E4A),
          secondary: const Color(0xFF0066CC),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          clipBehavior: Clip.antiAlias,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        // Improve focus visibility across the app
        focusColor: const Color(0xFF1F6E4A),
        highlightColor: Colors.transparent,
        splashFactory: InkRipple.splashFactory,
      ),
      home: const AuthenticationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Main authentication screen with tab-based switching between login and signup
class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({super.key});

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _prefilledEmail;
  bool _isCheckingSession = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedEmail();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await AuthService.getSavedEmail();
    if (!mounted) return;
    setState(() {
      _prefilledEmail = savedEmail;
    });
  }

  Future<void> _checkExistingSession() async {
    final backendConnected = await AuthService.checkBackendConnection();
    if (!mounted) return;

    if (!backendConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Backend server is not responding. Please ensure the server is running.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
      setState(() => _isCheckingSession = false);
      return;
    }

    try {
      final user = await AuthService.getCurrentUser();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainPage(email: user['email'] ?? '')),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9F5F0), Color(0xFFD4E9FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: context.responsivePagePadding(bottom: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppBreakpoints.formMaxWidth),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tab bar with custom styling and accessibility
                    Semantics(
                      label: 'Authentication tabs',
                      child: TabBar(
                        controller: _tabController,
                        indicator: const UnderlineTabIndicator(
                          borderSide: BorderSide(
                            color: Color(0xFF1F6E4A),
                            width: 3.0,
                          ),
                        ),
                        labelColor: const Color(0xFF1F6E4A),
                        unselectedLabelColor: Colors.grey.shade600,
                        tabs: const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'Create account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: context.isCompact ? 520 : 560,
                        maxHeight: context.isCompact ? 760 : 820,
                      ),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          LoginForm(prefilledEmail: _prefilledEmail),
                          const SignupForm(),
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

/// Login form with email, password, and forgot password functionality
class LoginForm extends StatefulWidget {
  final String? prefilledEmail;

  const LoginForm({super.key, this.prefilledEmail});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _showPassword = false;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledEmail != null) {
      _emailController.text = widget.prefilledEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final response = await AuthService.login(
      identifier: _emailController.text.trim(),
      password: _passwordController.text,
      rememberMe: _rememberMe,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    final authToken = response['token'] ?? response['access_token'];
    if (authToken != null) {
      await AuthService.saveToken(authToken);
      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_email', _emailController.text.trim());
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainPage(email: _emailController.text.trim()),
        ),
      );
      return;
    }

    final message = response['detail'] ?? response['message'] ?? 'Login failed';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController(text: _emailController.text);
    final enteredEmail = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'you@example.com',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final email = emailController.text.trim();
                if (!AuthService.isValidEmail(email)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid email address.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, email);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (enteredEmail == null) return;

    setState(() => _isLoading = true);
    final result = await AuthService.forgotPassword(email: enteredEmail);
    setState(() => _isLoading = false);

    if (!mounted) return;

    final message = result['detail'] ??
        result['message'] ??
        'Check your email for reset instructions';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Automatically navigate to the reset screen if successful
    if (!result.containsKey('detail') || message.toLowerCase().contains('sent')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PasswordResetScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.all(context.isCompact ? 20.0 : 32.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Welcome back',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to your account',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Email input field
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (!AuthService.isValidEmail(value ?? '')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
              onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
            ),
            const SizedBox(height: 16),

            // Password input field
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                    semanticLabel: _showPassword ? 'Hide password' : 'Show password',
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  splashRadius: 24,
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
              onFieldSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember me'),
              value: _rememberMe,
              activeColor: const Color(0xFF1F6E4A),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) {
                if (value != null) setState(() => _rememberMe = value);
              },
            ),
            const SizedBox(height: 8),

            // Forgot password link
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _handleForgotPassword,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(color: Color(0xFF0066CC), fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),

            const SizedBox(height: 24),

            // Success message display
            if (_successMessage != null)
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F6E4A).withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1F6E4A), width: 1),
                  ),
                  child: Text(
                    _successMessage!,
                    style: const TextStyle(
                      color: Color(0xFF1F6E4A),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (_successMessage != null) const SizedBox(height: 16),

            // Log in button
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6E4A),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                disabledBackgroundColor: Colors.grey[400],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Log in →',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Signup form with comprehensive validation (no date of birth – kept as original logic)
class SignupForm extends StatefulWidget {
  const SignupForm({super.key});

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _licenseController = TextEditingController();
  
  final _fullNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _licenseFocus = FocusNode();
  
  bool _isLoading = false;
  String? _passwordMatchError;
  String _selectedRole = 'Patient';

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _licenseController.dispose();
    _fullNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _licenseFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final response = await AuthService.signup(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber:
          _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
      role: _selectedRole == 'Patient' ? 'user' : 'provider',
      licenseNumber: _selectedRole == 'Healthcare Provider' ? _licenseController.text.trim() : null,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    final authToken = response['access_token'] ?? response['token'];
    if (authToken != null) {
      await AuthService.saveToken(authToken.toString());
      final signedUpEmail = _emailController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', signedUpEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created. You are now logged in.'),
          backgroundColor: Color(0xFF1F6E4A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainPage(email: signedUpEmail)),
      );
      return;
    }

    final error = response['detail'] ?? response['message'] ?? 'Signup failed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onConfirmPasswordChanged(String value) {
    setState(() {
      if (value.isNotEmpty && value != _passwordController.text) {
        _passwordMatchError = 'Passwords do not match';
      } else {
        _passwordMatchError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.all(context.isCompact ? 20.0 : 32.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Create account',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Join us to get started',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Full name field
            TextFormField(
              controller: _fullNameController,
              focusNode: _fullNameFocus,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                labelText: 'Full name',
                prefixIcon: const Icon(Icons.person_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Full name is required';
                }
                return null;
              },
              onFieldSubmitted: (_) => _emailFocus.requestFocus(),
            ),
            const SizedBox(height: 16),

            // Email field
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (!AuthService.isValidEmail(value ?? '')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
              onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
            ),
            const SizedBox(height: 16),

            // Phone number field
            TextFormField(
              controller: _phoneController,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(
                labelText: 'Phone number (optional)',
                hintText: '+1 555 123 4567',
                prefixIcon: const Icon(Icons.phone_android_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value != null && value.isNotEmpty && value.length < 7) {
                  return 'Enter a valid phone number or leave blank';
                }
                return null;
              },
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 16),

            // Password field
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                helperText:
                    'Minimum 8 characters with upper/lowercase, number, and symbol',
              ),
              validator: (value) {
                if (!AuthService.isStrongPassword(value ?? '')) {
                  return 'Password must be at least 8 characters with mixed case, number, and symbol';
                }
                return null;
              },
              onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
            ),
            const SizedBox(height: 16),

            // Confirm password field
            TextFormField(
              controller: _confirmPasswordController,
              focusNode: _confirmFocus,
              obscureText: true,
              textInputAction: _selectedRole == 'Healthcare Provider' ? TextInputAction.next : TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                errorText: _passwordMatchError,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              onChanged: _onConfirmPasswordChanged,
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              onFieldSubmitted: (_) => _selectedRole == 'Healthcare Provider' ? _licenseFocus.requestFocus() : _handleSignup(),
            ),
            const SizedBox(height: 16),

            // Role selection dropdown
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: InputDecoration(
                labelText: 'Register as a...',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Patient', child: Text('Patient')),
                DropdownMenuItem(value: 'Healthcare Provider', child: Text('Healthcare Provider / Doctor')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedRole = val;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // License number text field (visible only for providers)
            if (_selectedRole == 'Healthcare Provider') ...[
              TextFormField(
                controller: _licenseController,
                focusNode: _licenseFocus,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Health license number',
                  hintText: 'e.g., MD-12345-CM',
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                validator: (value) {
                  if (_selectedRole == 'Healthcare Provider' && (value == null || value.trim().length < 5)) {
                    return 'Please enter a valid license number (min 5 characters)';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleSignup(),
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),

            // Get started button
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSignup,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6E4A),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                disabledBackgroundColor: Colors.grey[400],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Get started →',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _tokenFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _showPassword = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _tokenFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (_tokenController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the reset token from your email'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!AuthService.isStrongPassword(_passwordController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password must be at least 8 characters and include upper/lowercase, number, and symbol',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final response = await AuthService.resetPassword(
      token: _tokenController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
    );
    setState(() => _isLoading = false);
    if (!mounted) return;

    final message = response['detail'] ?? response['message'] ?? 'Reset request failed';
    final success = response['message']?.toString().toLowerCase().contains('success') == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        backgroundColor: const Color(0xFF1F6E4A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Paste the reset token from your email and choose a new password.',
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tokenController,
                focusNode: _tokenFocus,
                decoration: InputDecoration(
                  labelText: 'Reset token',
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                  ),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      semanticLabel: _showPassword ? 'Hide password' : 'Show password',
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    splashRadius: 24,
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                  ),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _confirmFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                focusNode: _confirmFocus,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleReset(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleReset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6E4A),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Reset password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Main app page after successful login
class MainPage extends StatefulWidget {
  final String email;

  const MainPage({super.key, required this.email});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isLoading = true;
  String _role = 'user';
  String _fullName = '';
  String _errorMessage = '';
  String? _profilePicture;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = await AuthService.getCurrentUser();
      setState(() {
        _role = user['role'] ?? 'user';
        _fullName = user['full_name'] ?? '';
        _profilePicture = user['profile_picture']?.toString();
        _isLoading = false;
      });
      LocalNotificationService.syncAlarmsFromServer();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 350),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          focusColor: color.withAlpha(26),
          highlightColor: color.withAlpha(13),
          splashColor: color.withAlpha(51),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withAlpha(31),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = responsiveColumnCount(
      context,
      minTileWidth: 230,
      maxColumns: 4,
    );

    final String displayName = _fullName.isNotEmpty ? _fullName : widget.email;

    return Scaffold(
      appBar: AppBar(
        title: Text(_role == 'provider' ? 'Wadocta Provider Portal' : 'Wadocta Dashboard'),
        backgroundColor: const Color(0xFF1F6E4A),
        actions: [
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileScreen(email: widget.email)),
              );
              _loadUserProfile();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white24,
                  backgroundImage: _profilePicture != null && _profilePicture!.isNotEmpty
                      ? MemoryImage(base64Decode(_profilePicture!.contains(',') ? _profilePicture!.split(',').last : _profilePicture!))
                      : null,
                  child: _profilePicture != null && _profilePicture!.isNotEmpty
                      ? null
                      : const Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1F6E4A)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading your dashboard...',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                    ),
                  ],
                ),
              )
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'Could not load profile data',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey.shade900),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _errorMessage = '';
                              });
                              _loadUserProfile();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F6E4A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Retry'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              await AuthService.logout();
                              if (!context.mounted) return;
                              navigator.pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const AuthenticationScreen(),
                                ),
                              );
                            },
                            child: const Text('Log out'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: context.responsivePagePadding(bottom: 32),
                    child: ResponsiveCenter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: const Icon(
                              Icons.health_and_safety,
                              size: 72,
                              color: Color(0xFF1F6E4A),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _role == 'provider' ? 'Welcome back, Dr. $displayName!' : 'Good day, $displayName!',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _role == 'provider' ? 'Healthcare Provider Account' : 'Logged in as ${widget.email}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.black54,
                                ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Quick access',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final effectiveColumns = columns > 0 ? columns : 1;
                              final aspectRatio = context.isCompact 
                                ? 0.85  
                                : context.isMedium 
                                  ? 1.0   
                                  : 1.15; 
                              
                              if (_role == 'provider') {
                                // Doctor Dashboard
                                return GridView.count(
                                  crossAxisCount: effectiveColumns,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: aspectRatio,
                                  children: [
                                  ],
                                );
                              } else {
                                // Patient Dashboard
                                return GridView.count(
                                  crossAxisCount: effectiveColumns,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: aspectRatio,
                                  children: [
                                    _buildDashboardCard(
                                      context,
                                      title: 'Health Chat',
                                      subtitle: 'Talk with the AI assistant',
                                      icon: Icons.chat_bubble_outline,
                                      color: Colors.blue.shade700,
                                      onTap: () => _navigate(context, const ChatScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Emergency Help',
                                      subtitle: 'Get urgent care advice',
                                      icon: Icons.local_hospital_outlined,
                                      color: Colors.red.shade700,
                                      onTap: () => _navigate(context, const EmergencyScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Health Tips',
                                      subtitle: 'Learn simple wellness habits',
                                      icon: Icons.lightbulb_outline,
                                      color: Colors.teal.shade700,
                                      onTap: () => _navigate(context, const HealthTipsScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Symptom Checker',
                                      subtitle: 'Check your symptoms quickly',
                                      icon: Icons.medical_services_outlined,
                                      color: Colors.orange.shade700,
                                      onTap: () => _navigate(context, const SymptomCheckerScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Medication',
                                      subtitle: 'Reminders, adherence & refills',
                                      icon: Icons.medication,
                                      color: Colors.indigo.shade700,
                                      onTap: () => _navigate(context, const MedicationScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Health Tracker',
                                      subtitle: 'Track vitals, daily habits & goals',
                                      icon: Icons.favorite_border_rounded,
                                      color: const Color(0xFF059669),
                                      onTap: () => _navigate(context, const HealthTrackerScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Reports & Records',
                                      subtitle: 'Generate reports, manage medical records',
                                      icon: Icons.description_outlined,
                                      color: Colors.deepOrange.shade700,
                                      onTap: () => _navigate(context, const ReportsRecordsScreen()),
                                    ),
                                    _buildDashboardCard(
                                      context,
                                      title: 'Reminders & Alerts',
                                      subtitle: 'Manage appointments, medications & checks',
                                      icon: Icons.notifications_active_outlined,
                                      color: Colors.pink.shade700,
                                      onTap: () => _navigate(context, const RemindersAlertsScreen()),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: ElevatedButton(
                              onPressed: () async {
                                final navigator = Navigator.of(context);
                                await AuthService.logout();
                                if (!context.mounted) return;
                                navigator.pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const AuthenticationScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F6E4A),
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white70,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                minimumSize: const Size(120, 48),
                              ),
                              child: const Text('Log out'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// Simple user model used by profile and persistence flows
class User {
  final String fullName;
  final String email;
  final String password;
  final DateTime dob;
  final String location;
  final String? profilePicPath;

  User({
    required this.fullName,
    required this.email,
    required this.password,
    required this.dob,
    required this.location,
    this.profilePicPath,
  });

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'email': email,
        'password': password,
        'dob': dob.toIso8601String(),
        'location': location,
        if (profilePicPath != null) 'profilePicPath': profilePicPath,
      };

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      fullName: json['fullName'] as String,
      email: json['email'] as String,
      password: json['password'] as String,
      dob: DateTime.parse(json['dob'] as String),
      location: json['location'] as String,
      profilePicPath: json['profilePicPath'] as String?,
    );
  }
}

// ============================================================================
// Validation Helper Functions (moved to AuthService for consistency)
// ============================================================================
