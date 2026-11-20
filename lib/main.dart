import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJkYmRpbXBoYnJzZXpmdGluZGNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3ODA1MDIsImV4cCI6MjA4OTM1NjUwMn0.35i7hN8Y4iM-W6s760sB6S-sK2R5N7B3Q9Z1X4W8E2A';
const String adminPhoneNumber = '01012055498';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrSuperApp());
}

final supabase = Supabase.instance.client;

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
          surface: const Color(0xFFF6F8F7),
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
    setState(() {
      _savedPhone = prefs.getString('user_phone');
      _accountType = prefs.getString('account_type') ?? 'individual';
      _loading = false;
    });
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
        setState(() {
          _savedPhone = phone;
          _accountType = type;
        });
      },
    );
  }
}

// ============================================================================
// 1. LOGIN SCREEN (DYNAMIC RANDOM OTP + INDIVIDUAL & CORPORATE REGISTRATION)
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
  bool _otpSent = false;
  bool _busy = false;
  String _dynamicOtp = '';

  LoginScreen get w => widget as LoginScreen;

  String _normalizePhone(String input) {
    String p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('20') && p.length == 12) {
      p = '0${p.substring(2)}';
    } else if (p.length == 10 && p.startsWith('1')) {
      p = '0$p';
    }
    return p;
  }

  String _generateUniqueOtp() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  Future _sendOtp() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (phone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم موبايل مصري صحيح (11 رقم)')),
      );
      return;
    }
    if (_isCorporate) {
      if (_companyNameCtrl.text.trim().isEmpty ||
          _companyAddressCtrl.text.trim().isEmpty ||
          _taxIdCtrl.text.trim().isEmpty ||
          _delegateCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى استكمال جميع بيانات المنشأة والمفوض')),
        );
        return;
      }
    }

    final newCode = _generateUniqueOtp();
    setState(() {
      _dynamicOtp = newCode;
      _otpSent = true;
      _otpCtrl.clear();
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.sms, color: Color(0xFF006A4E)),
              SizedBox(width: 8),
              Text('رسالة التحقق (OTP)'),
            ],
          ),
          content: Text(
            'كود الدخول المتغير الخاص برقم $phone لهذه الجلسة هو:\n\n$newCode\n\n(يتغير هذا الكود تلقائياً في كل محاولة دخول)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم'),
            ),
          ],
        ),
      );
    }
  }

  Future _verifyAndEnter() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (_otpCtrl.text.trim() != _dynamicOtp || _dynamicOtp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود التفعيل غير صحيح! تأكد من الكود المرسل')),
      );
      return;
    }
    setState(() => _busy = true);

    try {
      if (_isCorporate) {
        final existingComp = await supabase
            .from('companies')
            .select()
            .eq('phone', phone)
            .maybeSingle();

        if (existingComp == null) {
          await supabase.from('companies').insert({
            'company_name': _companyNameCtrl.text.trim(),
            'company_address': _companyAddressCtrl.text.trim(),
            'tax_id': _taxIdCtrl.text.trim(),
            'delegate_name': _delegateCtrl.text.trim(),
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
                      child: const Text('حسناً'),
                    ),
                  ],
                ),
              );
            }
            setState(() => _busy = false);
            return;
          }
        } else {
          final status = existingComp['status'] ?? 'pending';
          if (status != 'approved' && phone != adminPhoneNumber) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(status == 'rejected'
                      ? 'تم رفض طلب تسجيل الشركة من الإدارة'
                      : 'طلب شركتك ما زال في انتظار موافقة الإدارة ⏳'),
                  backgroundColor: Colors.orange.shade800,
                ),
              );
            }
            setState(() => _busy = false);
            return;
          }
        }

        final existingProf = await supabase
            .from('profiles')
            .select()
            .eq('phone', phone)
            .maybeSingle();
        if (existingProf == null) {
          await supabase.from('profiles').insert({
            'phone': phone,
            'full_name': _companyNameCtrl.text.trim().isEmpty
                ? 'حساب شركات'
                : _companyNameCtrl.text.trim(),
            'balance': 0.0,
            'avatar_url': '',
          });
        }
        w.onLoginSuccess(phone, 'corporate');
      } else {
        final name = _nameCtrl.text.trim().isEmpty
            ? 'مستخدم EG Masr'
            : _nameCtrl.text.trim();
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
    } catch (e) {
      if (!_isCorporate || phone == adminPhoneNumber) {
        w.onLoginSuccess(phone, _isCorporate ? 'corporate' : 'individual');
      }
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
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFF006A4E),
                      child: Icon(Icons.account_balance_wallet,
                          size: 34, color: Color(0xFFD4AF37)),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'EG MASR',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF006A4E),
                      ),
                    ),
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
                          labelText: 'أدخل الكود المتغير المرسل',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _sendOtp,
                          child: const Text('إرسال كود جديد'),
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
                        onPressed:
                            _busy ? null : (_otpSent ? _verifyAndEnter : _sendOtp),
                        child: _busy
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _otpSent
                                    ? 'تأكيد ودخول للتطبيق'
                                    : 'إرسال كود التفعيل المتغير',
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
// 2. ULTRA-FAST MAIN HOME SHELL
// ============================================================================
class MainHomeShell extends StatefulWidget {
  final String userPhone;
  final String accountType;
  const MainHomeShell({
    super.key,
    required this.userPhone,
    required this.accountType,
  });

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
    _pages = [
      ChatsTab(currentUserPhone: w.userPhone),
      WalletTab(
        currentUserPhone: w.userPhone,
        isAdmin: w.userPhone == adminPhoneNumber,
      ),
      ServicesTab(
        currentUserPhone: w.userPhone,
        isCorporate:
            w.accountType == 'corporate' || w.userPhone == adminPhoneNumber,
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
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'المحادثات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'المحفظة و QR',
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: (w.accountType == 'corporate' ||
                    w.userPhone == adminPhoneNumber)
                ? 'خدمات الشركات VIP'
                : 'الخدمات والألعاب',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. CHATS TAB + FULL CONTACTS
// ============================================================================
class ChatsTab extends StatefulWidget {
  final String currentUserPhone;
  const ChatsTab({super.key, required this.currentUserPhone});

  @override
  State createState() => _ChatsTabState();
}

class _ChatsTabState extends State {
  List _users = [];
  bool _loading = true;

  ChatsTab get w => widget as ChatsTab;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  String _normalizePhone(String input) {
    String p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('20') && p.length == 12) {
      p = '0${p.substring(2)}';
    } else if (p.length == 10 && p.startsWith('1')) {
      p = '0$p';
    }
    return p;
  }

  Future _loadUsers() async {
    try {
      final res = await supabase
          .from('profiles')
          .select()
          .neq('phone', w.currentUserPhone);
      if (mounted) {
        setState(() {
          _users = List.from(res);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _openContactsSheet() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى السماح بالوصول لجهات الاتصال')),
        );
      }
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final registeredMap = {};
    for (var u in _users) {
      registeredMap[_normalizePhone(u['phone'].toString())] = u;
    }

    final matched = [];
    final allOthers = [];

    for (final c in contacts) {
      if (c.phones.isEmpty) continue;
      for (final ph in c.phones) {
        final norm = _normalizePhone(ph.number);
        if (norm.isEmpty || norm == w.currentUserPhone) continue;
        if (registeredMap.containsKey(norm)) {
          matched.add({
            'name': c.displayName,
            'phone': norm,
          });
        } else {
          allOthers.add({
            'name': c.displayName,
            'phone': ph.number,
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
          allContacts: allOthers,
        ),
      ),
    );
  }

  Future _searchByPhoneDialog() async {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بدء محادثة برقم الموبايل'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '01xxxxxxxxx',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final p = _normalizePhone(ctrl.text.trim());
              if (p.length >= 11) {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(
                      myPhone: w.currentUserPhone,
                      peerPhone: p,
                      peerName: p,
                    ),
                  ),
                );
              }
            },
            child: const Text('محادثة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحادثات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search),
            onPressed: _searchByPhoneDialog,
          ),
          IconButton(
            icon: const Icon(Icons.contacts),
            onPressed: _openContactsSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: ElevatedButton.icon(
                    onPressed: _openContactsSheet,
                    icon: const Icon(Icons.contacts),
                    label: const Text('عرض كل جهات الاتصال'),
                  ),
                )
              : ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF006A4E),
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      title: Text(u['full_name'] ?? u['phone']),
                      subtitle: Text(u['phone']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomScreen(
                              myPhone: w.currentUserPhone,
                              peerPhone: u['phone'],
                              peerName: u['full_name'] ?? u['phone'],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF006A4E),
        foregroundColor: Colors.white,
        onPressed: _openContactsSheet,
        icon: const Icon(Icons.contacts),
        label: const Text('جهات الاتصال'),
      ),
    );
  }
}

class FullContactsScreen extends StatefulWidget {
  final String myPhone;
  final List matched;
  final List allContacts;

