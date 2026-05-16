import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// INTERNAL IMPORTS
import 'package:infiplus_opd/patient_list.dart';
import 'package:infiplus_opd/patient_details.dart';
import 'package:infiplus_opd/supabase_handler.dart';
import 'package:infiplus_opd/services/master_data_service.dart';
import 'package:infiplus_opd/services/server_data_service.dart' as sds;
import 'package:infiplus_opd/registration_form.dart';
import 'package:infiplus_opd/payment_panel.dart';

// ─────────────────────────────────────────────────────────────────
//  GLOBAL DESIGN SYSTEM
// ─────────────────────────────────────────────────────────────────
class AppColors {
  // Brand
  static const Color primary       = Color(0xFF6366F1); // Indigo-500
  static const Color primaryDark   = Color(0xFF4F46E5); // Indigo-600
  static const Color accent        = Color(0xFF818CF8); // Indigo-400
  static const Color accentLight   = Color(0xFFEEF2FF); // Indigo-50

  // Surfaces
  static const Color bgBody        = Color(0xFFF0F4FF);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceGlass  = Color(0xE8FFFFFF);

  // Text
  static const Color textPrimary   = Color(0xFF0F172A); // Slate-900
  static const Color textSecondary = Color(0xFF475569); // Slate-600
  static const Color textMuted     = Color(0xFF94A3B8); // Slate-400

  // Status
  static const Color success       = Color(0xFF10B981);
  static const Color warning       = Color(0xFFF59E0B);
  static const Color danger        = Color(0xFFEF4444);

  // Border
  static const Color border        = Color(0xFFE2E8F0); // Slate-200
}

// ─────────────────────────────────────────────────────────────────
//  PATIENT DATA MODEL
// ─────────────────────────────────────────────────────────────────
class Patient {
  final String name;
  final String ageInfo;
  final String phone;
  final String initials;
  final String gender;
  final String id; // UHID
  final String address;

  // OPD Specific Fields
  final int opdRegistrationId;
  final String visitType;
  final String doctorId;
  final String? createdAt;
  final bool isFinalized;
  final String visitStatus;
  final String hospitalName;
  final Map<String, dynamic> fullData; // Raw data for editing

  DateTime get visitDate {
    if (createdAt == null) return DateTime.now();
    return DateTime.parse(createdAt!).toLocal();
  }

  Patient({
    required this.name,
    required this.ageInfo,
    required this.phone,
    required this.initials,
    required this.gender,
    required this.id,
    required this.address,
    required this.opdRegistrationId,
    required this.fullData,
    this.visitType = '',
    this.doctorId = '',
    this.createdAt,
    this.isFinalized = false,
    this.visitStatus = '',
    this.hospitalName = '',
  });

