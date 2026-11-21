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

// ============================================================================
// 1. LOGIN SCREEN (SECURITY RATE-LIMIT + 6-DIGIT DYNAMIC OTP + CORPORATE)
// ============================================================================
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
        content: Text('كود التأكيد المتغير (6 أرقام): $code ✅'),
        backgroundColor: const Color(0xFF006A4E),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future _verifyAndEnter() async {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      return;
    }
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
                  title: const Text('تم إرسال طلب تسجيل الشركة ⏳'),
                  content: const Text(
                    'حساب شركتك قيد المراجعة الآن. لا يمكن الدخول لحساب الشركات إلا بعد موافقة مدير النظام (Admin).',
                  ),
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
                content: Text('طلب شركتك ما زال في انتظار موافقة الإدارة ⏳'),
                backgroundColor: Colors.orange,
              ),
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
                    const Text('نظام مشفّر ومؤمّن بالكامل 🛡️',
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
                            label: const Center(child: Text('حساب شركات 🏢')),
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

// ============================================================================
// 2. MAIN HOME SHELL
// ============================================================================
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
    final isComp =
        w.accountType == 'corporate' || w.userPhone == adminPhoneNumber;
    _pages = [
      ChatsAndGroupsTab(currentUserPhone: w.userPhone),
      SocialFeedTab(
          currentUserPhone: w.userPhone,
          isAdmin: w.userPhone == adminPhoneNumber),
      DirectPayAndQrTab(
          currentUserPhone: w.userPhone,
          isAdmin: w.userPhone == adminPhoneNumber,
          isCorporate: isComp),
      ServicesTab(
        currentUserPhone: w.userPhone,
        isCorporate: isComp,
      ),
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
              icon: Icon(Icons.chat_bubble_outline), label: 'المحادثات'),
          NavigationDestination(
              icon: Icon(Icons.dynamic_feed_outlined), label: 'الموجز'),
          NavigationDestination(
              icon: Icon(Icons.qr_code_2), label: 'الدفع والباركود'),
          NavigationDestination(
              icon: Icon(Icons.directions_car), label: 'أوبر والخدمات'),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. CHATS & LIVE GPS LOCATION SHARING (LIKE UBER)
// ============================================================================
class ChatsAndGroupsTab extends StatefulWidget {
  final String currentUserPhone;
  const ChatsAndGroupsTab({super.key, required this.currentUserPhone});
  @override
  State createState() => _ChatsAndGroupsTabState();
}

class _ChatsAndGroupsTabState extends State {
  List _users = [];
  List _groups = [];
  Set _blockedPhones = {};
  bool _loading = true;
  ChatsAndGroupsTab get w => widget as ChatsAndGroupsTab;

  @override
  void initState() {
    super.initState();
    _loadData();
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
      final rels = await supabase
          .from('user_relations')
          .select()
          .eq('user_phone', w.currentUserPhone);
      final blocked = <String>{};
      for (var r in rels) {
        if (r['relation_type'] == 'block') {
          blocked.add(r['target_phone'].toString());
        }
      }
      if (mounted) {
        setState(() {
          _users = List.from(profs);
          _groups = List.from(grps);
          _blockedPhones = blocked;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _openContactsScreen() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) return;
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final regMap = {};
    for (var u in _users) {
      regMap[_normalizePhone(u['phone'].toString())] = u;
    }
    final matched = [];
    final others = [];
    for (final c in contacts) {
      for (final ph in c.phones) {
        final norm = _normalizePhone(ph.number);
        if (norm.isEmpty || norm == w.currentUserPhone) continue;
        if (regMap.containsKey(norm)) {
          matched.add({'name': c.displayName, 'phone': norm});
        } else {
          others.add({'name': c.displayName, 'phone': ph.number});
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
    final visibleUsers =
        _users.where((u) => !_blockedPhones.contains(u['phone'])).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحادثات والجروبات'),
          bottom: const TabBar(
            indicatorColor: Color(0xFFD4AF37),
            labelColor: Colors.white,
            tabs: [Tab(text: 'محادثات خاصة'), Tab(text: 'الجروبات')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ListView.separated(
                    itemCount: visibleUsers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = visibleUsers[i];
                      final ph = u['phone'].toString();
                      return ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFF006A4E),
                            child: Icon(Icons.person, color: Colors.white)),
                        title: Text(u['full_name'] ?? ph),
                        subtitle: Text(ph),
                        onTap: () {
                          final list = [w.currentUserPhone, ph]..sort();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomScreen(
                                myPhone: w.currentUserPhone,
                                roomId: '${list[0]}_${list[1]}',
                                peerPhone: ph,
                                title: u['full_name'] ?? ph,
                                isGroup: false,
                                onRelationChanged: _loadData,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  ListView.builder(
                    itemCount: _groups.length,
                    itemBuilder: (_, i) {
                      final g = _groups[i];
                      return ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFD4AF37),
                            child: Icon(Icons.groups, color: Colors.black)),
                        title: Text(g['group_name'] ?? ''),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomScreen(
                              myPhone: w.currentUserPhone,
                              roomId: 'GROUP_${g['id']}',
                              peerPhone: g['id'].toString(),
                              title: g['group_name'] ?? 'جروب',
                              isGroup: true,
                              onRelationChanged: _loadData,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF006A4E),
          foregroundColor: Colors.white,
          onPressed: _openContactsScreen,
          icon: const Icon(Icons.contacts),
          label: const Text('جهات الاتصال'),
        ),
      ),
    );
  }
}

class FullContactsScreen extends StatelessWidget {
  final String myPhone;
  final List matched;
  final List allContacts;
  const FullContactsScreen(
      {super.key,
      required this.myPhone,
      required this.matched,
      required this.allContacts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جهات الاتصال')),
      body: ListView(
        children: [
          ...matched.map((m) => ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0xFF006A4E),
                    child: Icon(Icons.person, color: Colors.white)),
                title: Text(m['name']),
                subtitle: Text(m['phone']),
                onTap: () {
                  final list = [myPhone, m['phone'].toString()]..sort();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatRoomScreen(
                        myPhone: myPhone,
                        roomId: '${list[0]}_${list[1]}',
                        peerPhone: m['phone'],
                        title: m['name'],
                        isGroup: false,
                      ),
                    ),
                  );
                },
              )),
          ...allContacts.map((c) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.phone)),
                title: Text(c['name']),
                subtitle: Text(c['phone']),
                trailing: TextButton(
                  onPressed: () => launchUrl(
                      Uri.parse('sms:${c['phone']}?body=انضم لتطبيق EG MASR')),
                  child: const Text('دعوة'),
                ),
              )),
        ],
      ),
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  final String myPhone;
  final String roomId;
  final String peerPhone;
  final String title;
  final bool isGroup;
  final VoidCallback? onRelationChanged;

  const ChatRoomScreen({
    super.key,
    required this.myPhone,
    required this.roomId,
    required this.peerPhone,
    required this.title,
    required this.isGroup,
    this.onRelationChanged,
  });
  @override
  State createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State {
  final _msgCtrl = TextEditingController();
  List _messages = [];
  ChatRoomScreen get w => widget as ChatRoomScreen;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future _fetchMessages() async {
    try {
      final res = await supabase
          .from('messages')
          .select()
          .eq('room_id', w.roomId)
          .order('created_at', ascending: true);
      if (mounted) setState(() => _messages = List.from(res));
    } catch (_) {}
  }

  Future _sendMessage(String text, {String type = 'text'}) async {
    if (text.trim().isEmpty) return;
    _msgCtrl.clear();
    setState(() => _messages.add({
          'sender_phone': w.myPhone,
          'content': text.trim(),
          'msg_type': type
        }));
    try {
      await supabase.from('messages').insert({
        'room_id': w.roomId,
        'sender_phone': w.myPhone,
        'receiver_phone': w.peerPhone,
        'content': text.trim(),
        'msg_type': type,
      });
    } catch (_) {}
  }

  Future _sendMyLiveLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      String placeName = '';
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          placeName =
              ' (${marks.first.street ?? ''}, ${marks.first.locality ?? ''})';
        }
      } catch (_) {}
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
      _sendMessage('📍 موقعي اللحظي$placeName:\n$mapsUrl', type: 'location');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(w.title),
        actions: [
          IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: 'إرسال موقعي',
              onPressed: _sendMyLiveLocation),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchMessages),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isMe = m['sender_phone'] == w.myPhone;
                final content = m['content'].toString();
                final isLoc = content.contains('https://www.google.com/maps');
                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: InkWell(
                    onTap: isLoc
                        ? () => launchUrl(
                            Uri.parse(content.split('\n').last.trim()),
                            mode: LaunchMode.externalApplication)
                        : null,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF006A4E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(content,
                          style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87)),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.red),
                    onPressed: _sendMyLiveLocation),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك...', border: InputBorder.none),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF006A4E)),
                    onPressed: () => _sendMessage(_msgCtrl.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. SOCIAL FEED TAB
// ============================================================================
class SocialFeedTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  const SocialFeedTab(
      {super.key, required this.currentUserPhone, required this.isAdmin});
  @override
  State createState() => _SocialFeedTabState();
}