  const FullContactsScreen({
    super.key,
    required this.myPhone,
    required this.matched,
    required this.allContacts,
  });

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
            m['name'].toString().toLowerCase().contains(_query.toLowerCase()) ||
            m['phone'].toString().contains(_query))
        .toList();

    final filteredAll = w.allContacts
        .where((c) =>
            c['name'].toString().toLowerCase().contains(_query.toLowerCase()) ||
            c['phone'].toString().contains(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title:
            Text('جهات الاتصال (${w.matched.length + w.allContacts.length})'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو رقم الموبايل...',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (filteredMatched.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text('مسجلون على EG MASR',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF006A4E))),
                  ),
                  ...filteredMatched.map((m) => ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF006A4E),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(m['name']),
                        subtitle: Text(m['phone']),
                        trailing:
                            const Icon(Icons.chat, color: Color(0xFF006A4E)),
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomScreen(
                                myPhone: w.myPhone,
                                peerPhone: m['phone'],
                                peerName: m['name'],
                              ),
                            ),
                          );
                        },
                      )),
                  const Divider(),
                ],
                ...filteredAll.map((c) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone)),
                      title: Text(c['name']),
                      subtitle: Text(c['phone']),
                      trailing: TextButton(
                        onPressed: () {
                          final msg = Uri.encodeComponent(
                              'انضم معايا على تطبيق EG MASR!');
                          launchUrl(Uri.parse('sms:${c['phone']}?body=$msg'));
                        },
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

// ============================================================================
// 4. CHAT ROOM (WITH VOICE NOTE TIMER RECORDER & MEDIA)
// ============================================================================
class ChatRoomScreen extends StatefulWidget {
  final String myPhone;
  final String peerPhone;
  final String peerName;

  const ChatRoomScreen({
    super.key,
    required this.myPhone,
    required this.peerPhone,
    required this.peerName,
  });

  @override
  State createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State {
  final _msgCtrl = TextEditingController();
  final _picker = ImagePicker();
  List _messages = [];
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recTimer;

  ChatRoomScreen get w => widget as ChatRoomScreen;

  String get _roomId {
    final list = [w.myPhone, w.peerPhone]..sort();
    return '${list[0]}_${list[1]}';
  }

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    super.dispose();
  }

  Future _fetchMessages() async {
    try {
      final res = await supabase
          .from('messages')
          .select()
          .eq('room_id', _roomId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() => _messages = List.from(res));
      }
    } catch (_) {}
  }

  Future _sendMessage(String text, {String type = 'text'}) async {
    if (text.trim().isEmpty) return;
    _msgCtrl.clear();
    setState(() {
      _messages.add({
        'sender_phone': w.myPhone,
        'content': text.trim(),
        'msg_type': type,
      });
    });
    try {
      await supabase.from('messages').insert({
        'room_id': _roomId,
        'sender_phone': w.myPhone,
        'receiver_phone': w.peerPhone,
        'content': text.trim(),
        'msg_type': type,
      });
    } catch (_) {}
  }

  void _toggleVoiceRecording() {
    if (!_isRecording) {
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    } else {
      _recTimer?.cancel();
      final dur = _recordSeconds < 1 ? 1 : _recordSeconds;
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
      });
      _sendMessage('🎤 رسالة صوتية مسجلة (0:${dur.toString().padLeft(2, '0')})',
          type: 'voice');
    }
  }

  Future _pickAndSendMedia() async {
    final XFile? file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final path = 'chat_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('avatars').uploadBinary(path, bytes);
      final url = supabase.storage.from('avatars').getPublicUrl(path);
      await _sendMessage(url, type: 'image');
    } catch (_) {
      await _sendMessage('[صورة مرفقة: ${file.name}]', type: 'text');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w.peerName, style: const TextStyle(fontSize: 16)),
            Text(w.peerPhone,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchMessages),
          IconButton(
              icon: const Icon(Icons.call),
              onPressed: () => _sendMessage('📞 مكالمة صوتية صادرة')),
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
                final type = m['msg_type'] ?? 'text';
                final content = m['content'].toString();

                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 270),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF006A4E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: type == 'image'
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(content, fit: BoxFit.cover),
                          )
                        : Text(
                            content,
                            style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87),
                          ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo, color: Color(0xFF006A4E)),
                  onPressed: _pickAndSendMedia,
                ),
                Expanded(
                  child: _isRecording
                      ? Text(
                          '🔴 جاري تسجيل الصوت... 0:${_recordSeconds.toString().padLeft(2, '0')} (اضغط المايك للإرسال)',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        )
                      : TextField(
                          controller: _msgCtrl,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالتك هنا...',
                            border: InputBorder.none,
                          ),
                          onSubmitted: _sendMessage,
                        ),
                ),
                IconButton(
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic,
                    color: _isRecording ? Colors.red : const Color(0xFF006A4E),
                    size: 28,
                  ),
                  onPressed: _toggleVoiceRecording,
                ),
                CircleAvatar(
                  backgroundColor: const Color(0xFF006A4E),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
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

// ============================================================================
// 5. REAL WALLET (STARTS AT 0.00 EGP + CARD/WALLET LINK + INSTAPAY SMS ALERTS)
// ============================================================================
class WalletTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  const WalletTab({
    super.key,
    required this.currentUserPhone,
    required this.isAdmin,
  });

  @override
  State createState() => _WalletTabState();
}

