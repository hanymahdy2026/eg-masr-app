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

class ChatsAndGroupsTab extends StatefulWidget {
  final String currentUserPhone;
  const ChatsAndGroupsTab({super.key, required this.currentUserPhone});
  @override
  State createState() => _ChatsAndGroupsTabState();
}

class _ChatsAndGroupsTabState extends State {
  List _users = [];
  List _groups = [];
  List _cachedContacts = [];
  bool _loading = true;
  bool _contactsLoading = false;
  ChatsAndGroupsTab get w => widget as ChatsAndGroupsTab;

  @override
  void initState() {
    super.initState();
    _loadData();
    _preloadContactsInBackground();
  }

  String _normalizePhone(String input) {
    String p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('20') && p.length == 12) p = '0${p.substring(2)}';
    if (p.length == 10 && p.startsWith('1')) p = '0$p';
    return p;
  }

  Future _loadData() async {
    try {
      final profs = await supabase
          .from('profiles')
          .select()
          .neq('phone', w.currentUserPhone);
      final grps = await supabase
          .from('groups')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _users = List.from(profs);
          _groups = List.from(grps);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _preloadContactsInBackground() async {
    if (_contactsLoading) return;
    _contactsLoading = true;
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (granted) {
        final raw = await FlutterContacts.getContacts(
            withProperties: true, withPhoto: false);
        _cachedContacts = raw;
      }
    } catch (_) {}
    _contactsLoading = false;
  }

  Future _openContactsScreen() async {
    if (_cachedContacts.isEmpty) {
      await _preloadContactsInBackground();
    }
    final regMap = <String, dynamic>{};
    for (var u in _users) {
      regMap[_normalizePhone(u['phone'].toString())] = u;
    }
    final matched = >[];
    final others = >[];
    final seen = <String>{};

    for (final c in _cachedContacts) {
      for (final ph in c.phones) {
        final norm = _normalizePhone(ph.number);
        if (norm.isEmpty || norm == w.currentUserPhone || seen.contains(norm)) {
          continue;
        }
        seen.add(norm);
        if (regMap.containsKey(norm)) {
          matched.add({
            'name': c.displayName.isEmpty ? norm : c.displayName,
            'phone': norm,
            'avatar': (regMap[norm]['avatar_url'] ?? '').toString(),
          });
        } else {
          others.add({
            'name': c.displayName.isEmpty ? ph.number : c.displayName,
            'phone': ph.number
          });
        }
      }
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullContactsScreen(
            myPhone: w.currentUserPhone, matched: matched, allContacts: others),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('EG MASR • المحادثات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_pin),
              tooltip: 'صفحتي الشخصية',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                        userPhone: w.currentUserPhone, isMe: true)),
              ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFFD4AF37),
            labelColor: Colors.white,
            tabs: [Tab(text: 'الدردشات الخاصة'), Tab(text: 'المجموعات')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        final ph = u['phone'].toString();
                        final avatar = (u['avatar_url'] ?? '').toString();
                        return ListTile(
                          leading: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(
                                      userPhone: ph, isMe: false)),
                            ),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: const Color(0xFF006A4E),
                              backgroundImage: avatar.startsWith('http')
                                  ? NetworkImage(avatar)
                                  : null,
                              child: !avatar.startsWith('http')
                                  ? const Icon(Icons.person,
                                      color: Colors.white)
                                  : null,
                            ),
                          ),
                          title: Text(u['full_name'] ?? ph,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(ph,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          trailing: const Icon(Icons.chevron_right,
                              color: Color(0xFF006A4E)),
                          onTap: () {
                            final list = [w.currentUserPhone, ph]..sort();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WhatsAppChatRoomScreen(
                                  myPhone: w.currentUserPhone,
                                  roomId: '${list[0]}_${list[1]}',
                                  peerPhone: ph,
                                  title: u['full_name'] ?? ph,
                                  peerAvatar: avatar,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  ListView.builder(
                    itemCount: _groups.length,
                    itemBuilder: (_, i) {
                      final g = _groups[i];
                      return ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFD4AF37),
                            child: Icon(Icons.groups, color: Colors.black)),
                        title: Text(g['group_name'] ?? '',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatsAppChatRoomScreen(
                              myPhone: w.currentUserPhone,
                              roomId: 'GROUP_${g['id']}',
                              peerPhone: g['id'].toString(),
                              title: g['group_name'] ?? 'جروب',
                              peerAvatar: '',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF006A4E),
          foregroundColor: Colors.white,
          onPressed: _openContactsScreen,
          child: const Icon(Icons.message),
        ),
      ),
    );
  }
}