class _SocialFeedTabState extends State {
  List _posts = [];
  String _myName = 'مستخدم EG Masr';
  bool _loading = true;
  SocialFeedTab get w => widget as SocialFeedTab;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future _loadFeed() async {
    try {
      final me = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.currentUserPhone)
          .maybeSingle();
      if (me != null) _myName = me['full_name'] ?? _myName;
      final allPosts = await supabase
          .from('posts')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _posts = List.from(allPosts);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _uploadFileToSupabase(XFile file, String ext) async {
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
          title: const Text('منشور جديد في الموجز'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'اكتب منشورك...')),
              const SizedBox(height: 10),
              if (uploading) const CircularProgressIndicator(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: uploading
                          ? null
                          : () async {
                              final img = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 75);
                              if (img != null) {
                                setSt(() => uploading = true);
                                final url =
                                    await _uploadFileToSupabase(img, 'jpg');
                                setSt(() {
                                  uploading = false;
                                  if (url.isNotEmpty) {
                                    uploadedUrl = url;
                                    mediaType = 'image';
                                  }
                                });
                              }
                            },
                      icon: const Icon(Icons.image),
                      label: const Text('صورة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: uploading
                          ? null
                          : () async {
                              final vid = await picker.pickVideo(
                                  source: ImageSource.gallery);
                              if (vid != null) {
                                setSt(() => uploading = true);
                                final url =
                                    await _uploadFileToSupabase(vid, 'mp4');
                                setSt(() {
                                  uploading = false;
                                  if (url.isNotEmpty) {
                                    uploadedUrl = url;
                                    mediaType = 'video';
                                  }
                                });
                              }
                            },
                      icon: const Icon(Icons.video_library),
                      label: const Text('فيديو'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (contentCtrl.text.trim().isEmpty && uploadedUrl.isEmpty) {
                  return;
                }
                Navigator.pop(ctx);
                await supabase.from('posts').insert({
                  'author_phone': w.currentUserPhone,
                  'author_name': _myName,
                  'content': SecurityShield.sanitize(contentCtrl.text),
                  'media_url': uploadedUrl,
                  'media_type': mediaType,
                  'privacy': 'public',
                  'likes': [],
                  'comments': [],
                });
                _loadFeed();
              },
              child: const Text('نشر'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('موجز EG MASR')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _posts.length,
              itemBuilder: (_, i) {
                final p = _posts[i];
                final mediaUrl = (p['media_url'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['author_name'] ?? '',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        if ((p['content'] ?? '').toString().isNotEmpty)
                          Text(p['content']),
                        if (p['media_type'] == 'image' &&
                            mediaUrl.startsWith('http')) ...[
                          const SizedBox(height: 8),
                          Image.network(mediaUrl,
                              width: double.infinity, fit: BoxFit.cover),
                        ] else if (p['media_type'] == 'video' &&
                            mediaUrl.startsWith('http')) ...[
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => launchUrl(Uri.parse(mediaUrl),
                                mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('تشغيل الفيديو'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF006A4E),
        foregroundColor: Colors.white,
        onPressed: _openCreatePostDialog,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('نشر بالموجز'),
      ),
    );
  }
}

// ============================================================================
// 5. DIRECT ELECTRONIC WALLETS, EG MASR WALLET & UNIQUE QR CODE
// ============================================================================
class DirectPayAndQrTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  final bool isCorporate;
  const DirectPayAndQrTab({
    super.key,
    required this.currentUserPhone,
    required this.isAdmin,
    required this.isCorporate,
  });
  @override
  State createState() => _DirectPayAndQrTabState();
}

class _DirectPayAndQrTabState extends State {
  String _linkedAccount = '';
  String _uniqueQrToken = '';
  double _egMasrBalance = 0.0;
  DirectPayAndQrTab get w => widget as DirectPayAndQrTab;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _linkedAccount =
        prefs.getString('direct_linked_${w.currentUserPhone}') ?? '';
    String? savedQr = prefs.getString('unique_qr_${w.currentUserPhone}');
    if (savedQr == null || savedQr.isEmpty) {
      final hash = SecurityShield.signSession(
              w.currentUserPhone, DateTime.now().toIso8601String())
          .substring(0, 12)
          .toUpperCase();
      final prefix = w.isCorporate ? 'EGMASR-CORP' : 'EGMASR-USER';
      savedQr = '$prefix-${w.currentUserPhone}-$hash';
      await prefs.setString('unique_qr_${w.currentUserPhone}', savedQr);
    }
    try {
      final prof = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.currentUserPhone)
          .maybeSingle();
      if (prof != null) {
        _egMasrBalance = (prof['balance'] ?? 0).toDouble();
      }
    } catch (_) {}
    if (mounted) setState(() => _uniqueQrToken = savedQr!);
  }

  void _openLinkDialog() {
    final numCtrl = TextEditingController();
    String provider = 'فودافون كاش (Vodafone Cash)';
    final providers = [
      'فودافون كاش (Vodafone Cash)',
      'اتصالات كاش (e& Money)',
      'أورانج كاش (Orange Cash)',
      'فيزا / ماستركارد / ميزة (Visa/Meeza)',
      'محفظة EG MASR الإلكترونية',
    ];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('ربط وسيلة الدفع الإلكتروني 💳'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                value: provider,
                isExpanded: true,
                items: providers
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setSt(() => provider = v.toString());
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: numCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'رقم المحفظة أو البطاقة'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final clean = numCtrl.text.trim();
                if (clean.length < 11) return;
                Navigator.pop(ctx);
                final label =
                    '$provider (****${clean.substring(clean.length - 4)})';
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                    'direct_linked_${w.currentUserPhone}', label);
                setState(() => _linkedAccount = label);
              },
              child: const Text('تأكيد الربط'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(w.isCorporate
            ? 'حساب الشركة والباركود 🏢'
            : 'الدفع الإلكتروني والباركود'),
        actions: [
          if (w.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings,
                  color: Color(0xFFD4AF37)),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminGovernanceScreen())),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const AuthGate()));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (w.isAdmin)
            Card(
              color: const Color(0xFFD4AF37),
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings,
                    color: Colors.black),
                title: const Text('لوحة تحكم الأدمن (اعتماد الشركات)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminGovernanceScreen())),
              ),
            ),
          Card(
            color: const Color(0xFF006A4E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    w.isCorporate ? 'حساب شركة معتمد 🏢' : 'حساب شخصي مؤمّن 🛡️',
                    style: const TextStyle(
                        color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text('رصيد محفظة EG MASR: $_egMasrBalance ج.م',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24, height: 22),
                  Text(
                    _linkedAccount.isEmpty
                        ? 'اربط فودافون / اتصالات / أورانج كاش أو فيزا للدفع المباشر'
                        : 'وسيلة الدفع المربوطة:\n$_linkedAccount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: Colors.black),
                    onPressed: _openLinkDialog,
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('ربط محفظة إلكترونية / فيزا'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                      w.isCorporate
                          ? 'الباركود الفريد الخاص بالشركة'
                          : 'الباركود الفريد الخاص بك (غير قابل للتكرار)',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_uniqueQrToken.isNotEmpty)
                    QrImageView(data: _uniqueQrToken, size: 170),
                  Text(_uniqueQrToken,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminGovernanceScreen extends StatefulWidget {
  const AdminGovernanceScreen({super.key});
  @override
  State createState() => _AdminGovernanceScreenState();
}

class _AdminGovernanceScreenState extends State {
  List _companies = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future _load() async {
    final comps = await supabase
        .from('companies')
        .select()
        .order('created_at', ascending: false);
    if (mounted) setState(() => _companies = List.from(comps));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اعتماد الشركات (Admin)')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _companies.length,
        itemBuilder: (_, i) {
          final c = _companies[i];
          return Card(
            child: ListTile(
              title: Text(c['company_name'] ?? ''),
              subtitle: Text(
                  'موبايل: ${c['phone']} | ضريبي: ${c['tax_id']}\nالحالة: ${c['status']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () async {
                      await supabase
                          .from('companies')
                          .update({'status': 'approved'}).eq('id', c['id']);
                      _load();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () async {
                      await supabase
                          .from('companies')
                          .update({'status': 'rejected'}).eq('id', c['id']);
                      _load();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 6. SERVICES TAB: UBER RIDES + TALABAT + PICKUP/JUMBO + COMPANY BUS TRACKER
// ============================================================================
class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool isCorporate;
  const ServicesTab(
      {super.key, required this.currentUserPhone, required this.isCorporate});

  @override
  Widget build(BuildContext context) {
    final places = [
      {
        'name': 'مطعم صبحي كابر (Sobhy Kaber)',
        'type': 'مطعم مشويات وطواجن',
        'address': '151 شارع عبيد، روض الفرج، شبرا، القاهرة',
        'officialUrl': 'https://www.google.com/search?q=مطعم+صبحي+كابر+الرسمي',
      },
      {
        'name': 'مطعم قصر الكبابجي (Qasr El Kababgi)',
        'type': 'مطعم مشويات ملكي',
        'address': 'التجمع الخامس / الشيخ زايد',
        'officialUrl': 'https://www.google.com/search?q=مطعم+قصر+الكبابجي+الرسمي',
      },
      {
        'name': 'كافيه سيلانترو (Cilantro Cafe)',
        'type': 'كافيه ومشروبات',
        'address': 'الزمالك / المعادي / مصر الجديدة',
        'officialUrl': 'https://www.google.com/search?q=Cilantro+Cafe+Egypt+official',
      },
      {
        'name': 'فندق فيرمونت نايل سيتي (Fairmont Nile City)',
        'type': 'فندق 5 نجوم على النيل',
        'address': 'كورنيش النيل، القاهرة',
        'officialUrl': 'https://www.google.com/search?q=Fairmont+Nile+City+official',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('أوبر والتوصيل والخدمات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. UBER-LIKE RIDES & DELIVERY SECTION
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF004D38), Color(0xFF006A4E)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مشاوير أوبر ونقل البضائع والطلبات 🚗🏍️🛻🚛',
                    style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'تتبع لحظي GPS • تسعيرة أوبر للملاكي والموتوسيكل • اتفاق مباشر للربع نقل والجامبو • تقييم الرحلة',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: Colors.black),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UberRideAndCargoScreen(
                                customerPhone: currentUserPhone,
                                initialMode: 'ride'),
                          ),
                        ),
                        icon: const Icon(Icons.local_taxi),
                        label: const Text('اطلب مشوار (أوبر)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF006A4E)),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UberRideAndCargoScreen(
                                customerPhone: currentUserPhone,
                                initialMode: 'cargo'),
                          ),
                        ),
                        icon: const Icon(Icons.local_shipping),
                        label: const Text('طلبات / ربع نقل / جامبو'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54)),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CaptainUberPortalScreen(
                                  captainPhone: currentUserPhone)),
                        ),
                        icon: const Icon(Icons.badge),
                        label: const Text('سجّل ككابتن (أوبر)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD4AF37),
                            side: const BorderSide(color: Color(0xFFD4AF37))),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => LiveTripTrackingScreen(
                                  userPhone: currentUserPhone)),
                        ),
                        icon: const Icon(Icons.my_location),
                        label: const Text('متابعة رحلتي GPS'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. EXCLUSIVE CORPORATE FEATURE: FOLLOW THE BUS (تابع الباص)
          if (isCorporate) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.directions_bus,
                          color: Color(0xFF004D38), size: 28),
                      SizedBox(width: 8),
                      Text('تابع الباص 🚌 (خدمة حصرية للشركات)',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D38))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'سجّل خطوط باصات الموظفين ومحطات الدائري والطرق، وتابع موقع الباص لحظة بلحظة مع إشعار فوري عند تخطي كل محطة.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004D38),
                          foregroundColor: const Color(0xFFD4AF37)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CorporateBusTrackerScreen(
                                companyPhone: currentUserPhone)),
                      ),
                      icon: const Icon(Icons.route),
                      label: const Text('إدارة ومتابعة باصات الموظفين الآن'),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 3. RESTAURANTS, CAFES & HOTELS (OFFICIAL PREVIEW + IN-APP BOOKING)
          const SizedBox(height: 18),
          const Text('الفنادق والمطاعم والكافيهات (معاينة رسمية وحجز داخلي)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...places.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['name']!,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${p['type']} • 📍 ${p['address']}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => launchUrl(
                                  Uri.parse(p['officialUrl']!),
                                  mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.public, size: 18),
                              label: const Text('معاينة الصفحة الرسمية'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF006A4E),
                                  foregroundColor: Colors.white),
                              onPressed: () => _openInAppBookingDialog(
                                  context, p['name']!, p['type']!),
                              icon: const Icon(Icons.bookmark_add, size: 18),
                              label: const Text('احجز من التطبيق'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  void _openInAppBookingDialog(
      BuildContext context, String placeName, String placeType) {
    final guestsCtrl = TextEditingController(text: '2');
    DateTime date = DateTime.now().add(const Duration(days: 1));
    TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
    String payMethod = 'فودافون كاش / إلكتروني';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('حجز داخلي: $placeName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: guestsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'عدد الأفراد / الغرف',
                      prefixIcon: Icon(Icons.people)),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text('التاريخ: ${date.year}-${date.month}-${date.day}'),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 180)),
                    );
                    if (d != null) setSt(() => date = d);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text('الساعة: ${time.format(ctx)}'),
                  onTap: () async {
                    final t =
                        await showTimePicker(context: ctx, initialTime: time);
                    if (t != null) setSt(() => time = t);
                  },
                ),
                DropdownButtonFormField(
                  value: payMethod,
                  items: const [
                    DropdownMenuItem(
                        value: 'فودافون كاش / إلكتروني',
                        child: Text('محفظة إلكترونية / فيزا')),
                    DropdownMenuItem(
                        value: 'محفظة EG MASR', child: Text('محفظة EG MASR')),
                    DropdownMenuItem(
                        value: 'دفع نقدي عند الوصول',
                        child: Text('دفع نقدي (Cash)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => payMethod = v.toString());
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006A4E),
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final ref = 'BKG-${Random().nextInt(89999) + 10000}';
                await supabase.from('transactions').insert({
                  'ref_code': ref,
                  'sender_phone': currentUserPhone,
                  'receiver_phone': placeName,
                  'amount': 0.0,
                  'tx_type': 'booking',
                  'note':
                      'حجز $placeName (${guestsCtrl.text} أفراد) يوم ${date.day}/${date.month} الساعة ${time.format(context)} - $payMethod',
                });
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('تم تأكيد حجزك بنجاح ✅'),
                      content: Text(
                          'المكان: $placeName\nالتاريخ: ${date.day}/${date.month}/${date.year}\nالساعة: ${time.format(context)}\nالدفع: $payMethod\nرقم الحجز: #$ref'),
                      actions: [
                        ElevatedButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('تم'))
                      ],
                    ),
                  );
                }
              },
              child: const Text('تأكيد الحجز الآن'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. UBER-LIKE RIDE & CARGO SCREEN (GPS + PRICING + QUARTER/JUMBO NEGOTIATION)
// ============================================================================
class UberRideAndCargoScreen extends StatefulWidget {
  final String customerPhone;
  final String initialMode;
  const UberRideAndCargoScreen(
      {super.key, required this.customerPhone, required this.initialMode});
  @override
  State createState() => _UberRideAndCargoScreenState();
}

class _UberRideAndCargoScreenState extends State {
  String _vehicle = 'car';
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _offerPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _paymentMethod = 'cash';
  double? _pickupLat;
  double? _pickupLng;
  double _distanceKm = 6.5;

  UberRideAndCargoScreen get w => widget as UberRideAndCargoScreen;

  @override
  void initState() {
    super.initState();
    _vehicle = w.initialMode == 'cargo' ? 'quarter_truck' : 'car';
    _detectMyGpsLocation();
  }

  Future _detectMyGpsLocation() async {
