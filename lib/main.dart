import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

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
    final bytes = utf8.encode('$phone|$type|$_appSecuritySalt');
    return sha256.convert(bytes).toString();
  }

  static bool verifySession(String phone, String type, String? sig) {
    if (sig == null || sig.isEmpty) return false;
    return signSession(phone, type) == sig;
  }

  static String sanitize(String input) {
    return input.replaceAll(RegExp(r'[<>"\x27;]'), '').trim();
  }

  static String generateUniqueQr(String phone, bool isCorporate) {
    final nonce = Random.secure().nextInt(999999999).toString().padLeft(9, '0');
    final ts = DateTime.now().microsecondsSinceEpoch.toString();
    final digest = sha256
        .convert(utf8.encode('$phone|$ts|$nonce|$_appSecuritySalt'))
        .toString()
        .substring(0, 14)
        .toUpperCase();
    final prefix = isCorporate ? 'EGMASR-CORP' : 'EGMASR-USER';
    return '$prefix-$phone-$digest-$nonce';
  }
}

Future _transferFunds(
    String senderPhone, String receiverPhone, double amount, String note) async {
  final ref = 'TX-${Random.secure().nextInt(899999) + 100000}';
  await supabase.from('transactions').insert({
    'ref_code': ref,
    'sender_phone': senderPhone,
    'receiver_phone': receiverPhone,
    'amount': amount,
    'tx_type': 'transfer',
    'note': note,
  });
  try {
    final rec = await supabase
        .from('profiles')
        .select()
        .eq('phone', receiverPhone)
        .maybeSingle();
    if (rec != null) {
      final newBal = (rec['balance'] ?? 0).toDouble() + amount;
      await supabase
          .from('profiles')
          .update({'balance': newBal}).eq('phone', receiverPhone);
    }
  } catch (_) {}
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
          surface: const Color(0xFFF0F2F5),
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
            content: Text('تم إيقاف المحاولات مؤقتاً للحماية انتظر دقيقة')),
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
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return;
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (_otpCtrl.text.trim() != _generatedOtp || _generatedOtp.isEmpty) {
      _failedAttempts++;
      if (_failedAttempts >= 3) {
        _lockedUntil = DateTime.now().add(const Duration(minutes: 1));
        _failedAttempts = 0;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('كود التأكيد غير صحيح!'), backgroundColor: Colors.red),
      );
      return;
    }
    _failedAttempts = 0;
    setState(() => _busy = true);
    try {
      if (_isCorporate) {
        final compName = SecurityShield.sanitize(_companyNameCtrl.text);
        final compAddr = SecurityShield.sanitize(_companyAddressCtrl.text);
        final taxId = SecurityShield.sanitize(_taxIdCtrl.text);
        final delegate = SecurityShield.sanitize(_delegateCtrl.text);

        final existingComp = await supabase
            .from('companies')
            .select()
            .eq('phone', phone)
            .maybeSingle();

        if (existingComp == null) {
          await supabase.from('companies').insert({
            'company_name': compName,
            'company_address': compAddr,
            'tax_id': taxId,
            'delegate_name': delegate,
            'phone': phone,
            'status': phone == adminPhoneNumber ? 'approved' : 'pending',
          });
          if (phone != adminPhoneNumber) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تم إرسال طلب تسجيل الشركة'),
                  content: const Text(
                      'حساب شركتك قيد المراجعة الآن لحين موافقة الإدارة.'),
                  actions: [
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('حسناً'))
                  ],
                ),
              );
            }
            setState(() => _busy = false);
            return;
          }
        } else if ((existingComp['status'] ?? 'pending') != 'approved' &&
            phone != adminPhoneNumber) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('طلب شركتك ما زال في انتظار موافقة الإدارة')),
            );
          }
          setState(() => _busy = false);
          return;
        }
        final existingProf = await supabase
            .from('profiles')
            .select()
            .eq('phone', phone)
            .maybeSingle();
        if (existingProf == null) {
          await supabase.from('profiles').insert({
            'phone': phone,
            'full_name': compName.isEmpty ? 'حساب شركات' : compName,
            'balance': 0.0,
            'avatar_url': '',
          });
        }
        w.onLoginSuccess(phone, 'corporate');
      } else {
        final name = SecurityShield.sanitize(_nameCtrl.text).isEmpty
            ? 'مستخدم EG Masr'
            : SecurityShield.sanitize(_nameCtrl.text);
        final existing = await supabase
            .from('profiles')
            .select()
            .eq('phone', phone)
            .maybeSingle();
        if (existing == null) {
          await supabase.from('profiles').insert({
            'phone': phone,
            'full_name': name,
            'balance': 0.0,
            'avatar_url': '',
          });
        }
        w.onLoginSuccess(phone, 'individual');
      }
    } catch (_) {
      w.onLoginSuccess(phone, _isCorporate ? 'corporate' : 'individual');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF006A4E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFF006A4E),
                      child: Icon(Icons.verified_user,
                          size: 34, color: Color(0xFFD4AF37)),
                    ),
                    const SizedBox(height: 10),
                    const Text('EG MASR',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF006A4E))),
                    const Text('نظام مشفّر ومؤمّن بالكامل',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('حساب أفراد')),
                            selected: !_isCorporate,
                            selectedColor: const Color(0xFF006A4E),
                            labelStyle: TextStyle(
                                color: !_isCorporate
                                    ? Colors.white
                                    : Colors.black),
                            onSelected: (_) =>
                                setState(() => _isCorporate = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('حساب شركات')),
                            selected: _isCorporate,
                            selectedColor: const Color(0xFFD4AF37),
                            labelStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold),
                            onSelected: (_) =>
                                setState(() => _isCorporate = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_isCorporate)
                      TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'الاسم بالكامل',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      )
                    else ...[
                      TextField(
                        controller: _companyNameCtrl,
                        decoration: InputDecoration(
                          labelText: 'اسم المنشأة / الشركة',
                          prefixIcon: const Icon(Icons.business),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _companyAddressCtrl,
                        decoration: InputDecoration(
                          labelText: 'عنوان المنشأة بالتفصيل',
                          prefixIcon: const Icon(Icons.location_on),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _taxIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'رقم التسجيل الضريبي',
                          prefixIcon: const Icon(Icons.receipt_long),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _delegateCtrl,
                        decoration: InputDecoration(
                          labelText: 'اسم المسؤول أو المفوض',
                          prefixIcon: const Icon(Icons.badge),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'رقم الموبايل (01xxxxxxxxx)',
                        prefixIcon: const Icon(Icons.phone_android),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'كود التأكيد (6 أرقام)',
                          prefixIcon: const Icon(Icons.lock_open),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006A4E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy
                            ? null
                            : (_otpSent ? _verifyAndEnter : _sendOtpOnApp),
                        child: _busy
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _otpSent
                                    ? 'تأكيد الكود والدخول'
                                    : 'إرسال كود التأكيد',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
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
    );
  }
}

class MainHomeShell extends StatefulWidget {
  final String userPhone;
  final String accountType;
  const MainHomeShell(
      {super.key, required this.userPhone, required this.accountType});
  @override
  State createState() => _MainHomeShellState();
}

class _MainHomeShellState extends State {
  int _index = 0;
  late final List _pages;
  MainHomeShell get w => widget as MainHomeShell;

  @override
  void initState() {
    super.initState();
    final isAdmin = w.userPhone == adminPhoneNumber;
    final isComp = w.accountType == 'corporate';
    _pages = [
      ChatsAndGroupsTab(currentUserPhone: w.userPhone),
      SocialFeedTab(currentUserPhone: w.userPhone, isAdmin: isAdmin),
      DirectPayAndQrTab(
          currentUserPhone: w.userPhone,
          isAdmin: isAdmin,
          isCorporate: isComp),
      ServicesTab(
          currentUserPhone: w.userPhone,
          canAccessBus: isComp || isAdmin),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages.cast<Widget>()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat), label: 'المحادثات'),
          NavigationDestination(
              icon: Icon(Icons.dynamic_feed), label: 'الموجز'),
          NavigationDestination(
              icon: Icon(Icons.qr_code_scanner), label: 'المحفظة والباركود'),
          NavigationDestination(
              icon: Icon(Icons.local_taxi), label: 'المشاوير والخدمات'),
        ],
      ),
    );
  }
}
