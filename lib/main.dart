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
const String _appSecuritySalt = 'EGMASR_SHIELD_2026_SECURE_KEY_991';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrSuperApp());
}

final supabase = Supabase.instance.client;

String cleanEgyptianPhone(String input) {
  final buf = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c >= 48 && c <= 57) buf.writeCharCode(c);
  }
  String p = buf.toString();
  if (p.startsWith('20') && p.length == 12) p = '0${p.substring(2)}';
  if (p.length == 10 && p.startsWith('1')) p = '0$p';
  return p;
}

class SecurityShield {
  static String signSession(String phone, String type) {
    final bytes = utf8.encode('$phone-$type-$_appSecuritySalt');
    return sha256.convert(bytes).toString();
  }

  static bool verifySession(String phone, String type, String? sig) {
    if (sig == null || sig.isEmpty) return false;
    return signSession(phone, type) == sig;
  }

  static String sanitize(String input) {
    return input.replaceAll('<', '').replaceAll('>', '').trim();
  }

  static String generateUniqueQr(String phone, bool isCorporate) {
    final nonce = Random.secure().nextInt(999999999).toString().padLeft(9, '0');
    final ts = DateTime.now().microsecondsSinceEpoch.toString();
    final digest = sha256
        .convert(utf8.encode('$phone-$ts-$nonce-$_appSecuritySalt'))
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
      return MainHomeShell(userPhone: _savedPhone!, accountType: _accountType);
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
  LoginScreen get w => widget as LoginScreen;

  void _sendOtpOnApp() {
    final phone = cleanEgyptianPhone(_phoneCtrl.text.trim());
    if (phone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل رقم موبايل مصري صحيح (11 رقم)')));
      return;
    }
    if (_isCorporate &&
        (_companyNameCtrl.text.trim().isEmpty ||
            _companyAddressCtrl.text.trim().isEmpty ||
            _taxIdCtrl.text.trim().isEmpty ||
            _delegateCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى استكمال جميع بيانات المنشأة')));
      return;
    }
    final code = (100000 + Random.secure().nextInt(899999)).toString();
    setState(() {
      _generatedOtp = code;
      _otpSent = true;
      _otpCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('كود التأكيد (6 أرقام): $code'),
      backgroundColor: const Color(0xFF006A4E),
      duration: const Duration(seconds: 8),
    ));
  }

  Future _verifyAndEnter() async {
    final phone = cleanEgyptianPhone(_phoneCtrl.text.trim());
    if (_otpCtrl.text.trim() != _generatedOtp || _generatedOtp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('كود التأكيد غير صحيح!'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isCorporate) {
        final compName = SecurityShield.sanitize(_companyNameCtrl.text);
        final existingComp = await supabase
            .from('companies')
            .select()
            .eq('phone', phone)
            .maybeSingle();
        if (existingComp == null) {
          await supabase.from('companies').insert({
            'company_name': compName,
            'company_address': SecurityShield.sanitize(_companyAddressCtrl.text),
            'tax_id': SecurityShield.sanitize(_taxIdCtrl.text),
            'delegate_name': SecurityShield.sanitize(_delegateCtrl.text),
            'phone': phone,
            'status': phone == adminPhoneNumber ? 'approved' : 'pending',
          });
          if (phone != adminPhoneNumber) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تم إرسال طلب تسجيل الشركة'),
                  content: const Text('حساب شركتك قيد المراجعة الآن.'),
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
                const SnackBar(content: Text('طلب شركتك في انتظار الموافقة')));
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
                      radius: 30,
                      backgroundColor: Color(0xFF006A4E),
                      child: Icon(Icons.verified_user,
                          size: 32, color: Color(0xFFD4AF37)),
                    ),
                    const SizedBox(height: 8),
                    const Text('EG MASR',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF006A4E))),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 14),
                    if (!_isCorporate)
                      TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                            labelText: 'الاسم بالكامل',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14))),
                      )
                    else ...[
                      TextField(
                          controller: _companyNameCtrl,
                          decoration: InputDecoration(
                              labelText: 'اسم الشركة',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)))),
                      const SizedBox(height: 8),
                      TextField(
                          controller: _companyAddressCtrl,
                          decoration: InputDecoration(
                              labelText: 'عنوان الشركة',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)))),
                      const SizedBox(height: 8),
                      TextField(
                          controller: _taxIdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: 'السجل الضريبي',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)))),
                      const SizedBox(height: 8),
                      TextField(
                          controller: _delegateCtrl,
                          decoration: InputDecoration(
                              labelText: 'اسم المفوض',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)))),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                          labelText: 'رقم الموبايل (01xxxxxxxxx)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14))),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: 'كود التأكيد (6 أرقام)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14))),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006A4E),
                            foregroundColor: Colors.white),
                        onPressed: _busy
                            ? null
                            : (_otpSent ? _verifyAndEnter : _sendOtpOnApp),
                        child: _busy
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(_otpSent ? 'دخول' : 'إرسال كود التأكيد'),
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
          currentUserPhone: w.userPhone, isAdmin: isAdmin, isCorporate: isComp),
      ServicesTab(
          currentUserPhone: w.userPhone, canAccessBus: isComp || isAdmin),
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
          NavigationDestination(icon: Icon(Icons.chat), label: 'المحادثات'),
          NavigationDestination(icon: Icon(Icons.dynamic_feed), label: 'الموجز'),
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
  List _cachedContacts = [];
  bool _loading = true;
  bool _contactsLoading = false;
  ChatsAndGroupsTab get w => widget as ChatsAndGroupsTab;

  @override
  void initState() {
    super.initState();
    _loadData();
    _preloadContacts();
  }

  Future _loadData() async {
    try {
      final profs = await supabase
          .from('profiles')
          .select()
          .neq('phone', w.currentUserPhone);
      if (mounted) {
        setState(() {
          _users = List.from(profs);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _preloadContacts() async {
    if (_contactsLoading) return;
    _contactsLoading = true;
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (granted) {
        _cachedContacts = await FlutterContacts.getContacts(
            withProperties: true, withPhoto: false);
      }
    } catch (_) {}
    _contactsLoading = false;
  }

  Future _openContactsScreen() async {
    if (_cachedContacts.isEmpty) await _preloadContacts();
    final regMap = {};
    for (var u in _users) {
      regMap[cleanEgyptianPhone(u['phone'].toString())] = u;
    }
    final matched = [];
    final others = [];
    final seen = {};
    for (final c in _cachedContacts) {
      for (final ph in c.phones) {
        final norm = cleanEgyptianPhone(ph.number);
        if (norm.isEmpty ||
            norm == w.currentUserPhone ||
            seen.containsKey(norm)) {
          continue;
        }
        seen[norm] = true;
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
              myPhone: w.currentUserPhone,
              matched: matched,
              allContacts: others)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EG MASR • المحادثات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_pin),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                      userPhone: w.currentUserPhone, isMe: true)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
                            builder: (_) =>
                                UserProfileScreen(userPhone: ph, isMe: false)),
                      ),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF006A4E),
                        backgroundImage: avatar.startsWith('http')
                            ? NetworkImage(avatar)
                            : null,
                        child: !avatar.startsWith('http')
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                    ),
                    title: Text(u['full_name'] ?? ph,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(ph,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF006A4E),
        foregroundColor: Colors.white,
        onPressed: _openContactsScreen,
        child: const Icon(Icons.message),
      ),
    );
  }
}

