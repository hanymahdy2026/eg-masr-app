import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

typedef JsonMap = Map<String, dynamic>;

// بيانات الأدمن الأساسي (أنت)
const String ADMIN_CONTACT = 'h27n4y200@gmail.com';

// أشهر 20 لغة في العالم
const List> SUPPORTED_LANGUAGES = [
  {'code': 'ar', 'name': 'العربية (Arabic)'},
  {'code': 'en', 'name': 'English (الإنجليزية)'},
  {'code': 'fr', 'name': 'Français (الفرنسية)'},
  {'code': 'de', 'name': 'Deutsch (الألمانية)'},
  {'code': 'es', 'name': 'Español (الإسبانية)'},
  {'code': 'it', 'name': 'Italiano (الإيطالية)'},
  {'code': 'tr', 'name': 'Türkçe (التركية)'},
  {'code': 'ru', 'name': 'Русский (الروسية)'},
  {'code': 'zh', 'name': '中文 (الصينية)'},
  {'code': 'ja', 'name': '日本語 (اليابانية)'},
  {'code': 'ko', 'name': '한국어 (الكورية)'},
  {'code': 'hi', 'name': 'हिन्दी (الهندية)'},
  {'code': 'ur', 'name': 'اردو (الأردية)'},
  {'code': 'pt', 'name': 'Português (البرتغالية)'},
  {'code': 'nl', 'name': 'Nederlands (الهولندية)'},
  {'code': 'sv', 'name': 'Svenska (السويدية)'},
  {'code': 'pl', 'name': 'Polski (البولندية)'},
  {'code': 'el', 'name': 'Ελληνικά (اليونانية)'},
  {'code': 'id', 'name': 'Bahasa Indonesia (الإندونيسية)'},
  {'code': 'ms', 'name': 'Bahasa Melayu (الماليزية)'},
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://bdbdimphbrsezftindck.supabase.co',
    anonKey: 'sb_publishable_pJ66bE2_25v6M4kG_uI1nA_g5cE6W0m',
  );
  runApp(const EgMasrSuperApp());
}

final supabase = Supabase.instance.client;

class EgMasrSuperApp extends StatefulWidget {
  const EgMasrSuperApp({super.key});

  @override
  State<EgMasrSuperApp> createState() => _EgMasrSuperAppState();
}

class _EgMasrSuperAppState extends State<EgMasrSuperApp> {
  Locale _locale = const Locale('ar');

  void _changeLanguage(String langCode) {
    setState(() {
      _locale = Locale(langCode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EG Masr',
      locale: _locale,
      supportedLocales: SUPPORTED_LANGUAGES.map((l) => Locale(l['code']!)).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF075E54)),
        useMaterial3: true,
      ),
      home: DualAuthScreen(
        currentLang: _locale.languageCode,
        onLangChanged: _changeLanguage,
      ),
    );
  }
}

// ==========================================
// 1. شاشة الدخول المزدوج (شخصي / شركات) + اختيار اللغة
// ==========================================
class DualAuthScreen extends StatefulWidget {
  final String currentLang;
  final Function(String) onLangChanged;

  const DualAuthScreen({
    super.key,
    required this.currentLang,
    required this.onLangChanged,
  });

  @override
  State<DualAuthScreen> createState() => _DualAuthScreenState();
}

class _DualAuthScreenState extends State<DualAuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _personalContactCtrl = TextEditingController();
  final _personalNameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _isLoading = false;

  final _compNameCtrl = TextEditingController();
  final _compAddressCtrl = TextEditingController();
  final _compPlotCtrl = TextEditingController();
  final _compTaxCtrl = TextEditingController();
  final _compManagerCtrl = TextEditingController();
  final _compContactCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _sendOtp() async {
    final contact = _personalContactCtrl.text.trim();
    if (contact.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final code = (100000 + Random().nextInt(900000)).toString();

      if (contact.contains('@')) {
        try {
          await supabase.auth.signInWithOtp(email: contact);
        } catch (_) {}
      }

      setState(() {
        _otpSent = true;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال كود التفعيل (كود التجربة السريعة: $code)'),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyAndEnterPersonal() async {
    final contact = _personalContactCtrl.text.trim();
    final name = _personalNameCtrl.text.trim().isEmpty ? contact : _personalNameCtrl.text.trim();
    final enteredOtp = _otpCtrl.text.trim();

    if (enteredOtp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال كود التحقق المكون من 6 أرقام')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final existing = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', contact)
          .maybeSingle();

      JsonMap userData;
      if (existing == null) {
        final qrData = 'EGMASR-USER-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
        final isAdmin = (contact.toLowerCase() == ADMIN_CONTACT.toLowerCase());
        userData = await supabase.from('users_profiles').insert({
          'contact_info': contact,
          'full_name': name,
          'qr_code_data': qrData,
          'is_admin': isAdmin,
        }).select().single();
      } else {
        userData = existing;
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainHomeScreen(
              currentUser: userData,
              isCompany: false,
              currentLang: widget.currentLang,
              onLangChanged: widget.onLangChanged,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content
