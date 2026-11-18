import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey = 'sb_publishable_bQ1u1u3iE9h5w_g7Y5k1A_q2R8t6Y4u2';
const String adminEmail = 'h27n4y200@gmail.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrApp());
}

final supabase = Supabase.instance.client;

const Map appTranslations = {
  'ar': {
    'appName': 'EG Masr',
    'personal': 'حساب شخصي',
    'company': 'حساب شركات',
    'name': 'الاسم بالكامل',
    'contact': 'رقم الهاتف أو البريد الإلكتروني (Gmail)',
    'sendOtp': 'إرسال كود التفعيل (4 أرقام)',
    'enterOtp': 'أدخل كود التفعيل (4 أرقام)',
    'verify': 'تأكيد الدخول',
    'companyName': 'اسم المنشأة / الشركة',
    'companyPhone': 'رقم المنشأة',
    'address': 'عنوان المنشأة',
    'taxReg': 'رقم التسجيل الضريبي',
    'managerName': 'اسم المسؤول',
    'registerCompany': 'تسجيل المنشأة',
    'pendingApproval': 'طلبك قيد المراجعة من الإدارة',
    'chats': 'المحادثات والجروبات',
    'contacts': 'جهات الاتصال',
    'myQr': 'الباركود',
    'admin': 'الأدمن',
    'newGroup': 'إنشاء جروب جديد',
    'groupName': 'اسم الجروب',
    'selectMembers': 'اختر الأعضاء',
    'create': 'إنشاء',
    'typeMsg': 'اكتب رسالة بالعربي أو الإنجليزي أو رابط...',
    'logout': 'تسجيل خروج',
  },
  'en': {
    'appName': 'EG Masr',
    'personal': 'Personal Account',
    'company': 'Company Account',
    'name': 'Full Name',
    'contact': 'Phone Number or Email (Gmail)',
    'sendOtp': 'Send 4-Digit Code',
    'enterOtp': 'Enter 4-Digit Code',
    'verify': 'Verify & Login',
    'companyName': 'Company / Facility Name',
    'companyPhone': 'Facility Phone Number',
    'address': 'Address',
    'taxReg': 'Tax Registration Number',
    'managerName': 'Manager Name',
    'registerCompany': 'Register Company',
    'pendingApproval': 'Your company is pending admin approval',
    'chats': 'Chats & Groups',
    'contacts': 'Contacts',
    'myQr': 'My QR',
    'admin': 'Admin',
    'newGroup': 'Create New Group',
    'groupName': 'Group Name',
    'selectMembers': 'Select Members',
    'create': 'Create',
    'typeMsg': 'Type a message or link...',
    'logout': 'Logout',
  },
};

class EgMasrApp extends StatefulWidget {
  const EgMasrApp({super.key});
  @override
  State<EgMasrApp> createState() => _EgMasrAppState();
}

class _EgMasrAppState extends State<EgMasrApp> {
  String _lang = 'ar';
  Map? _currentUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('lang') ?? 'ar';
    final savedContact = prefs.getString('user_contact');
    setState(() => _lang = savedLang);