class FullContactsScreen extends StatefulWidget {
  final String myPhone;
  final List matched;
  final List allContacts;
  const FullContactsScreen(
      {super.key,
      required this.myPhone,
      required this.matched,
      required this.allContacts});
  @override
  State createState() => _FullContactsScreenState();
}

class _FullContactsScreenState extends State {
  String _query = '';
  FullContactsScreen get w => widget as FullContactsScreen;

  @override
  Widget build(BuildContext context) {
    final filteredMatched = w.matched
        .where((m) =>
            m['name'].toString().toLowerCase().contains(_query) ||
            m['phone'].toString().contains(_query))
        .toList();
    final filteredOthers = w.allContacts
        .where((c) =>
            c['name'].toString().toLowerCase().contains(_query) ||
            c['phone'].toString().contains(_query))
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
                hintText: 'بحث سريع بالاسم أو الرقم...',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ...filteredMatched.map((m) => ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: Color(0xFF006A4E),
                          child: Icon(Icons.person, color: Colors.white)),
                      title: Text(m['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(m['phone'].toString()),
                      onTap: () {
                        final list = [w.myPhone, m['phone'].toString()]..sort();
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatsAppChatRoomScreen(
                              myPhone: w.myPhone,
                              roomId: '${list[0]}_${list[1]}',
                              peerPhone: m['phone'].toString(),
                              title: m['name'].toString(),
                              peerAvatar: (m['avatar'] ?? '').toString(),
                            ),
                          ),
                        );
                      },
                    )),
                ...filteredOthers.take(150).map((c) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone)),
                      title: Text(c['name'].toString()),
                      subtitle: Text(c['phone'].toString()),
                      trailing: TextButton(
                        onPressed: () => launchUrl(Uri.parse(
                            'sms:${c['phone']}?body=انضم لتطبيق EG MASR')),
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

class _WhatsAppChatRoomScreenState extends State {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _playingUrl;
  late final Stream _messagesStream;
  WhatsAppChatRoomScreen get w => widget as WhatsAppChatRoomScreen;

  @override
  void initState() {
    super.initState();
    _messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', w.roomId)
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

  Future _uploadMedia(List bytes, String ext) async {
    final fileName =
        'chat_${w.myPhone}_${DateTime.now().millisecondsSinceEpoch}.$ext';
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

  Future _sendMessage(String text,
      {String type = 'text', String mediaUrl = ''}) async {
    if (text.trim().isEmpty && mediaUrl.isEmpty) return;
    _msgCtrl.clear();
    try {
      await supabase.from('messages').insert({
        'room_id': w.roomId,
        'sender_phone': w.myPhone,
        'receiver_phone': w.peerPhone,
        'content': text.trim(),
        'msg_type': type,
        'media_url': mediaUrl,
      });
    } catch (_) {}
  }

  Future _pickAndSendImage(ImageSource src) async {
    final img =
        await ImagePicker().pickImage(source: src, imageQuality: 75);
    if (img == null) return;
    final url = await _uploadMedia(await img.readAsBytes(), 'jpg');
    if (url.toString().isNotEmpty) {
      await _sendMessage('صورة', type: 'image', mediaUrl: url.toString());
    }
  }

  Future _pickAndSendVideo() async {
    final vid = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (vid == null) return;
    final url = await _uploadMedia(await vid.readAsBytes(), 'mp4');
    if (url.toString().isNotEmpty) {
      await _sendMessage('فيديو', type: 'video', mediaUrl: url.toString());
    }
  }

  Future _sendHighAccuracyLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.best));
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
      await _sendMessage('موقعي المباشر GPS:\n$mapsUrl', type: 'location');
    } catch (_) {}
  }

  Future _toggleVoiceRecording() async {
    try {
      if (_isRecording) {
        final path = await _recorder.stop();
        setState(() => _isRecording = false);
        if (path != null && await File(path).exists()) {
          final url = await _uploadMedia(await File(path).readAsBytes(), 'm4a');
          if (url.toString().isNotEmpty) {
            await _sendMessage('رسالة صوتية',
                type: 'audio', mediaUrl: url.toString());
          }
        }
      } else if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        await _recorder.start(const RecordConfig(),
            path: '${dir.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a');
        setState(() => _isRecording = true);
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
        title: Text('تحويل أموال إلى ${w.title}'),
        content: TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المبلغ (ج.م)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (amt <= 0) return;
              Navigator.pop(ctx);
              await _transferFunds(
                  w.myPhone, w.peerPhone, amt, 'تحويل داخل المحادثة');
              await _sendMessage('تم تحويل مبلغ $amt ج.م إلى محفظتك بنجاح',
                  type: 'money');
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          children: [
            IconButton(
                icon: const Icon(Icons.photo, size: 32, color: Colors.purple),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage(ImageSource.gallery);
                }),
            IconButton(
                icon: const Icon(Icons.videocam, size: 32, color: Colors.orange),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickAndSendVideo();
                }),
            IconButton(
                icon:
                    const Icon(Icons.location_on, size: 32, color: Colors.green),
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendHighAccuracyLocation();
                }),
            IconButton(
                icon: const Icon(Icons.payments,
                    size: 32, color: Color(0xFFD4AF37)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openInChatMoneyTransfer();
                }),
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
        title: Text(w.title),
        actions: [
          IconButton(
              icon: const Icon(Icons.payments),
              onPressed: _openInChatMoneyTransfer)
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data as List;
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    final isMe = m['sender_phone'] == w.myPhone;
                    final content = (m['content'] ?? '').toString();
                    final type = (m['msg_type'] ?? 'text').toString();
                    final mediaUrl = (m['media_url'] ?? '').toString();
                    final isUrl = content.contains('http');
                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (type == 'image' && mediaUrl.startsWith('http'))
                              Image.network(mediaUrl, width: 200)
                            else if (type == 'video' &&
                                mediaUrl.startsWith('http'))
                              ElevatedButton(
                                  onPressed: () => launchUrl(
                                      Uri.parse(mediaUrl),
                                      mode: LaunchMode.externalApplication),
                                  child: const Text('تشغيل الفيديو'))
                            else if (type == 'audio' &&
                                mediaUrl.startsWith('http'))
                              IconButton(
                                icon: Icon(_playingUrl == mediaUrl
                                    ? Icons.stop
                                    : Icons.play_arrow),
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
                              )
                            else
                              InkWell(
                                onTap: isUrl
                                    ? () {
                                        final idx = content.indexOf('http');
                                        if (idx >= 0) {
                                          launchUrl(
                                              Uri.parse(content
                                                  .substring(idx)
                                                  .split(' ')
                                                  .first),
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      }
                                    : null,
                                child: Text(content,
                                    style: TextStyle(
                                        color: isUrl
                                            ? Colors.blue
                                            : Colors.black87)),
                              ),
                            if (isMe)
                              const Icon(Icons.done_all,
                                  size: 14, color: Colors.blue),
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
                IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _showAttachmentSheet),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: _isRecording ? 'جاري التسجيل...' : 'رسالة...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (v) => _sendMessage(v),
                  ),
                ),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic,
                      color:
                          _isRecording ? Colors.red : const Color(0xFF006A4E)),
                  onPressed: _toggleVoiceRecording,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF006A4E)),
                  onPressed: () => _sendMessage(_msgCtrl.text),
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