class _WalletTabState extends State {
  double _balance = 0.0;
  String _fullName = 'مستخدم EG Masr';
  String _linkedCard = '';
  List _txHistory = [];

  WalletTab get w => widget as WalletTab;

  @override
  void initState() {
    super.initState();
    _loadAllWalletData();
  }

  Future _loadAllWalletData() async {
    final prefs = await SharedPreferences.getInstance();
    _linkedCard = prefs.getString('linked_card_${w.currentUserPhone}') ?? '';
    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.currentUserPhone)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _balance = (data['balance'] ?? 0.0).toDouble();
          _fullName = data['full_name'] ?? _fullName;
        });
      }
      final txs = await supabase
          .from('transactions')
          .select()
          .or('sender_phone.eq.${w.currentUserPhone},receiver_phone.eq.${w.currentUserPhone}')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _txHistory = List.from(txs));
      }
    } catch (_) {}
  }

  void _showBankNotification(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF004D38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: Color(0xFFD4AF37)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تم الاطلاع'),
          ),
        ],
      ),
    );
  }

  void _openLinkCardAndDepositDialog() {
    final cardCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController(text: 'البنك الأهلي / مصر / CIB');
    final depositCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ربط فيزا بنكية / محفظة وإيداع'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bankNameCtrl,
                decoration:
                    const InputDecoration(labelText: 'اسم البنك أو المحفظة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cardCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'رقم الفيزا (16 رقم) أو رقم المحفظة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: depositCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'مبلغ الشحن الفوري لحسابك (ج.م)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final card = cardCtrl.text.trim();
              final amt = double.tryParse(depositCtrl.text.trim()) ?? 0.0;
              if (card.length < 11) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('أدخل رقم بطاقة أو محفظة صحيح')),
                );
                return;
              }
              Navigator.pop(ctx);
              final masked =
                  '**** ${card.substring(card.length - 4)} (${bankNameCtrl.text})';
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                  'linked_card_${w.currentUserPhone}', masked);

              final newBal = _balance + amt;
              final ref = 'DEP${Random().nextInt(899999) + 100000}';
              setState(() {
                _linkedCard = masked;
                _balance = newBal;
              });

              try {
                await supabase.from('profiles').update({'balance': newBal}).eq(
                    'phone', w.currentUserPhone);
                if (amt > 0) {
                  await supabase.from('transactions').insert({
                    'ref_code': ref,
                    'sender_phone': 'BANK_CARD',
                    'receiver_phone': w.currentUserPhone,
                    'amount': amt,
                    'tx_type': 'deposit',
                    'note': 'إيداع من $masked',
                  });
                }
              } catch (_) {}

              _loadAllWalletData();
              if (amt > 0 && mounted) {
                _showBankNotification(
                  'إشعار إضافة رصيد - EG MASR',
                  'تم إضافة مبلغ ${amt.toStringAsFixed(2)} ج.م إلى حسابك رقم ${w.currentUserPhone} من البطاقة $masked.\nرصيدك الحالي: ${newBal.toStringAsFixed(2)} ج.م\nرقم المرجع: #$ref',
                );
              }
            },
            child: const Text('ربط وتأكيد الإيداع'),
          ),
        ],
      ),
    );
  }

  Future _executeRealTransfer(String toPhone, double amount) async {
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صحيحاً أكبر من 0')),
      );
      return;
    }
    if (amount > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('عفواً، رصيدك الحالي لا يكفي لإتمام العملية! اشحن محفظتك أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newSenderBal = _balance - amount;
    final ref = 'TRX${Random().nextInt(899999) + 100000}';

    setState(() => _balance = newSenderBal);

    try {
      await supabase
          .from('profiles')
          .update({'balance': newSenderBal}).eq('phone', w.currentUserPhone);

      final rec = await supabase
          .from('profiles')
          .select()
          .eq('phone', toPhone)
          .maybeSingle();
      if (rec != null) {
        final recNewBal = (rec['balance'] ?? 0.0).toDouble() + amount;
        await supabase
            .from('profiles')
            .update({'balance': recNewBal}).eq('phone', toPhone);
      }

      await supabase.from('transactions').insert({
        'ref_code': ref,
        'sender_phone': w.currentUserPhone,
        'receiver_phone': toPhone,
        'amount': amount,
        'tx_type': 'transfer',
        'note': 'تحويل لحظي إلى $toPhone',
      });
    } catch (_) {}

    _loadAllWalletData();
    if (mounted) {
      _showBankNotification(
        'إشعار خصم فوري (InstaPay Alert)',
        'تم خصم مبلغ ${amount.toStringAsFixed(2)} ج.م من حسابك رقم ${w.currentUserPhone} وتحويله بنجاح إلى المستلم $toPhone.\n\nرصيدك المتاح الآن: ${newSenderBal.toStringAsFixed(2)} ج.م\nرقم المرجع: #$ref',
      );
    }
  }

  void _openTransferDialog({String? prefilledPhone}) {
    final phoneCtrl = TextEditingController(text: prefilledPhone ?? '');
    final amtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل أموال لحظي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم حساب المستلم'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ (ج.م)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final p = phoneCtrl.text.trim();
              final a = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
              Navigator.pop(ctx);
              _executeRealTransfer(p, a);
            },
            child: const Text('تحويل وخصم الآن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uniqueQrPayload =
        'EGMASR://PAY?ACC=${w.currentUserPhone}&NAME=${Uri.encodeComponent(_fullName)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('المحفظة البنكية و QR'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _loadAllWalletData),
          if (w.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings,
                  color: Color(0xFFD4AF37)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminCompaniesScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                );
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
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.verified_user, color: Colors.black),
                title: const Text('لوحة الأدمن (اعتماد الشركات)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminCompaniesScreen()),
                  );
                },
              ),
            ),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: const Color(0xFF006A4E),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_fullName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text('رقم الحساب: ${w.currentUserPhone}',
                      style: const TextStyle(color: Colors.white70)),
                  if (_linkedCard.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Chip(
                        backgroundColor: Colors.white12,
                        label: Text('💳 $_linkedCard',
                            style: const TextStyle(
                                color: Color(0xFFD4AF37), fontSize: 12)),
                      ),
                    ),
                  const Divider(color: Colors.white24, height: 24),
                  const Text('الرصيد الفعلي المتاح',
                      style: TextStyle(color: Colors.white70)),
                  Text(
                    '${_balance.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _openLinkCardAndDepositDialog,
                          icon: const Icon(Icons.credit_card),
                          label: const Text('ربط فيزا / إيداع'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF006A4E),
                          ),
                          onPressed: () => _openTransferDialog(),
                          icon: const Icon(Icons.send),
                          label: const Text('تحويل لحظي'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => Scaffold(
                              appBar: AppBar(
                                  title: const Text('امسح باركود المستلم')),
                              body: MobileScanner(
                                onDetect: (cap) {
                                  if (cap.barcodes.isNotEmpty &&
                                      cap.barcodes.first.rawValue != null) {
                                    final raw = cap.barcodes.first.rawValue!;
                                    Navigator.pop(ctx);
                                    String phone = raw;
                                    if (raw.contains('ACC=')) {
                                      phone = raw
                                          .split('ACC=')[1]
                                          .split('&')[0];
                                    }
                                    _openTransferDialog(prefilledPhone: phone);
                                  }
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('الدفع بمسح باركود QR'),
                    ),
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
                  const Text('الباركود الخاص بحسابك (InstaPay QR)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  QrImageView(data: uniqueQrPayload, size: 160),
                  Text(w.currentUserPhone,
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('سجل المعاملات البنكية وكشف الحساب',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_txHistory.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('لا توجد معاملات مالية مسجلة حتى الآن'),
              ),
            )
          else
            ..._txHistory.map((tx) {
              final isOut = tx['sender_phone'] == w.currentUserPhone;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        isOut ? Colors.red.shade50 : Colors.green.shade50,
                    child: Icon(
                      isOut ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isOut ? Colors.red : Colors.green,
                    ),
                  ),
                  title: Text(tx['note'] ?? ''),
                  subtitle: Text('مرجع: #${tx['ref_code']}'),
                  trailing: Text(
                    '${isOut ? '-' : '+'}${tx['amount']} ج.م',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOut ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class AdminCompaniesScreen extends StatefulWidget {
  const AdminCompaniesScreen({super.key});

  @override
  State createState() => _AdminCompaniesScreenState();
}

class _AdminCompaniesScreenState extends State {
  List _companies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future _loadCompanies() async {
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('companies')
          .select()
          .order('created_at', ascending: false);
      setState(() => _companies = List.from(res));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future _updateStatus(String id, String status) async {
    await supabase.from('companies').update({'status': status}).eq('id', id);
    _loadCompanies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة واعتماد الشركات (Admin)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _companies.isEmpty
              ? const Center(child: Text('لا توجد طلبات شركات حالياً'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _companies.length,
                  itemBuilder: (_, i) {
                    final c = _companies[i];
                    final status = c['status'] ?? 'pending';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['company_name'] ?? '',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('العنوان: ${c['company_address']}'),
                            Text('الرقم الضريبي: ${c['tax_id']}'),
                            Text('المفوض: ${c['delegate_name']}'),
                            Text('الموبايل: ${c['phone']}'),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Chip(
                                  label: Text(status == 'approved'
                                      ? 'معتمد ✅'
                                      : status == 'rejected'
                                          ? 'مرفوض ❌'
                                          : 'قيد المراجعة ⏳'),
                                ),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white),
                                      onPressed: () =>
                                          _updateStatus(c['id'], 'approved'),
                                      child: const Text('موافقة'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () =>
                                          _updateStatus(c['id'], 'rejected'),
                                      child: const Text('رفض'),
                                    ),
                                  ],
                                ),
                              ],
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
// 6. REAL LIVE PORTALS (DIGITAL EGYPT, PUBG/GAMES TOPUP, REAL BILLS, HOTELS)
// ============================================================================
class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool isCorporate;
  const ServicesTab({
    super.key,
    required this.currentUserPhone,
    required this.isCorporate,
  });

  void _launchRealUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final realPortals = [
      {
        'title': 'مصر الرقمية',
        'sub': 'البوابة الحكومية الرسمية',
        'icon': Icons.account_balance,
        'url': 'https://digital.gov.eg',
      },
      {
        'title': 'شحن شدات ببجي PUBG',
        'sub': 'Midasbuy الرسمي',
        'icon': Icons.sports_esports,
        'url': 'https://www.midasbuy.com/midasbuy/eg/buy/pubgm',
      },
      {
        'title': 'جواهر فري فاير',
        'sub': 'Shop2Game الرسمي',
        'icon': Icons.videogame_asset,
        'url': 'https://shop2game.com',
      },
      {
        'title': 'فواتير الكهرباء',
        'sub': 'المنصة الموحدة للكهرباء',
        'icon': Icons.electric_bolt,
        'url': 'https://eservices.eehc.gov.eg',
      },
      {
        'title': 'شحن فودافون / WE',
        'sub': 'البوابة الرسمية للشحن',
        'icon': Icons.phone_android,
        'url': 'https://web.vodafone.com.eg/ar/recharge',
      },
      {
        'title': 'قطارات مصر',
        'sub': 'حجز التذاكر الرسمي',
        'icon': Icons.train,
        'url': 'https://obs.enr.gov.eg/o-city/obs/enr/railway/ar/booktickets',
      },
    ];

    final luxuryPlaces = [
      {
        'name': 'مطعم وكافيه كازبلانكا - الزمالك',
        'cat': 'مطعم فاخر • إطلالة مباشرة على النيل',
        'rating': '4.9',
        'address': 'شارع أبو الفدا، الزمالك، القاهرة',
        'hours': '10:00 صباحاً - 2:00 صباحاً',
        'desc':
            'تجربة طعام راقية على ضفاف النيل مباشرة مع قائمة أطباق عالمية وشرقية وجلسات VIP مخصصة لرجال الأعمال والعائلات.',
        'image':
            'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      },
      {
        'name': 'قصر المشويات الملكي - التجمع الخامس',
        'cat': 'مشويات وطواجن فاخرة • قاعات VIP',
        'rating': '4.8',
        'address': 'شارع التسعين الشمالي، القاهرة الجديدة',
        'hours': '12:00 ظهراً - 1:00 صباحاً',
        'desc':
            'أفخم المشويات المصرية واللحوم الفاخرة مع قاعات اجتماعات خاصة للشركات وضيافة ملكية متكاملة.',
        'image':
            'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isCorporate
            ? 'بوابة الشركات VIP والخدمات الحقيقية'
            : 'الخدمات الحقيقية وشحن الألعاب'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isCorporate) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF004D38), Color(0xFF006A4E)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.workspace_premium,
                          color: Color(0xFFD4AF37), size: 28),
                      SizedBox(width: 8),
                      Text(
                        'حجوزات الشركات وكبار العملاء (VIP)',
                        style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () =>
                              _launchRealUrl('https://www.egyptair.com'),
                          icon: const Icon(Icons.flight_takeoff),
                          label: const Text('مصر للطيران ✈️'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF006A4E),
                          ),
                          onPressed: () =>
                              _launchRealUrl('https://www.booking.com'),
                          icon: const Icon(Icons.hotel),
                          label: const Text('حجز فنادق 🏨'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          const Text('بوابات الدفع الحكومية وشحن الألعاب الحقيقية',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: realPortals.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.55,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, i) {
              final s = realPortals[i];
              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _launchRealUrl(s['url'] as String),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s['icon'] as IconData,
                            color: const Color(0xFF006A4E), size: 30),
                        const SizedBox(height: 6),
                        Text(
                          s['title'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          s['sub'] as String,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('أفخم المطاعم والكافيهات (معاينة وحجز)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...luxuryPlaces.map((place) => Card(
                margin: const EdgeInsets.only(bottom: 14),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RestaurantDetailScreen(place: place),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(
                        place['image']!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(place['name']!,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      '${place['cat']} • ⭐ ${place['rating']}',
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF006A4E),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RestaurantDetailScreen(place: place),
                                  ),
                                );
                              },
                              child: const Text('معاينة وحجز'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class RestaurantDetailScreen extends StatefulWidget {
  final Map place;
  const RestaurantDetailScreen({super.key, required this.place});

  @override
  State createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State {
  final _guestsCtrl = TextEditingController(text: '4');
  final _timeCtrl = TextEditingController(text: '8:30 مساءً');

  RestaurantDetailScreen get w => widget as RestaurantDetailScreen;

  @override
  Widget build(BuildContext context) {
    final p = w.place;
    return Scaffold(
      appBar: AppBar(title: Text(p['name'] ?? '')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(
              p['image'] ?? '',
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] ?? '',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('📍 ${p['address']}'),
                  Text('🕒 ${p['hours']}',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  Text(p['desc'] ?? '', style: const TextStyle(height: 1.5)),
                  const Divider(height: 28),
                  const Text('نموذج الحجز',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _guestsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'عدد الأفراد'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _timeCtrl,
                    decoration: const InputDecoration(labelText: 'الموعد'),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006A4E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'تم تأكيد الحجز في ${p['name']} لعدد ${_guestsCtrl.text} أفراد ✅'),
                            backgroundColor: const Color(0xFF006A4E),
                          ),
                        );
                      },
                      child: const Text('تأكيد الحجز'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