    if (savedContact != null) {
      final user = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', savedContact)
          .maybeSingle();
      if (user != null) setState(() => _currentUser = user);
    }
    setState(() => _loading = false);
  }

  Future<void> _toggleLang() async {
    final next = _lang == 'ar' ? 'en' : 'ar';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', next);
    setState(() => _lang = next);
  }

  String tr(String key) {
    final map = appTranslations[_lang] as Map?;
    return (map?[key] ?? key).toString();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EG Masr',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF075E54)),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _currentUser == null
              ? AuthScreen(
                  lang: _lang,
                  onToggleLang: _toggleLang,
                  tr: tr,
                  onLoginSuccess: (user) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('user_contact', user['contact_info']);
                    setState(() => _currentUser = user);
                  },
                )
              : HomeScreen(
                  user: _currentUser!,
                  lang: _lang,
                  onToggleLang: _toggleLang,
                  tr: tr,
                  onLogout: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_contact');
                    setState(() => _currentUser = null);
                  },
                ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final String lang;
  final VoidCallback onToggleLang;
  final String Function(String) tr;
  final Function(Map) onLoginSuccess;

  const AuthScreen({
    super.key,
    required this.lang,
    required this.onToggleLang,
    required this.tr,
    required this.onLoginSuccess,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  String _generatedOtp = '';

  final _compNameCtrl = TextEditingController();
  final _compPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _sendCode() {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) return;
    final code = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    setState(() {
      _generatedOtp = code;
      _otpSent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('كود التفعيل المكون من 4 أرقام: $code'),
        duration: const Duration(seconds: 15),
      ),
    );
  }

  Future<void> _verifyPersonal() async {
    if (_otpCtrl.text.trim() != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود التفعيل غير صحيح')),
      );
      return;
    }
    final contact = _contactCtrl.text.trim().toLowerCase();
    final isAdmin = contact == adminEmail.toLowerCase();
    final res = await supabase
        .from('users_profiles')
        .upsert({
          'full_name': _nameCtrl.text.trim(),
          'contact_info': contact,
          'account_type': 'personal',
          'is_admin': isAdmin,
        }, onConflict: 'contact_info')
        .select()
        .single();
    widget.onLoginSuccess(res);
  }

  Future<void> _registerCompany() async {
    if (_compNameCtrl.text.isEmpty ||
        _compPhoneCtrl.text.isEmpty ||
        _addressCtrl.text.isEmpty ||
        _taxCtrl.text.isEmpty ||
        _managerCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إدخال جميع بيانات المنشأة')),
      );
      return;
    }
    final contact = _compPhoneCtrl.text.trim().toLowerCase();
    final existing = await supabase
        .from('companies')
        .select()
        .eq('contact_info', contact)
        .maybeSingle();

    if (existing != null) {
      if (existing['status'] == 'approved') {
        final user = await supabase
            .from('users_profiles')
            .upsert({
              'full_name': existing['company_name'],
              'contact_info': contact,
              'account_type': 'company',
              'is_admin': false,
            }, onConflict: 'contact_info')
            .select()
            .single();
        widget.onLoginSuccess(user);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.tr('pendingApproval'))),
        );
      }
      return;
    }

    await supabase.from('companies').insert({
      'company_name': _compNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'plot_number': _compPhoneCtrl.text.trim(),
      'tax_reg_number': _taxCtrl.text.trim(),
      'manager_name': _managerCtrl.text.trim(),
      'contact_info': contact,
      'status': 'pending',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.tr('pendingApproval'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tr('appName')),
        actions: [
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(widget.lang == 'ar' ? 'English' : 'عربي', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: widget.tr('personal')),
            Tab(text: widget.tr('company')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: widget.tr('name'))),
                const SizedBox(height: 12),
                TextField(controller: _contactCtrl, decoration: InputDecoration(labelText: widget.tr('contact'))),
                const SizedBox(height: 16),
                if (!_otpSent)
                  ElevatedButton(onPressed: _sendCode, child: Text(widget.tr('sendOtp')))
                else ...[
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(labelText: widget.tr('enterOtp')),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _verifyPersonal, child: Text(widget.tr('verify'))),
                ],
              ],
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _compNameCtrl, decoration: InputDecoration(labelText: widget.tr('companyName'))),
                TextField(controller: _compPhoneCtrl, decoration: InputDecoration(labelText: widget.tr('companyPhone'))),
                TextField(controller: _addressCtrl, decoration: InputDecoration(labelText: widget.tr('address'))),
                TextField(controller: _taxCtrl, decoration: InputDecoration(labelText: widget.tr('taxReg'))),
                TextField(controller: _managerCtrl, decoration: InputDecoration(labelText: widget.tr('managerName'))),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _registerCompany, child: Text(widget.tr('registerCompany'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Map user;
  final String lang;
  final VoidCallback onToggleLang;
  final String Function(String) tr;
  final VoidCallback onLogout;

  const HomeScreen({
    super.key,
    required this.user,
    required this.lang,
    required this.onToggleLang,
    required this.tr,
    required this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user['is_admin'] == true ||
        widget.user['contact_info'].toString().toLowerCase() == adminEmail.toLowerCase();

    final pages = [
      ChatsAndGroupsTab(user: widget.user, tr: widget.tr),
      ContactsScreen(user: widget.user, tr: widget.tr),
      QrScreen(user: widget.user, tr: widget.tr),
      if (isAdmin) AdminScreen(tr: widget.tr),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.tr('appName')} -${widget.user['full_name']}'),
        actions: [
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(widget.lang == 'ar' ? 'EN' : 'عربي', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat), label: widget.tr('chats')),
          NavigationDestination(icon: const Icon(Icons.contacts), label: widget.tr('contacts')),
          NavigationDestination(icon: const Icon(Icons.qr_code), label: widget.tr('myQr')),
          if (isAdmin) NavigationDestination(icon: const Icon(Icons.admin_panel_settings), label: widget.tr('admin')),
        ],
      ),