class _UserProfileScreenState extends State {
  Map? _profile;
  List _userPosts = [];
  bool _loading = true;
  UserProfileScreen get w => widget as UserProfileScreen;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future _loadProfile() async {
    try {
      final prof = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.userPhone)
          .maybeSingle();
      final posts = await supabase
          .from('posts')
          .select()
          .eq('author_phone', w.userPhone)
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

  Future _changePhoto() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final fileName =
        'avatar_${w.userPhone}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await supabase.storage.from('avatars').uploadBinary(fileName, bytes,
          fileOptions: const FileOptions(upsert: true));
      final url = supabase.storage.from('avatars').getPublicUrl(fileName);
      await supabase
          .from('profiles')
          .update({'avatar_url': url}).eq('phone', w.userPhone);
      _loadProfile();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['full_name'] ?? w.userPhone;
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
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF006A4E),
                        backgroundImage: avatar.startsWith('http')
                            ? NetworkImage(avatar)
                            : null,
                        child: !avatar.startsWith('http')
                            ? const Icon(Icons.person,
                                size: 50, color: Colors.white)
                            : null,
                      ),
                      if (w.isMe)
                        TextButton.icon(
                            onPressed: _changePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('تغيير الصورة الشخصية')),
                      Text(name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(w.userPhone,
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                ..._userPosts.map((p) => Card(
                      margin: const EdgeInsets.all(10),
                      child: ListTile(
                        title: Text(p['content'] ?? ''),
                        subtitle: (p['media_url'] ?? '')
                                .toString()
                                .startsWith('http')
                            ? Image.network(p['media_url'])
                            : null,
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

class _SocialFeedTabState extends State {
  List _posts = [];
  Map _avatars = {};
  String _myName = 'مستخدم EG Masr';
  String _myAvatar = '';
  bool _loading = true;
  SocialFeedTab get w => widget as SocialFeedTab;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future _loadFeed() async {
    try {
      final profs = await supabase.from('profiles').select();
      final avMap = {};
      for (var pr in profs) {
        avMap[pr['phone'].toString()] = (pr['avatar_url'] ?? '').toString();
        if (pr['phone'] == w.currentUserPhone) {
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
          _avatars = avMap;
          _posts = List.from(allPosts);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _uploadFile(XFile file, String ext) async {
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('منشور جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(hintText: 'بم تفكر؟...')),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final img = await ImagePicker().pickImage(
                        source: ImageSource.gallery, imageQuality: 75);
                    if (img != null) {
                      final u = await _uploadFile(img, 'jpg');
                      if (u.toString().isNotEmpty) {
                        uploadedUrl = u.toString();
                        mediaType = 'image';
                      }
                    }
                  },
                  icon: const Icon(Icons.image),
                  label: const Text('صورة'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final vid = await ImagePicker()
                        .pickVideo(source: ImageSource.gallery);
                    if (vid != null) {
                      final u = await _uploadFile(vid, 'mp4');
                      if (u.toString().isNotEmpty) {
                        uploadedUrl = u.toString();
                        mediaType = 'video';
                      }
                    }
                  },
                  icon: const Icon(Icons.video_library),
                  label: const Text('فيديو'),
                ),
              ],
            ),
          ],
        ),
        actions: [
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EG MASR • الموجز'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                      userPhone: w.currentUserPhone, isMe: true)),
            ).then((_) => _loadFeed()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _posts.length + 1,
              itemBuilder: (_, idx) {
                if (idx == 0) {
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF006A4E),
                        backgroundImage: _myAvatar.startsWith('http')
                            ? NetworkImage(_myAvatar)
                            : null,
                        child: !_myAvatar.startsWith('http')
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      title: const Text('بم تفكر؟ اضغط للنشر...'),
                      onTap: _openCreatePostDialog,
                    ),
                  );
                }
                final p = _posts[idx - 1];
                final authorPhone = (p['author_phone'] ?? '').toString();
                final av = (_avatars[authorPhone] ?? '').toString();
                final mediaUrl = (p['media_url'] ?? '').toString();
                final likes = List.from(p['likes'] ?? []);
                return Card(
                  margin: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF006A4E),
                          backgroundImage:
                              av.startsWith('http') ? NetworkImage(av) : null,
                          child: !av.startsWith('http')
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        title: Text(p['author_name'] ?? authorPhone,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => UserProfileScreen(
                                  userPhone: authorPhone,
                                  isMe: authorPhone == w.currentUserPhone)),
                        ),
                      ),
                      if ((p['content'] ?? '').toString().isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(p['content'])),
                      if (p['media_type'] == 'image' &&
                          mediaUrl.startsWith('http'))
                        Image.network(mediaUrl, width: double.infinity),
                      if (p['media_type'] == 'video' &&
                          mediaUrl.startsWith('http'))
                        ElevatedButton(
                            onPressed: () => launchUrl(Uri.parse(mediaUrl),
                                mode: LaunchMode.externalApplication),
                            child: const Text('تشغيل الفيديو')),
                      TextButton.icon(
                        onPressed: () async {
                          if (likes.contains(w.currentUserPhone)) {
                            likes.remove(w.currentUserPhone);
                          } else {
                            likes.add(w.currentUserPhone);
                          }
                          await supabase.from('posts').update(
                              {'likes': likes}).eq('id', p['id']);
                          _loadFeed();
                        },
                        icon: const Icon(Icons.thumb_up),
                        label: Text('أعجبني (${likes.length})'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class DirectPayAndQrTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  final bool isCorporate;
  const DirectPayAndQrTab(
      {super.key,
      required this.currentUserPhone,
      required this.isAdmin,
      required this.isCorporate});
  @override
  State createState() => _DirectPayAndQrTabState();
}

class _DirectPayAndQrTabState extends State {
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
    String? savedQr = prefs.getString('unique_qr_v2_${w.currentUserPhone}');
    if (savedQr == null || savedQr.isEmpty) {
      savedQr =
          SecurityShield.generateUniqueQr(w.currentUserPhone, w.isCorporate);
      await prefs.setString('unique_qr_v2_${w.currentUserPhone}', savedQr);
    }
    try {
      final prof = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.currentUserPhone)
          .maybeSingle();
      if (prof != null) _egMasrBalance = (prof['balance'] ?? 0).toDouble();
    } catch (_) {}
    if (mounted) setState(() => _uniqueQrToken = savedQr!);
  }

  void _openSendMoneyDialog({String initialTarget = ''}) {
    final targetCtrl = TextEditingController(text: initialTarget);
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل أموال لأي محفظة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: targetCtrl,
                decoration: const InputDecoration(
                    labelText: 'رقم المحفظة المستلمة أو كود QR')),
            TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ (ج.م)')),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              final raw = targetCtrl.text.trim();
              if (amt <= 0 || raw.isEmpty) return;
              Navigator.pop(ctx);
              String targetPhone = raw;
              if (raw.startsWith('EGMASR-')) {
                final parts = raw.split('-');
                if (parts.length >= 3) targetPhone = parts[2];
              }
              await _transferFunds(
                  w.currentUserPhone, targetPhone, amt, 'تحويل مالي');
              _initData();
            },
            child: const Text('تأكيد التحويل'),
          ),
        ],
      ),
    );
  }

  void _openQrScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('امسح الباركود للدفع')),
          body: MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null && code.isNotEmpty) {
                Navigator.pop(ctx);
                _openSendMoneyDialog(initialTarget: code);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحفظة والباركود الفريد'),
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
          Card(
            color: const Color(0xFF006A4E),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('رصيد محفظتك: $_egMasrBalance ج.م',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openQrScanner,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('امسح باركود'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openSendMoneyDialog(),
                          icon: const Icon(Icons.send),
                          label: const Text('تحويل أموال'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('الباركود المالي الفريد الخاص بحسابك فقط',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_uniqueQrToken.isNotEmpty)
                    QrImageView(data: _uniqueQrToken, size: 180),
                  SelectableText(_uniqueQrToken,
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
      appBar: AppBar(title: const Text('اعتماد الشركات')),
      body: ListView.builder(
        itemCount: _companies.length,
        itemBuilder: (_, i) {
          final c = _companies[i];
          return ListTile(
            title: Text(c['company_name'] ?? ''),
            subtitle: Text('${c['phone']} - ${c['status']}'),
            trailing: IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () async {
                await supabase
                    .from('companies')
                    .update({'status': 'approved'}).eq('id', c['id']);
                _load();
              },
            ),
          );
        },
      ),
    );
  }
}

class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool canAccessBus;
  const ServicesTab(
      {super.key, required this.currentUserPhone, required this.canAccessBus});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المشاوير والتوصيل والخدمات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006A4E),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RideAndCargoScreen(
                      customerPhone: currentUserPhone, initialMode: 'ride')),
            ),
            icon: const Icon(Icons.local_taxi),
            label: const Text('اطلب مشوار (ملاكي / موتوسيكل)'),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 52)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RideAndCargoScreen(
                      customerPhone: currentUserPhone, initialMode: 'cargo')),
            ),
            icon: const Icon(Icons.local_shipping),
            label: const Text('نقل بضائع (ربع نقل / جامبو باتفاق)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CaptainPortalScreen(captainPhone: currentUserPhone)),
            ),
            icon: const Icon(Icons.badge),
            label: const Text('بوابة الكابتن'),
          ),
          if (canAccessBus) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D38),
                  foregroundColor: const Color(0xFFD4AF37),
                  minimumSize: const Size(double.infinity, 54)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CorporateBusTrackerScreen(
                        companyPhone: currentUserPhone)),
              ),
              icon: const Icon(Icons.directions_bus),
              label: const Text('تابع الباص (للشركات والإدارة)'),
            ),
          ],
        ],
      ),
    );
  }
}

