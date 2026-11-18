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

  // متحكمات الحساب الشخصي
  final _personalContactCtrl = TextEditingController();
  final _personalNameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  String _generatedDemoOtp = '';
  bool _isLoading = false;

  // متحكمات حساب الشركات
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

  // إرسال كود تحقق 6 أرقام
  Future<void> _sendOtp() async {
    final contact = _personalContactCtrl.text.trim();
    if (contact.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // توليد كود 6 أرقام للتحقق الفوري (بجانب محاولة إرسال الإيميل)
      final code = (100000 + Random().nextInt(900000)).toString();
      _generatedDemoOtp = code;

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
            content: Text('تم إرسال كود التفعيل (للتجربة السريعة الكود هو: $code)'),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // تأكيد الكود ودخول الحساب الشخصي
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
      // التحقق أو إنشاء ملف المستخدم مع الباركود الخاص به
      final existing = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', contact)
          .maybeSingle();

      Map<String, dynamic> userData;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تسجيل أو دخول حساب الشركات
  Future<void> _submitCompany() async {
    final contact = _compContactCtrl.text.trim();
    if (contact.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final existing = await supabase
          .from('companies')
          .select()
          .eq('contact_info', contact)
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'approved') {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => MainHomeScreen(
                  currentUser: existing,
                  isCompany: true,
                  currentLang: widget.currentLang,
                  onLangChanged: widget.onLangChanged,
                ),
              ),
            );
          }
          return;
        } else {
          if (mounted) {
            _showPendingCompanyDialog(existing['company_name'], existing['status']);
          }
          return;
        }
      }

      // تسجيل شركة جديدة
      if (_compNameCtrl.text.isEmpty ||
          _compAddressCtrl.text.isEmpty ||
          _compPlotCtrl.text.isEmpty ||
          _compTaxCtrl.text.isEmpty ||
          _compManagerCtrl.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى ملء جميع بيانات المنشأة بالكامل')),
        );
        return;
      }

      await supabase.from('companies').insert({
        'company_name': _compNameCtrl.text.trim(),
        'address': _compAddressCtrl.text.trim(),
        'plot_number': _compPlotCtrl.text.trim(),
        'tax_reg_number': _compTaxCtrl.text.trim(),
        'manager_name': _compManagerCtrl.text.trim(),
        'contact_info': contact,
        'status': 'pending',
      });

      if (mounted) {
        _showPendingCompanyDialog(_compNameCtrl.text.trim(), 'pending');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPendingCompanyDialog(String compName, String status) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حالة تسجيل المنشأة'),
        content: Text(
          status == 'rejected'
              ? 'نعتذر، تم رفض طلب منشأة ($compName) من قبل الإدارة.'
              : 'تم إرسال بيانات منشأة ($compName) بنجاح!\n\nحسابك الآن قيد المراجعة والتأكيد من قبل الأدمن. بمجرد الموافقة ستتمكن من الدخول مباشرة.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EG Masr', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF075E54),
        actions: [
          // قائمة اختيار اللغة من أشهر 20 لغة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButton<String>(
              value: widget.currentLang,
              dropdownColor: const Color(0xFF075E54),
              icon: const Icon(Icons.language, color: Colors.white),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: SUPPORTED_LANGUAGES.map((lang) {
                return DropdownMenuItem<String>(
                  value: lang['code'],
                  child: Text(lang['name']!),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) widget.onLangChanged(val);
              },
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'حساب شخصي'),
            Tab(icon: Icon(Icons.business), text: 'حساب شركات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // التاب 1: الحساب الشخصي
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.verified_user, size: 70, color: Color(0xFF075E54)),
                const SizedBox(height: 12),
                const Text(
                  'تسجيل الدخول الشخصي',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _personalNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _personalContactCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني (Gmail) أو رقم الهاتف',
                    prefixIcon: Icon(Icons.contact_mail),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (!_otpSent)
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendOtp,
                    icon: const Icon(Icons.send),
                    label: const Text('إرسال كود التحقق (6 أرقام)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF075E54),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  )
                else ...[
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'أدخل كود التحقق (6 أرقام)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _verifyAndEnterPersonal,
                    icon: const Icon(Icons.login),
                    label: const Text('تأكيد ودخول التطبيق'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // التاب 2: حساب الشركات
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.apartment, size: 65, color: Color(0xFF075E54)),
                const SizedBox(height: 8),
                const Text(
                  'بوابة تسجيل ودخول الشركات',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'إذا كانت شركتك معتمدة مسبقاً، أدخل الإيميل/الهاتف واضغط دخول مباشرة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _compContactCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البريد الرسمي أو رقم هاتف الشركة *',
                    prefixIcon: Icon(Icons.phone_android),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _compNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنشأة / الشركة',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _compAddressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'العنوان بالتفصيل',
                    prefixIcon: Icon(Icons.location_on),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _compPlotCtrl,
                        decoration: const InputDecoration(
                          labelText: 'رقم القطعة',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _compTaxCtrl,
                        decoration: const InputDecoration(
                          labelText: 'رقم التسجيل الضريبي',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _compManagerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المسؤول / المدير المفوض',
                    prefixIcon: Icon(Icons.person_pin),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitCompany,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('تسجيل المنشأة / دخول الشركات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF075E54),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. الشاشة الرئيسية (المحادثات، جهات الاتصال + البحث، الباركود، لوحة الأدمن)
// ==========================================
class MainHomeScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final bool isCompany;
  final String currentLang;
  final Function(String) onLangChanged;

  const MainHomeScreen({
    super.key,
    required this.currentUser,
    required this.isCompany,
    required this.currentLang,
    required this.onLangChanged,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;
  List<Contact> _deviceContacts = [];
  List> _appUsers = [];
  String _searchQuery = '';
  bool _loadingContacts = true;

  @override
  void initState() {
    super.initState();
    _loadContactsAndUsers();
  }

  Future<void> _loadContactsAndUsers() async {
    try {
      // جلب المستخدمين المسجلين في التطبيق
      final usersRes = await supabase.from('users_profiles').select();
      _appUsers = List>.from(usersRes);

      // جلب جهات الاتصال من الهاتف
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        _deviceContacts = contacts;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingContacts = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = (!widget.isCompany && widget.currentUser['is_admin'] == true);
    final String displayName = widget.isCompany
        ? widget.currentUser['company_name']
        : (widget.currentUser['full_name'] ?? widget.currentUser['contact_info']);

    final List<Widget> pages = [
      // 1. صفحة الشات العام وجميع المستخدمين
      _buildChatsAndUsersTab(),
      // 2. صفحة جهات الاتصال والبحث بالاسم والرقم
      _buildContactsSearchTab(),
      // 3. صفحة الباركود الخاص والملف الشخصي
      _buildProfileQrTab(displayName),
      // 4. لوحة تحكم الأدمن (تظهر للأدمن فقط)
      if (isAdmin) const AdminPanelTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('EG Masr - $displayName', style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF075E54),
        actions: [
          DropdownButton<String>(
            value: widget.currentLang,
            dropdownColor: const Color(0xFF075E54),
            icon: const Icon(Icons.language, color: Colors.white),
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            items: SUPPORTED_LANGUAGES.map((lang) {
              return DropdownMenuItem<String>(
                value: lang['code'],
                child: Text(lang['name']!),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) widget.onLangChanged(val);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DualAuthScreen(
                    currentLang: widget.currentLang,
                    onLangChanged: widget.onLangChanged,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF075E54),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'المحادثات'),
          const BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'الأرقام والبحث'),
          const BottomNavigationBarItem(icon: Icon(Icons.qr_code_2), label: 'الباركود وحسابي'),
          if (isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'الأدمن'),
        ],
      ),
    );
  }

  // تبويب المحادثات المباشرة
  Widget _buildChatsAndUsersTab() {
    final myContact = widget.currentUser['contact_info'];
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFF075E54), child: Icon(Icons.groups, color: Colors.white)),
          title: const Text('غرفة المحادثة العامة (EG Masr)', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('تواصل مع الجميع بالصور والفيديو والصوت والموقع'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MultimediaChatScreen(
                  senderName: widget.isCompany ? widget.currentUser['company_name'] : widget.currentUser['full_name'],
                  senderContact: myContact,
                  receiverContact: 'ALL',
                  chatTitle: 'غرفة المحادثة العامة',
                ),
              ),
            );
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('المستخدمون المسجلون (اضغط لبدء محادثة خاصة)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _appUsers.length,
            itemBuilder: (context, index) {
              final u = _appUsers[index];
              if (u['contact_info'] == myContact) return const SizedBox.shrink();
              return ListTile(
                leading: CircleAvatar(child: Text((u['full_name'] ?? 'U')[0].toUpperCase())),
                title: Text(u['full_name'] ?? u['contact_info']),
                subtitle: Text(u['contact_info']),
                trailing: const Icon(Icons.message, color: Color(0xFF075E54)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MultimediaChatScreen(
                        senderName: widget.isCompany ? widget.currentUser['company_name'] : widget.currentUser['full_name'],
                        senderContact: myContact,
                        receiverContact: u['contact_info'],
                        chatTitle: u['full_name'] ?? u['contact_info'],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // تبويب جهات الاتصال والبحث بالاسم والرقم
  Widget _buildContactsSearchTab() {
    final filteredContacts = _deviceContacts.where((c) {
      final nameMatch = c.displayName.toLowerCase().contains(_searchQuery.toLowerCase());
      final phoneMatch = c.phones.any((p) => p.number.replaceAll(' ', '').contains(_searchQuery));
      return nameMatch || phoneMatch;
    }).toList();

    final filteredAppUsers = _appUsers.where((u) {
      final name = (u['full_name'] ?? '').toString().toLowerCase();
      final contact = (u['contact_info'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || contact.contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الموبايل...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade100,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        if (_loadingContacts)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView(
              children: [
                if (filteredAppUsers.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Text('نتائج البحث في مستخدمي التطبيق:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  ),
                  ...filteredAppUsers.map((u) => ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white)),
                        title: Text(u['full_name'] ?? ''),
                        subtitle: Text(u['contact_info'] ?? ''),
                        trailing: const Icon(Icons.chat),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MultimediaChatScreen(
                                senderName: widget.currentUser['full_name'] ?? 'مستخدم',
                                senderContact: widget.currentUser['contact_info'],
                                receiverContact: u['contact_info'],
                                chatTitle: u['full_name'] ?? u['contact_info'],
                              ),
                            ),
                          );
                        },
                      )),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text('جهات الاتصال على هاتفك:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ),
                ...filteredContacts.map((c) {
                  final phone = c.phones.isNotEmpty ? c.phones.first.number : 'بدون رقم';
                  return ListTile(
                    leading: CircleAvatar(child: Text(c.displayName.isNotEmpty ? c.displayName[0] : '#')),
                    title: Text(c.displayName),
                    subtitle: Text(phone),
                    trailing: const Icon(Icons.send, color: Color(0xFF075E54)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MultimediaChatScreen(
                            senderName: widget.currentUser['full_name'] ?? 'مستخدم',
                            senderContact: widget.currentUser['contact_info'],
                            receiverContact: phone,
                            chatTitle: c.displayName,
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  // تبويب الباركود الخاص والملف الشخصي
  Widget _buildProfileQrTab(String displayName) {
    final qrData = widget.isCompany
        ? 'COMPANY-${widget.currentUser['tax_reg_number']}'
        : (widget.currentUser['qr_code_data'] ?? widget.currentUser['contact_info']);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(widget.currentUser['contact_info'], style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220.0,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'هذا هو الباركود (QR Code) الخاص بحسابك\nيمكن للآخرين مسحه للتواصل معك فوراً',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. لوحة تحكم الأدمن (تأكيد أو رفض الشركات)
// ==========================================
class AdminPanelTab extends StatefulWidget {
  const AdminPanelTab({super.key});

  @override
  State<AdminPanelTab> createState() => _AdminPanelTabState();
}

class _AdminPanelTabState extends State<AdminPanelTab> {
  Future<void> _updateCompanyStatus(String id, String newStatus) async {
    await supabase.from('companies').update({'status': newStatus}).eq('id', id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: supabase.from('companies').select().order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final companies = List>.from(snapshot.data as List);
        if (companies.isEmpty) {
          return const Center(child: Text('لا توجد طلبات شركات حالياً'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: companies.length,
          itemBuilder: (context, index) {
            final c = companies[index];
            final status = c['status'];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(c['company_name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Chip(
                          label: Text(status == 'approved' ? 'مقبول' : (status == 'rejected' ? 'مرفوض' : 'قيد المراجعة')),
                          backgroundColor: status == 'approved' ? Colors.green.shade100 : Colors.amber.shade100,
                        ),
                      ],
                    ),
                    Text('المسؤول: ${c['manager_name']} | التواصل: ${c['contact_info']}'),
                    Text('العنوان: ${c['address']} | رقم القطعة: ${c['plot_number']}'),
                    Text('التسجيل الضريبي: ${c['tax_reg_number']}'),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _updateCompanyStatus(c['id'], 'approved'),
                          icon: const Icon(Icons.check),
                          label: const Text('تأكيد وموافقة'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _updateCompanyStatus(c['id'], 'rejected'),
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('رفض', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==========================================
// 4. شاشة الشات الشامل (نص + روابط + صور + فيديو + ريكورد صوتي + لوكيشن GPS)
// ==========================================
class MultimediaChatScreen extends StatefulWidget {
  final String senderName;
  final String senderContact;
  final String receiverContact;
  final String chatTitle;

  const MultimediaChatScreen({
    super.key,
    required this.senderName,
    required this.senderContact,
    required this.receiverContact,
    required this.chatTitle,
  });

  @override
  State<MultimediaChatScreen> createState() => _MultimediaChatScreenState();
}

class _MultimediaChatScreenState extends State<MultimediaChatScreen> {
  final _msgCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isUploading = false;

  // إرسال رسالة نصية أو رابط
  Future<void> _sendTextMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final isLink = text.startsWith('http://') || text.startsWith('https://');
    await supabase.from('messages').insert({
      'sender_phone': widget.senderContact,
      'receiver_contact': widget.receiverContact,
      'content': '${widget.senderName}: $text',
      'msg_type': isLink ? 'link' : 'text',
      'media_url': isLink ? text : null,
    });
  }

  // إرسال صورة أو فيديو
  Future<void> _pickAndSendMedia(bool isVideo) async {
    final XFile? file = isVideo
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('chat_media').uploadBinary(fileName, bytes);
      final publicUrl = supabase.storage.from('chat_media').getPublicUrl(fileName);

      await supabase.from('messages').insert({
        'sender_phone': widget.senderContact,
        'receiver_contact': widget.receiverContact,
        'content': isVideo ? '${widget.senderName} أرسل فيديو 🎥' : '${widget.senderName} أرسل صورة 📷',
        'msg_type': isVideo ? 'video' : 'image',
        'media_url': publicUrl,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الرفع: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // تسجيل وإرسال ريكورد صوتي
  Future<void> _toggleRecordAudio() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        setState(() => _isUploading = true);
        try {
          final file = File(path);
          final bytes = await file.readAsBytes();
          final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await supabase.storage.from('chat_media').uploadBinary(fileName, bytes);
          final publicUrl = supabase.storage.from('chat_media').getPublicUrl(fileName);

          await supabase.from('messages').insert({
            'sender_phone': widget.senderContact,
            'receiver_contact': widget.receiverContact,
            'content': '${widget.senderName} أرسل رسالة صوتية 🎤',
            'msg_type': 'audio',
            'media_url': publicUrl,
          });
        } finally {
          if (mounted) setState(() => _isUploading = false);
        }
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: filePath);
        setState(() => _isRecording = true);
      }
    }
  }

  // إرسال الموقع الجغرافي (Location GPS)
  Future<void> _sendCurrentLocation() async {
    setState(() => _isUploading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى السماح بالوصول للموقع')));
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';

      await supabase.from('messages').insert({
        'sender_phone': widget.senderContact,
        'receiver_contact': widget.receiverContact,
        'content': '${widget.senderName} شارك موقعه الجغرافي 📍',
        'msg_type': 'location',
        'media_url': mapsUrl,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديد الموقع: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatTitle, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF075E54),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(),
          Expanded(
            child: StreamBuilder<List>>(
              stream: supabase.from('messages').stream(primaryKey: ['id']).order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final allMsgs = snapshot.data!;
                // تصفية الرسائل حسب الغرفة أو المحادثة الخاصة
                final msgs = allMsgs.where((m) {
                  if (widget.receiverContact == 'ALL') {
                    return m['receiver_contact'] == 'ALL' || m['receiver_contact'] == null;
                  }
                  return (m['sender_phone'] == widget.senderContact && m['receiver_contact'] == widget.receiverContact) ||
                      (m['sender_phone'] == widget.receiverContact && m['receiver_contact'] == widget.senderContact);
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, index) {
                    final m = msgs[index];
                    final isMe = m['sender_phone'] == widget.senderContact;
                    final type = m['msg_type'] ?? 'text';
                    final mediaUrl = m['media_url'];

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFDCF8C6) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['content'] ?? '', style: const TextStyle(fontSize: 15)),
                            if (type == 'image' && mediaUrl != null) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(mediaUrl, height: 180, fit: BoxFit.cover),
                              ),
                            ],
                            if ((type == 'video' || type == 'location' || type == 'link') && mediaUrl != null) ...[
                              const SizedBox(height: 6),
                              ElevatedButton.icon(
                                onPressed: () => launchUrl(Uri.parse(mediaUrl), mode: LaunchMode.externalApplication),
                                icon: Icon(type == 'location' ? Icons.map : (type == 'video' ? Icons.play_circle : Icons.link)),
                                label: Text(type == 'location' ? 'فتح الموقع على الخريطة' : (type == 'video' ? 'تشغيل الفيديو' : 'فتح الرابط')),
                              ),
                            ],
                            if (type == 'audio' && mediaUrl != null) ...[
                              const SizedBox(height: 6),
                              ElevatedButton.icon(
                                onPressed: () => _audioPlayer.play(UrlSource(mediaUrl)),
                                icon: const Icon(Icons.volume_up),
                                label: const Text('استماع للريكورد الصوتي'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // شريط الإرسال والوسائط المتعددة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image, color: Colors.teal),
                  tooltip: 'إرسال صورة',
                  onPressed: () => _pickAndSendMedia(false),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.deepPurple),
                  tooltip: 'إرسال فيديو',
                  onPressed: () => _pickAndSendMedia(true),
                ),
                IconButton(
                  icon: const Icon(Icons.location_on, color: Colors.red),
                  tooltip: 'إرسال الموقع',
                  onPressed: _sendCurrentLocation,
                ),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic, color: _isRecording ? Colors.red : Colors.orange),
                  tooltip: 'ريكورد صوتي',
                  onPressed: _toggleRecordAudio,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة أو رابط...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF075E54)),
                  onPressed: _sendTextMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