class FullContactsScreen extends StatefulWidget {
  final String myPhone;
  final List> matched;
  final List> allContacts;
  const FullContactsScreen(
      {super.key,
      required this.myPhone,
      required this.matched,
      required this.allContacts});

  @override
  State createState() => _FullContactsScreenState();
}

class _FullContactsScreenState extends State<FullContactsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filteredMatched = widget.matched
        .where((m) =>
            m['name']!.toLowerCase().contains(_query) ||
            m['phone']!.contains(_query))
        .toList();
    final filteredOthers = widget.allContacts
        .where((c) =>
            c['name']!.toLowerCase().contains(_query) ||
            c['phone']!.contains(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('جهات الاتصال السريعة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الرقم فوراً...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (filteredMatched.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text('موجودون على EG MASR',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF006A4E))),
                  ),
                ...filteredMatched.map((m) => ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: Color(0xFF006A4E),
                          child: Icon(Icons.person, color: Colors.white)),
                      title: Text(m['name']!,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(m['phone']!),
                      onTap: () {
                        final list = [widget.myPhone, m['phone']!]..sort();
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatsAppChatRoomScreen(
                              myPhone: widget.myPhone,
                              roomId: '${list[0]}_${list[1]}',
                              peerPhone: m['phone']!,
                              title: m['name']!,
                              peerAvatar: m['avatar'] ?? '',
                            ),
                          ),
                        );
                      },
                    )),
                if (filteredOthers.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text('دعوة إلى EG MASR',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                ...filteredOthers.take(150).map((c) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone)),
                      title: Text(c['name']!),
                      subtitle: Text(c['phone']!),
                      trailing: TextButton(
                        onPressed: () => launchUrl(Uri.parse(
                            'sms:${c['phone']}?body=انضم لتطبيق EG MASR للتواصل والدفع والمشاوير')),
                        child: const Text('دعوة'),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class WhatsAppChatRoomScreen extends StatefulWidget {
  final String myPhone;
  final String roomId;
  final String peerPhone;
  final String title;
  final String peerAvatar;
  const WhatsAppChatRoomScreen(
      {super.key,
      required this.myPhone,
      required this.roomId,
      required this.peerPhone,
      required this.title,
      required this.peerAvatar});
  @override
  State createState() => _WhatsAppChatRoomScreenState();
}

class _WhatsAppChatRoomScreenState extends State<WhatsAppChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _playingUrl;
  late final Stream<List>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: true);
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _uploadMedia(List<int> bytes, String ext) async {
    final fileName =
        'chat_${widget.myPhone}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    for (final bucket in ['media', 'avatars']) {
      try {
        await supabase.storage.from(bucket).uploadBinary(
            fileName, bytes as dynamic,
            fileOptions: const FileOptions(upsert: true));
        return supabase.storage.from(bucket).getPublicUrl(fileName);
      } catch (_) {}
    }
    return '';
  }

  Future<void> _sendMessage(String text,
      {String type = 'text', String mediaUrl = ''}) async {
    if (text.trim().isEmpty && mediaUrl.isEmpty) return;
    _msgCtrl.clear();
    try {
      await supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_phone': widget.myPhone,
        'receiver_phone': widget.peerPhone,
        'content': text.trim(),
        'msg_type': type,
        'media_url': mediaUrl,
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    } catch (_) {}
  }

  Future<void> _pickAndSendImage(ImageSource src) async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: src, imageQuality: 75);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final url = await _uploadMedia(bytes, 'jpg');
    if (url.isNotEmpty) {
      await _sendMessage('صورة مرفقة', type: 'image', mediaUrl: url);
    }
  }

  Future<void> _pickAndSendVideo() async {
    final picker = ImagePicker();
    final vid = await picker.pickVideo(source: ImageSource.gallery);
    if (vid == null) return;
    final bytes = await vid.readAsBytes();
    final url = await _uploadMedia(bytes, 'mp4');
    if (url.isNotEmpty) {
      await _sendMessage('فيديو مرفق', type: 'video', mediaUrl: url);
    }
  }

  Future<void> _sendHighAccuracyLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.best));
      String place = '';
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          place =
              ' (${marks.first.street ?? ''}, ${marks.first.subLocality ?? ''}, ${marks.first.locality ?? ''})';
        }
      } catch (_) {}
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
      await _sendMessage('موقعي المباشر بدقة عالية$place:\n$mapsUrl',
          type: 'location');
    } catch (_) {}
  }

  Future<void> _toggleVoiceRecording() async {
    try {
      if (_isRecording) {
        final path = await _recorder.stop();
        setState(() => _isRecording = false);
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final url = await _uploadMedia(bytes, 'm4a');
            if (url.isNotEmpty) {
              await _sendMessage('رسالة صوتية 🎤', type: 'audio', mediaUrl: url);
            }
          }
        }
      } else {
        if (await _recorder.hasPermission()) {
          final dir = await getTemporaryDirectory();
          final filePath =
              '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await _recorder.start(const RecordConfig(), path: filePath);
          setState(() => _isRecording = true);
        }
      }
    } catch (_) {
      setState(() => _isRecording = false);
    }
  }

  void _openInChatMoneyTransfer() {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تحويل أموال إلى ${widget.title}'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'المبلغ بالجنيه المصري (ج.م)',
              prefixIcon: Icon(Icons.payments)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006A4E),
                foregroundColor: Colors.white),
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (amt <= 0) return;
              Navigator.pop(ctx);
              await _transferFunds(
                  widget.myPhone, widget.peerPhone, amt, 'تحويل داخل المحادثة');
              await _sendMessage(
                  'تم تحويل مبلغ ${amt.toStringAsFixed(2)} ج.م إلى محفظتك بنجاح 💸',
                  type: 'money');
            },
            child: const Text('إرسال المبلغ الآن'),
          ),
        ],
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          runSpacing: 16,
          children: [
            _attachOption(Icons.photo_library, 'صورة', Colors.purple, () {
              Navigator.pop(ctx);
              _pickAndSendImage(ImageSource.gallery);
            }),
            _attachOption(Icons.camera_alt, 'كاميرا', Colors.pink, () {
              Navigator.pop(ctx);
              _pickAndSendImage(ImageSource.camera);
            }),
            _attachOption(Icons.videocam, 'فيديو', Colors.orange, () {
              Navigator.pop(ctx);
              _pickAndSendVideo();
            }),
            _attachOption(Icons.location_on, 'موقعي GPS', Colors.green, () {
              Navigator.pop(ctx);
              _sendHighAccuracyLocation();
            }),
            _attachOption(Icons.payments, 'تحويل أموال', const Color(0xFFD4AF37),
                () {
              Navigator.pop(ctx);
              _openInChatMoneyTransfer();
            }),
          ],
        ),
      ),
    );
  }

  Widget _attachOption(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            CircleAvatar(
                radius: 26,
                backgroundColor: color,
                child: Icon(icon, color: Colors.white)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFD4AF37),
              backgroundImage: widget.peerAvatar.startsWith('http')
                  ? NetworkImage(widget.peerAvatar)
                  : null,
              child: !widget.peerAvatar.startsWith('http')
                  ? const Icon(Icons.person, color: Colors.black, size: 20)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Text('متصل • محادثة خاصة مشفرة',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.payments),
              onPressed: _openInChatMoneyTransfer),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    final isMe = m['sender_phone'] == widget.myPhone;
                    final content = (m['content'] ?? '').toString();
                    final type = (m['msg_type'] ?? 'text').toString();
                    final mediaUrl = (m['media_url'] ?? '').toString();
                    final isUrl = content.contains('http://') ||
                        content.contains('https://');
                    final timeStr = (m['created_at'] ?? '').toString().length >=
                            16
                        ? m['created_at'].toString().substring(11, 16)
                        : '';

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.76),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFFDCF8C6)
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(isMe ? 14 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 14),
                          ),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 2,
                                offset: Offset(0, 1))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (type == 'image' &&
                                mediaUrl.startsWith('http'))
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(mediaUrl,
                                    width: 220, fit: BoxFit.cover),
                              )
                            else if (type == 'video' &&
                                mediaUrl.startsWith('http'))
                              ElevatedButton.icon(
                                onPressed: () => launchUrl(Uri.parse(mediaUrl),
                                    mode: LaunchMode.externalApplication),
                                icon: const Icon(Icons.play_circle_fill),
                                label: const Text('تشغيل الفيديو'),
                              )
                            else if (type == 'audio' &&
                                mediaUrl.startsWith('http'))
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                        _playingUrl == mediaUrl
                                            ? Icons.stop_circle
                                            : Icons.play_circle_fill,
                                        color: const Color(0xFF006A4E),
                                        size: 32),
                                    onPressed: () async {
                                      if (_playingUrl == mediaUrl) {
                                        await _audioPlayer.stop();
                                        setState(() => _playingUrl = null);
                                      } else {
                                        setState(() => _playingUrl = mediaUrl);
                                        await _audioPlayer
                                            .play(UrlSource(mediaUrl));
                                      }
                                    },
                                  ),
                                  const Text('تسجيل صوتي',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ],
                              )
                            else
                              InkWell(
                                onTap: isUrl
                                    ? () {
                                        final match = RegExp(r'https?://\S+')
                                            .firstMatch(content);
                                        if (match != null) {
                                          launchUrl(
                                              Uri.parse(match.group(0)!),
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      }
                                    : null,
                                child: Text(
                                  content,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isUrl
                                        ? Colors.blue.shade800
                                        : Colors.black87,
                                    decoration: isUrl
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(timeStr,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey)),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.done_all,
                                      size: 14, color: Colors.blue),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file,
                              color: Colors.grey),
                          onPressed: _showAttachmentSheet,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            decoration: InputDecoration(
                              hintText: _isRecording
                                  ? 'جاري تسجيل الصوت...'
                                  : 'رسالة...',
                              border: InputBorder.none,
                            ),
                            onSubmitted: (v) => _sendMessage(v),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt,
                              color: Colors.grey),
                          onPressed: () =>
                              _pickAndSendImage(ImageSource.camera),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _isRecording
                      ? Colors.red
                      : const Color(0xFF006A4E),
                  child: IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                    ),
                    onPressed: _toggleVoiceRecording,
                  ),
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF006A4E),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () => _sendMessage(_msgCtrl.text),
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