class RideAndCargoScreen extends StatefulWidget {
  final String customerPhone;
  final String initialMode;
  const RideAndCargoScreen(
      {super.key, required this.customerPhone, required this.initialMode});
  @override
  State createState() => _RideAndCargoScreenState();
}

class _RideAndCargoScreenState extends State {
  String _vehicle = 'car';
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _offerPriceCtrl = TextEditingController();
  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;
  double _distanceKm = 0.0;
  RideAndCargoScreen get w => widget as RideAndCargoScreen;

  @override
  void initState() {
    super.initState();
    _vehicle = w.initialMode == 'cargo' ? 'quarter_truck' : 'car';
    _detectPickup();
  }

  Future _detectPickup() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.best));
      _pickupLat = pos.latitude;
      _pickupLng = pos.longitude;
      String addr =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          addr =
              '${marks.first.street ?? ''}, ${marks.first.subLocality ?? ''}, ${marks.first.locality ?? ''}';
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _pickupCtrl.text = addr);
        _calcDistance();
      }
    } catch (_) {}
  }

  Future _resolveDropoff() async {
    final dest = _dropoffCtrl.text.trim();
    if (dest.isEmpty) return;
    try {
      final locs = await locationFromAddress('$dest, Egypt');
      if (locs.isNotEmpty) {
        _dropoffLat = locs.first.latitude;
        _dropoffLng = locs.first.longitude;
        _calcDistance();
      }
    } catch (_) {}
  }

  void _calcDistance() {
    if (_pickupLat != null &&
        _pickupLng != null &&
        _dropoffLat != null &&
        _dropoffLng != null) {
      final m = Geolocator.distanceBetween(
          _pickupLat!, _pickupLng!, _dropoffLat!, _dropoffLng!);
      final km = (m / 1000.0) * 1.25;
      setState(() => _distanceKm = km < 0.5 ? 1.0 : km);
    }
  }

  double _calcPrice() {
    if (_distanceKm <= 0) return 0.0;
    if (_vehicle == 'motorcycle') return 12.0 + (_distanceKm * 4.5);
    if (_vehicle == 'car') return 20.0 + (_distanceKm * 8.0);
    return double.tryParse(_offerPriceCtrl.text.trim()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final isCargo = _vehicle == 'quarter_truck' || _vehicle == 'jumbo_truck';
    final price = _calcPrice();
    return Scaffold(
      appBar: AppBar(title: const Text('طلب رحلة أو نقل')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                  label: const Text('موتوسيكل'),
                  selected: _vehicle == 'motorcycle',
                  onSelected: (_) => setState(() => _vehicle = 'motorcycle')),
              ChoiceChip(
                  label: const Text('ملاكي'),
                  selected: _vehicle == 'car',
                  onSelected: (_) => setState(() => _vehicle = 'car')),
              ChoiceChip(
                  label: const Text('ربع نقل (باتفاق)'),
                  selected: _vehicle == 'quarter_truck',
                  onSelected: (_) =>
                      setState(() => _vehicle = 'quarter_truck')),
              ChoiceChip(
                  label: const Text('جامبو (باتفاق)'),
                  selected: _vehicle == 'jumbo_truck',
                  onSelected: (_) => setState(() => _vehicle = 'jumbo_truck')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pickupCtrl,
            decoration: InputDecoration(
              labelText: 'موقعك الحالي GPS',
              suffixIcon: IconButton(
                  icon: const Icon(Icons.my_location),
                  onPressed: _detectPickup),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dropoffCtrl,
            onChanged: (_) => _resolveDropoff(),
            decoration: const InputDecoration(
                labelText: 'المكان اللي عاوز توصله'),
          ),
          const SizedBox(height: 14),
          if (_distanceKm > 0)
            Card(
              color: const Color(0xFFE8F5E9),
              child: ListTile(
                title: Text('المسافة: ${_distanceKm.toStringAsFixed(1)} كم',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(
                  isCargo
                      ? 'التسعيرة: باتفاق'
                      : '${price.toStringAsFixed(1)} ج.م',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF006A4E)),
                ),
              ),
            ),
          if (isCargo)
            TextField(
              controller: _offerPriceCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'السعر المقترح للاتفاق (ج.م)'),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006A4E),
                foregroundColor: Colors.white),
            onPressed: () async {
              if (_pickupCtrl.text.isEmpty || _dropoffCtrl.text.isEmpty) return;
              await supabase.from('delivery_orders').insert({
                'order_code': 'EGM-${Random().nextInt(89999) + 10000}',
                'customer_phone': w.customerPhone,
                'service_type': isCargo ? 'cargo' : 'ride',
                'vehicle_type': _vehicle,
                'pickup_location': _pickupCtrl.text.trim(),
                'dropoff_location': _dropoffCtrl.text.trim(),
                'details': 'المسافة: ${_distanceKm.toStringAsFixed(1)} كم',
                'price': price,
                'status': 'searching',
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text('تأكيد الطلب الآن'),
          ),
        ],
      ),
    );
  }
}