  factory Patient.fromOpdMap(Map<String, dynamic> map) {
    final patientData = map['patient_detail'] ?? {};

    String pName = (patientData['name'] ?? 'Unknown').toString().trim();
    if (pName.isEmpty) pName = 'Unknown';

    String pGender = (patientData['gender'] ?? 'U').toString().trim();
    if (pGender.isEmpty) pGender = 'U';

    String pInitials = "P";
    if (pName != 'Unknown') {
      try {
        List<String> parts = pName.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (parts.length > 1) {
          pInitials = "${parts[0][0]}${parts[1][0]}".toUpperCase();
        } else if (parts.isNotEmpty) {
          pInitials = parts[0][0].toUpperCase();
        }
      } catch (e) {
        pInitials = pName.isNotEmpty ? pName[0].toUpperCase() : "?";
      }
    }

    return Patient(
      name: pName,
      ageInfo: "${patientData['age'] ?? '0'} ${patientData['age_unit'] ?? 'Y'}",
      phone: patientData['number']?.toString() ?? 'N/A',
      initials: pInitials,
      gender: pGender,
      id: patientData['uhid'] ?? '',
      address: patientData['address'] ?? '',
      opdRegistrationId: map['id'] ?? 0,
      visitType: map['visit_type'] ?? '',
      doctorId: map['treating_doctor_id']?.toString() ?? '',
      createdAt: map['created_at'],
      isFinalized: map['is_finalized'] ?? false,
      visitStatus: map['visit_status']?.toString() ?? '',
      hospitalName: map['hospital_name']?.toString() ?? '',
      fullData: map,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  MAIN
// ─────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseHandler.initialize();
  
  // Start loading master data in background, don't block the UI thread
  MasterDataService().initialize(); 
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final poppinsTextTheme = GoogleFonts.poppinsTextTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'InfiPlus OPD',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.bgBody,
        useMaterial3: true,
        textTheme: poppinsTextTheme.copyWith(
          displayLarge:  poppinsTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700),
          headlineLarge: poppinsTextTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
          headlineMedium: poppinsTextTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          titleLarge:    poppinsTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          titleMedium:   poppinsTextTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          bodyLarge:     poppinsTextTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
          bodyMedium:    poppinsTextTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
          labelLarge:    poppinsTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 14),
          hintStyle: GoogleFonts.poppins(color: AppColors.textMuted, fontSize: 13),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  AUTH GATE
// ─────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MasterDataService().loadStatus,
      builder: (context, isLoaded, _) {
        if (!isLoaded) {
          return const SplashScreen();
        }

        final session = SupabaseHandler.client.auth.currentSession;
        return session != null ? const PatientDashboardPage() : const LoginPage();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  SPLASH SCREEN — Prevents black screen, shows progress
// ─────────────────────────────────────────────────────────────────
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A), // Match login theme
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security_rounded, size: 64, color: Colors.white),
            ),
            const SizedBox(height: 32),
            Text("InfiPlus OPD",
              style: GoogleFonts.poppins(
                fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.2
              ),
            ),
            const SizedBox(height: 8),
            Text("Powering your clinical workspace",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  LOGIN PAGE  — Stunning glassmorphism design
// ─────────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading           = false;
  bool _obscurePassword     = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseHandler.client.auth.signInWithPassword(
        email:    _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PatientDashboardPage()));
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.danger));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unexpected error occurred"), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient Background ──────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF6366F1)],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // ── Decorative Circles ───────────────────────────────
          Positioned(top: -80, right: -80,
              child: _decorCircle(260, Colors.white.withValues(alpha: 0.06))),
          Positioned(bottom: -60, left: -60,
              child: _decorCircle(220, Colors.white.withValues(alpha: 0.08))),
          Positioned(top: 120, left: -40,
              child: _decorCircle(140, Colors.white.withValues(alpha: 0.04))),

          // ── Login Card ───────────────────────────────────────
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 420,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 60, offset: const Offset(0, 20)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Logo badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text("InfiPlus OPD",
                              style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          Text("Welcome back",
                            style: GoogleFonts.poppins(
                              fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text("Sign in to your clinical workspace",
                            style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 36),

                          // Email field
                          Text("Email address",
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: "doctor@hospital.com",
                              prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.textMuted),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Password field
                          Text("Password",
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                            onSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              hintText: "••••••••",
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textMuted),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 20, color: AppColors.textMuted,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Sign in button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _signIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                  : Text("Sign In", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Footer note
                          Center(
                            child: Text("Secure clinic access · InfiPlus HMS",
                              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
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
        ],
      ),
    );
  }

  Widget _decorCircle(double size, Color color) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  DASHBOARD PAGE
// ─────────────────────────────────────────────────────────────────
class PatientDashboardPage extends StatefulWidget {
  const PatientDashboardPage({super.key});
  @override
  State<PatientDashboardPage> createState() => _PatientDashboardPageState();
}

class _PatientDashboardPageState extends State<PatientDashboardPage> {
  List<Patient> patients   = [];
  bool _isLoading          = true;
  int  _selectedIndex      = 0;
  bool _isOffline          = false;
  bool _isSyncing          = false;
  bool _isRegistering      = false;
  bool _isAddingPayment    = false;
  Patient? _editingPatient;
  Patient? _paymentPatient;

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;


  @override
  void initState() {
    super.initState();
    _smartLoadData();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) _syncWithCloud();
    });

    // Listen for local changes (from tabs)
    sds.ServerDataService.refreshNotifier.addListener(_syncWithCloud);
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();

    sds.ServerDataService.refreshNotifier.removeListener(_syncWithCloud);
    super.dispose();
  }

  Future<void> _smartLoadData() async {
    await _syncWithCloud();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncWithCloud({String? searchQuery}) async {
    if (_isSyncing) return;
    if (mounted) {
      setState(() => _isSyncing = true);
    }
    try {
      final base = SupabaseHandler.client
          .from('opd_registration')
          .select('*, patient_detail!inner(*)')
          .eq('is_Deleted', false);

      dynamic request;
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.trim();
        
        // Step 1: Find patients that match the search query in patient_detail
        // We use a separate query to be safe with cross-table filtering compatibility
        final patientSearch = await SupabaseHandler.client
            .from('patient_detail')
            .select('uhid')
            .or('name.ilike.*$q*,uhid.ilike.*$q*,number.eq.${int.tryParse(q) ?? -1}')
            .limit(100);
        
        final matchingUhids = (patientSearch as List).map((p) => p['uhid'].toString()).toList();
        
        // Step 2: Query opd_registration for these UHIDs OR direct UHID matches
        String orFilter = 'uhid.ilike.*$q*';
        if (matchingUhids.isNotEmpty) {
          // Join matching UHIDs into a CSV for the .in_() filter equivalent in an or() string
          final uhidList = matchingUhids.map((id) => '"$id"').join(',');
          orFilter += ',uhid.in.($uhidList)';
        }
        
        request = base.or(orFilter);
      } else {
        request = base.order('created_at', ascending: false).limit(50);
      }

      final response = await request.timeout(const Duration(seconds: 10));
      final data = response as List<dynamic>;

      if (mounted) {
        setState(() {
          patients    = data.map((json) => Patient.fromOpdMap(json)).toList();
          _isOffline  = false;
          _isLoading  = false;
        });
      }
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('socketexception') || err.contains('timeout') || err.contains('host lookup')) {
        if (mounted) {
          setState(() => _isOffline = true);
        }
      } else {
        debugPrint("Critical Error: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Logout Confirmation", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Are you sure you want to log out from your workspace?", style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupabaseHandler.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet    = screenWidth > 800;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
              const SizedBox(height: 20),
              Text("Loading patient queue…",
                style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (patients.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              Text("No Patients Found", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              if (_isOffline)
                Text("You are currently offline.", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.warning)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _syncWithCloud,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // ── Status Banner ─────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  height: (_isOffline || _isSyncing) ? 28 : 0,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isOffline
                          ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                          : [const Color(0xFF10B981), const Color(0xFF059669)],
                    ),
                  ),
                  child: Center(
                    child: _isOffline
                        ? Text("OFFLINE MODE · CACHED DATA", style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                              const SizedBox(width: 8),
                              Text("Syncing with cloud…", style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            ],
                          ),
                  ),
                ),

                Expanded(
                  child: Row(
                    children: [
                      // ── LEFT SIDEBAR ─────────────────────────────
                      if (isTablet || !_isRegistering)
                        SizedBox(
                          width: isTablet ? 380 : screenWidth,
                          child: LeftPanelPatientList(
                            patients:          patients,
                            selectedIndex:     _selectedIndex,
                            onPatientSelected: (index) async {
                              setState(() {
                                _selectedIndex = index;
                                _isRegistering = false; // Close registration when patient selected
                                _editingPatient = null;
                              });
                              if (!isTablet) {
                                // On mobile, navigate to details page
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: Text(patients[index].name, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                                        leading: IconButton(
                                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                                          onPressed: () => Navigator.pop(context),
                                        ),
                                      ),
                                      body: RightPanelPatientDetails(patient: patients[index]),
                                    ),
                                  ),
                                );
                                // Auto-refresh when returning from details
                                _syncWithCloud();
                              }
                            },
                            onRefresh: ({searchQuery}) => _syncWithCloud(searchQuery: searchQuery),
                            onNewRegistration: () {
                              setState(() {
                                _isRegistering = true;
                                _editingPatient = null;
                              });
                            },
                            onEditPatient: (p) async {
                              setState(() {
                                _editingPatient = p;
                                _isRegistering = true;
                                _isAddingPayment = false;
                              });
                              if (!isTablet) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      body: RegistrationForm(
                                        editPatient: p,
                                        onCancel: () => Navigator.pop(context),
                                        onSuccess: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                );
                                _syncWithCloud();
                              }
                            },
                            onAddPayment: (p) async {
                              setState(() {
                                _paymentPatient = p;
                                _isAddingPayment = true;
                                _isRegistering = false;
                              });
                              if (!isTablet) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      body: PaymentPanel(
                                        patient: p,
                                        onCancel: () => Navigator.pop(context),
                                        onSuccess: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                );
                                _syncWithCloud();
                              }
                            },
                          ),
                        ),

                      // ── RIGHT DETAIL PANEL / REGISTRATION FORM ───
                      if (isTablet || _isRegistering)
                        Expanded(
                          child: Container(
                            color: AppColors.bgBody,
                            child: _isRegistering
                                ? RegistrationForm(
                                    editPatient: _editingPatient,
                                    onCancel: () => setState(() {
                                      _isRegistering = false;
                                      _editingPatient = null;
                                    }),
                                    onSuccess: () {
                                      setState(() {
                                        _isRegistering = false;
                                        _editingPatient = null;
                                      });
                                      _syncWithCloud();
                                    },
                                  )
                                : _isAddingPayment
                                    ? PaymentPanel(
                                        patient: _paymentPatient ?? patients[_selectedIndex],
                                        onCancel: () => setState(() => _isAddingPayment = false),
                                        onSuccess: () {
                                          setState(() => _isAddingPayment = false);
                                          _syncWithCloud();
                                        },
                                      )
                                    : RightPanelPatientDetails(patient: patients[_selectedIndex]),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Hidden Logout Button (Subtle, but visible enough)
          Positioned(
            left: 10,
            bottom: 10,
            child: Opacity(
              opacity: 0.4, // Increased from 0.15 for better visibility
              child: IconButton(
                icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.textMuted),
                onPressed: _showLogoutConfirmation,
                tooltip: "Logout",
              ),
            ),
          ),
        ],
      ),
    );
  }
}