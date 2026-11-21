import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJkYmRpbXBoYnJzZXpmdGluZGNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3ODA1MDIsImV4cCI6MjA4OTM1NjUwMn0.35i7hN8Y4iM-W6s760sB6S-sK2R5N7B3Q9Z1X4W8E2A';
const String adminPhoneNumber = '01012055498';
const String _appSecuritySalt = 'EGMASR_SHIELD_2026_SECURE_KEY_#991';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrSuperApp());
}

final supabase = Supabase.instance.client;

class SecurityShield {
  static String signSession(String phone, String type) {
    final bytes = utf8.encode('$phone|$type\vert{}$_appSecuritySalt');
    return sha256.convert(bytes).toString();
  }

  static bool verifySession(String phone, String type, String? sig) {
    if (sig == null || sig.isEmpty) return false;
    return signSession(phone, type) == sig;
  }

  static String sanitize(String input) {
    return input.replaceAll(RegExp(r'[<>"\x27;]'), '').trim();
  }
}

class EgMasrSuperApp extends StatelessWidget {
  const EgMasrSuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EG MASR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006A4E),
          primary: const Color(0xFF006A4E),
          secondary: const Color(0xFFD4AF37),
          surface: const Color(0xFFF4F6F5),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF006A4E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State createState() => _AuthGateState();
}

class _AuthGateState extends State {
  String? _savedPhone;
  String _accountType = 'individual';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    final type = prefs.getString('account_type') ?? 'individual';
    final sig = prefs.getString('session_sig');

    if (phone != null &&
        phone.isNotEmpty &&
        SecurityShield.verifySession(phone, type, sig)) {
      setState(() {
        _savedPhone = phone;
        _accountType = type;
        _loading = false;
      });
    } else {
      await prefs.clear();
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_savedPhone != null && _savedPhone!.isNotEmpty) {
      return MainHomeShell(
        userPhone: _savedPhone!,
        accountType: _accountType,
      );
    }
    return LoginScreen(
      onLoginSuccess: (phone, type) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_phone', phone);
        await prefs.setString('account_type', type);
        await prefs.setString(
            'session_sig', SecurityShield.signSession(phone, type));
        setState(() {
          _savedPhone = phone;
          _accountType = type;
        });
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  final Function(String, String) onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});
  @override
  State createState() => _LoginScreenState();
}

class _LoginScreenState extends State {
  bool _isCorporate = false;
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _companyAddressCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _delegateCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String _generatedOtp = '';
  bool _otpSent = false;
  bool _busy = false;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  LoginScreen get w => widget as LoginScreen;

  String _normalizePhone(String input) {
    String p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('20') && p.length == 12) p = '0${p.substring(2)}';
    if (p.length == 10 && p.startsWith('1')) p = '0$p';
    return p;
  }

  void _sendOtpOnApp() {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم إيقاف المحاولات مؤقتاً للحماية 🛡️ انتظر دقيقة')),
      );
      return;
    }
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (phone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم موبايل مصري صحيح (11 رقم)')),
      );
      return;
    }
    if (_isCorporate &&
        (_companyNameCtrl.text.trim().isEmpty ||
            _companyAddressCtrl.text.trim().isEmpty ||
            _taxIdCtrl.text.trim().isEmpty ||
            _delegateCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى استكمال جميع بيانات المنشأة والمفوض')),
      );
      return;
    }
    final code = (100000 + Random.secure().nextInt(899999)).toString();
    setState(() {
      _generatedOtp = code;
      _otpSent = true;
      _otpCtrl.clear();
 });
 
    
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('كود التأكيد المتغير (6 أرقام): $code'),
    backgroundColor: const Color(0xFF006A4E),
    duration: const Duration(seconds: 8),
  ),
);
}

  Future _verifyAndEnter() async {