class UserProfileScreen extends StatefulWidget {
  final String userPhone;
  final bool isMe;
  const UserProfileScreen(
      {super.key, required this.userPhone, required this.isMe});
  @override
  State createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map? _profile;
  List _userPosts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final prof = await supabase
          .from('profiles')
          .select()
          .eq('phone', widget.userPhone)
          .maybeSingle();
      final posts = await supabase
          .from('posts')
          .select()
          .eq('author_phone', widget.userPhone)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _profile = prof;
          _userPosts = List.from(posts);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeProfilePhoto() async {
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final fileName =
        'avatar_${widget.userPhone}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await supabase.storage
          .from('avatars')
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));
      final url = supabase.storage.from('avatars').getPublicUrl(fileName);
      await supabase
          .from('profiles')
          .update({'avatar_url': url}).eq('phone', widget.userPhone);
      _loadProfile();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['full_name'] ?? widget.userPhone;
    final avatar = (_profile?['avatar_url'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 54,
                            backgroundColor: const Color(0xFF006A4E),
                            backgroundImage: avatar.startsWith('http')
                                ? NetworkImage(avatar)
                                : null,
                            child: !avatar.startsWith('http')
                                ? const Icon(Icons.person,
                                    size: 54, color: Colors.white)
                                : null,
                          ),
                          if (widget.isMe)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFD4AF37),
                                child: IconButton(
                                  icon: const Icon(Icons.camera_alt,
                                      size: 16, color: Colors.black),
                                  onPressed: _changeProfilePhoto,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(name,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(widget.userPhone,
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('المنشورات',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                ..._userPosts.map((p) => Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['content'] ?? ''),
                            if ((p['media_url'] ?? '')
                                .toString()
                                .startsWith('http')) ...[
                              const SizedBox(height: 8),
                              Image.network(p['media_url'],
                                  width: double.infinity, fit: BoxFit.cover),
                            ],
                          ],
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}

class SocialFeedTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  const SocialFeedTab(
      {super.key, required this.currentUserPhone, required this.isAdmin});
  @override
  State createState() => _SocialFeedTabState();
}

class _SocialFeedTabState extends State<SocialFeedTab> {
  List _posts = [];
  Map<String, String> _avatarsMap = {};
  String _myName = 'مستخدم EG Masr';
  String _myAvatar = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    try {
      final profs = await supabase.from('profiles').select();
      final avMap = <String, String>{};
      for (var pr in profs) {
        avMap[pr['phone'].toString()] = (pr['avatar_url'] ?? '').toString();
        if (pr['phone'] == widget.currentUserPhone) {
          _myName = pr['full_name'] ?? _myName;
          _myAvatar = (pr['avatar_url'] ?? '').toString();
        }
      }
      final allPosts = await supabase
          .from('posts')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _avatarsMap = avMap;
          _posts = List.from(allPosts);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _uploadFileToSupabase(XFile file, String ext) async {
    final bytes = await file.readAsBytes();
    final fileName = 'egmasr_${DateTime.now().millisecondsSinceEpoch}.$ext';
    for (final bucket in ['media', 'avatars']) {
      try {
        await supabase.storage.from(bucket).uploadBinary(fileName, bytes,
            fileOptions: const FileOptions(upsert: true));
        return supabase.storage.from(bucket).getPublicUrl(fileName);
      } catch (_) {}
    }
    return '';
  }

  void _openCreatePostDialog() {
    final contentCtrl = TextEditingController();
    String mediaType = 'text';
    String uploadedUrl = '';
    bool uploading = false;
    final picker = ImagePicker();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('إنشاء منشور'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'بم تفكر؟ اكتب منشورك هنا...')),
              const SizedBox(height