class CaptainPortalScreen extends StatefulWidget {
  final String captainPhone;
  const CaptainPortalScreen({super.key, required this.captainPhone});
  @override
  State createState() => _CaptainPortalScreenState();
}

class _CaptainPortalScreenState extends State {
  List _orders = [];
  CaptainPortalScreen get w => widget as CaptainPortalScreen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future _load() async {
    final ords = await supabase
        .from('delivery_orders')
        .select()
        .order('created_at', ascending: false);
    if (mounted) setState(() => _orders = List.from(ords));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بوابة الكابتن')),
      body: ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final o = _orders[i];
          return ListTile(
            title: Text('${o['order_code']} • ${o['price']} ج.م'),
            subtitle:
                Text('${o['pickup_location']} -> ${o['dropoff_location']}'),
            trailing: ElevatedButton(
              onPressed: () async {
                await supabase.from('delivery_orders').update({
                  'captain_phone': w.captainPhone,
                  'status': 'on_the_way',
                }).eq('id', o['id']);
                _load();
              },
              child: const Text('قبول'),
            ),
          );
        },
      ),
    );
  }
}

class CorporateBusTrackerScreen extends StatefulWidget {
  final String companyPhone;
  const CorporateBusTrackerScreen({super.key, required this.companyPhone});
  @override
  State createState() => _CorporateBusTrackerScreenState();
}

class _CorporateBusTrackerScreenState extends State {
  List _buses = [];
  CorporateBusTrackerScreen get w => widget as CorporateBusTrackerScreen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future _load() async {
    final res = await supabase
        .from('company_buses')
        .select()
        .eq('company_phone', w.companyPhone);
    if (mounted) setState(() => _buses = List.from(res));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تابع الباص')),
      body: ListView.builder(
        itemCount: _buses.length,
        itemBuilder: (_, i) {
          final b = _buses[i];
          return ListTile(
            leading: const Icon(Icons.directions_bus),
            title: Text(b['bus_name'] ?? ''),
            subtitle: Text(b['route_name'] ?? ''),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await supabase.from('company_buses').insert({
            'company_phone': w.companyPhone,
            'bus_name': 'باص الشركة ${_buses.length + 1}',
            'route_name': 'الدائري - مقر الشركة',
          });
          _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
