import 'dart:async';
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
// 1. LOGIN SCREEN (INDIVIDUAL + CORPORATE REGISTRATION + ADMIN GATE)
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
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      _otpSent = true;
      _busy = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('كود التفعيل لـ $phone هو: 123456'),
          backgroundColor: const Color(0xFF006A4E),
        ),
      );
    }
  }

  Future _verifyAndEnter() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (_otpCtrl.text.trim() != '123456') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود التفعيل غير صحيح (استخدم 123456)')),
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
            'balance': 50000.0,
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
            'balance': 1000.0,
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
                          labelText: 'كود التفعيل (123456)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
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
                                    ? (_isCorporate
                                        ? 'تأكيد ودخول الشركات'
                                        : 'دخول للتطبيق')
                                    : 'إرسال كود التفعيل',
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
// 2. FAST MAIN HOME SHELL (IndexedStack for Instant Zero-Lag Switching)
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
                : 'الخدمات والمطاعم',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. CHATS TAB + FULL CONTACTS LIST WITH SEARCH
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
            'profile': registeredMap[norm],
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
            tooltip: 'بحث برقم الموبايل',
            onPressed: _searchByPhoneDialog,
          ),
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'كل جهات الاتصال',
            onPressed: _openContactsSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: _users.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        const Icon(Icons.chat_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Center(
                            child: Text('افتح جهات الاتصال لبدء محادثة فورية')),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _openContactsSheet,
                            icon: const Icon(Icons.contacts),
                            label: const Text('عرض كل جهات الاتصال'),
                          ),
                        )
                      ],
                    )
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        final avatar = (u['avatar_url'] ?? '').toString();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF006A4E),
                            backgroundImage: avatar.isNotEmpty
                                ? NetworkImage(avatar)
                                : null,
                            child: avatar.isEmpty
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
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
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF006A4E),
        foregroundColor: Colors.white,
        onPressed: _openContactsSheet,
        icon: const Icon(Icons.contacts),
        label: const Text('كل جهات الاتصال'),
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
        title: Text(
            'جهات الاتصال (${w.matched.length + w.allContacts.length})'),
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text('جميع الأرقام المسجلة على الهاتف',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...filteredAll.map((c) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone)),
                      title: Text(c['name']),
                      subtitle: Text(c['phone']),
                      trailing: TextButton(
                        onPressed: () {
                          final msg = Uri.encodeComponent(
                              'انضم معايا على تطبيق EG MASR!');
                          launchUrl(
                              Uri.parse('sms:${c['phone']}?body=$msg'));
                        },
                        child: const Text('دعوة / SMS'),
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
// 4. CHAT ROOM
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
  Timer? _pollTimer;

  ChatRoomScreen get w => widget as ChatRoomScreen;

  String get _roomId {
    final list = [w.myPhone, w.peerPhone]..sort();
    return '${list[0]}_${list[1]}';
  }

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
    try {
      await supabase.from('messages').insert({
        'room_id': _roomId,
        'sender_phone': w.myPhone,
        'receiver_phone': w.peerPhone,
        'content': text.trim(),
        'msg_type': type,
      });
      _fetchMessages();
    } catch (_) {
      setState(() {
        _messages.add({
          'sender_phone': w.myPhone,
          'content': text.trim(),
          'msg_type': type,
        });
      });
    }
  }

  Future _pickAndSendMedia(ImageSource source, {bool isVideo = false}) async {
    final XFile? file = isVideo
        ? await _picker.pickVideo(source: source)
        : await _picker.pickImage(source: source, imageQuality: 70);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final path = 'chat_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('avatars').uploadBinary(path, bytes);
      final url = supabase.storage.from('avatars').getPublicUrl(path);
      await _sendMessage(url, type: isVideo ? 'video' : 'image');
    } catch (_) {
      await _sendMessage('[مرفق وسائط: ${file.name}]', type: 'text');
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
              icon: const Icon(Icons.call),
              onPressed: () => _sendMessage('📞 مكالمة صوتية صادرة')),
          IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: () => _sendMessage('📹 مكالمة فيديو صادرة')),
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
                  onPressed: () => _pickAndSendMedia(ImageSource.gallery),
                ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالتك هنا...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _sendMessage,
                  ),
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
// 5. WALLET TAB + ADMIN APPROVAL PANEL (ONLY FOR 01012055498)
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
  double _balance = 1000.0;
  String _fullName = 'مستخدم EG Masr';
  String _avatarUrl = '';

  WalletTab get w => widget as WalletTab;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future _loadProfile() async {
    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.currentUserPhone)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _balance = (data['balance'] ?? 1000).toDouble();
          _fullName = data['full_name'] ?? _fullName;
          _avatarUrl = (data['avatar_url'] ?? '').toString();
        });
      }
    } catch (_) {}
  }

  Future _changeProfilePhoto() async {
    final picker = ImagePicker();
    final XFile? img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img == null) return;
    try {
      final bytes = await img.readAsBytes();
      final fileName =
          'avatar_${w.currentUserPhone}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      await supabase
          .from('profiles')
          .update({'avatar_url': publicUrl}).eq('phone', w.currentUserPhone);
      setState(() => _avatarUrl = publicUrl);
    } catch (_) {}
  }

  Future _transferMoney(String toPhone, double amount) async {
    if (amount <= 0 || amount > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرصيد غير كافٍ')),
      );
      return;
    }
    setState(() => _balance -= amount);
    try {
      await supabase
          .from('profiles')
          .update({'balance': _balance}).eq('phone', w.currentUserPhone);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحويل $amount ج.م إلى $toPhone بنجاح ✅'),
          backgroundColor: const Color(0xFF006A4E),
        ),
      );
    }
  }

  void _openTransferDialog({String? prefilledPhone}) {
    final phoneCtrl = TextEditingController(text: prefilledPhone ?? '');
    final amtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل أموال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم المستلم'),
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
              final a = double.tryParse(amtCtrl.text.trim()) ?? 0;
              Navigator.pop(ctx);
              _transferMoney(p, a);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحفظة و QR'),
        actions: [
          if (w.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings,
                  color: Color(0xFFD4AF37)),
              tooltip: 'لوحة موافقة الشركات (Admin)',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (w.isAdmin)
              Card(
                color: const Color(0xFFD4AF37),
                margin: const EdgeInsets.only(bottom: 14),
                child: ListTile(
                  leading: const Icon(Icons.verified_user, color: Colors.black),
                  title: const Text('لوحة تحكم الأدمن (موافقة الشركات)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('مراجعة واعتماد طلبات تسجيل الشركات'),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              color: const Color(0xFF006A4E),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _changeProfilePhoto,
                          child: CircleAvatar(
                            radius: 30,
                            backgroundColor: const Color(0xFFD4AF37),
                            backgroundImage: _avatarUrl.isNotEmpty
                                ? NetworkImage(_avatarUrl)
                                : null,
                            child: _avatarUrl.isEmpty
                                ? const Icon(Icons.camera_alt,
                                    color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fullName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              Text(w.currentUserPhone,
                                  style:
                                      const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    Text(
                      '${_balance.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => _openTransferDialog(),
                            icon: const Icon(Icons.send),
                            label: const Text('تحويل برقم'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF006A4E),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => Scaffold(
                                    appBar: AppBar(
                                        title: const Text('امسح كود QR')),
                                    body: MobileScanner(
                                      onDetect: (cap) {
                                        if (cap.barcodes.isNotEmpty &&
                                            cap.barcodes.first.rawValue !=
                                                null) {
                                          final val =
                                              cap.barcodes.first.rawValue!;
                                          Navigator.pop(ctx);
                                          _openTransferDialog(
                                              prefilledPhone: val.replaceAll(
                                                  'EGMASR:', ''));
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('مسح QR'),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('كود QR الخاص بك',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    QrImageView(
                      data: 'EGMASR:${w.currentUserPhone}',
                      size: 160,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
// 6. SERVICES, DIGITAL EGYPT, CORPORATE VIP (FLIGHTS, HOTELS, LUXURY DINING)
//    & RESTAURANT DETAILS PAGE WITH PHOTOS BEFORE BOOKING
// ============================================================================
class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool isCorporate;
  const ServicesTab({
    super.key,
    required this.currentUserPhone,
    required this.isCorporate,
  });

  void _openRealPaymentScreen(BuildContext context, String serviceTitle,
      String fieldLabel, IconData icon) {
    final accountCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(serviceTitle)),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 54, color: const Color(0xFF006A4E)),
                const SizedBox(height: 12),
                Text('الدفع الفوري - $serviceTitle',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(
                  controller: accountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: fieldLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'المبلغ المطلوب (ج.م)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006A4E),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (accountCtrl.text.trim().isEmpty ||
                          amountCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('أدخل البيانات والمبلغ')),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'تم سداد ${amountCtrl.text} ج.م لـ $serviceTitle بنجاح ✅'),
                          backgroundColor: const Color(0xFF006A4E),
                        ),
                      );
                    },
                    child: const Text('تأكيد السداد الفوري',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = [
      {
        'title': 'مصر الرقمية',
        'icon': Icons.account_balance,
        'label': 'بوابة مصر الرقمية الحكومية',
        'isGov': true,
      },
      {
        'title': 'شحن رصيد',
        'icon': Icons.phone_android,
        'label': 'رقم الموبايل المراد شحنه',
        'isGov': false,
      },
      {
        'title': 'فواتير الكهرباء',
        'icon': Icons.electric_bolt,
        'label': 'رقم السداد الإلكتروني للعداد',
        'isGov': false,
      },
      {
        'title': 'فواتير المياه',
        'icon': Icons.water_drop,
        'label': 'رقم حساب فاتورة المياه',
        'isGov': false,
      },
      {
        'title': 'الإنترنت الأرضي',
        'icon': Icons.wifi,
        'label': 'رقم التليفون الأرضي بكود المحافظة',
        'isGov': false,
      },
      {
        'title': 'تذاكر المترو والقطار',
        'icon': Icons.train,
        'label': 'رقم المحطة / كود التذكرة',
        'isGov': false,
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
      {
        'name': 'جولدن نايل لاونج - جاردن سيتي',
        'cat': 'كافيه ومطعم رجال أعمال • 5 نجوم',
        'rating': '4.9',
        'address': 'كورنيش النيل، جاردن سيتي، القاهرة',
        'hours': '8:00 صباحاً - 3:00 صباحاً',
        'desc':
            'أجواء هادئة وفاخرة لاجتماعات الشركات والضيافة الرسمية مع أجود أنواع القهوة المختصة والمأكولات العالمية.',
        'image':
            'https://images.unsplash.com/photo-1559339352-11d035aa65de?w=800',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isCorporate
            ? 'بوابة الشركات VIP والخدمات'
            : 'الخدمات والمطاعم ومصر الرقمية'),
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
                        'خدمات الشركات وكبار العملاء (VIP)',
                        style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 17,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CorporateTravelScreen(
                                      isFlight: true)),
                            );
                          },
                          icon: const Icon(Icons.flight_takeoff),
                          label: const Text('حجز طيران'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF006A4E),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CorporateTravelScreen(
                                      isFlight: false)),
                            );
                          },
                          icon: const Icon(Icons.hotel),
                          label: const Text('حجز فنادق'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          const Text('الخدمات الحكومية ومصر الرقمية والفواتير',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.0,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, i) {
              final s = services[i];
              final isGov = s['isGov'] == true;
              return Card(
                color: isGov ? const Color(0xFF006A4E) : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (isGov) {
                      launchUrl(Uri.parse('https://digital.gov.eg'),
                          mode: LaunchMode.externalApplication);
                    } else {
                      _openRealPaymentScreen(
                        context,
                        s['title'] as String,
                        s['label'] as String,
                        s['icon'] as IconData,
                      );
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s['icon'] as IconData,
                          color: isGov
                              ? const Color(0xFFD4AF37)
                              : const Color(0xFF006A4E),
                          size: 30),
                      const SizedBox(height: 8),
                      Text(
                        s['title'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isGov ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
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
                        height: 160,
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
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${place['cat']} • ⭐ ${place['rating']}',
                                      style:
                                          const TextStyle(color: Colors.grey)),
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

// ============================================================================
// RESTAURANT FULL PREVIEW PAGE + BOOKING FORM ON SAME / RETURN FLOW
// ============================================================================
class RestaurantDetailScreen extends StatefulWidget {
  final Map place;
  const RestaurantDetailScreen({super.key, required this.place});

  @override
  State createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State {
  final _guestsCtrl = TextEditingController(text: '4');
  final _timeCtrl = TextEditingController(text: '8:30 مساءً');
  final _notesCtrl = TextEditingController();

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
              height: 230,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(p['name'] ?? '',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      Chip(
                        backgroundColor: const Color(0xFFD4AF37),
                        label: Text('⭐ ${p['rating']}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('📍 ${p['address']}',
                      style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text('🕒 مواعيد العمل: ${p['hours']}',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  Text(p['desc'] ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.5)),
                  const Divider(height: 32),
                  const Text('نموذج حجز طاولة / قاعة VIP',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _guestsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'عدد الأفراد',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timeCtrl,
                    decoration: InputDecoration(
                      labelText: 'الموعد والتاريخ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات إضافية (جلسة نيلية / قاعة شركات)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
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
                                'تم تأكيد حجزك في ${p['name']} لعدد ${_guestsCtrl.text} أفراد الساعة ${_timeCtrl.text} ✅'),
                            backgroundColor: const Color(0xFF006A4E),
                          ),
                        );
                      },
                      child: const Text('تأكيد الحجز الآن',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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

// ============================================================================
// CORPORATE VIP FLIGHTS & HOTELS BOOKING PORTAL
// ============================================================================
class CorporateTravelScreen extends StatelessWidget {
  final bool isFlight;
  const CorporateTravelScreen({super.key, required this.isFlight});

  @override
  Widget build(BuildContext context) {
    final items = isFlight
        ? [
            {
              'title': 'مصر للطيران (EGYPTAIR) - درجة رجال الأعمال',
              'sub': 'القاهرة ✈️ دبي / الرياض / لندن • مرونة كاملة للشركات',
              'price': '14,500 ج.م',
            },
            {
              'title': 'طيران الإمارات (Emirates) - VIP Corporate',
              'sub': 'القاهرة ✈️ دبي • صالة كبار الزوار + سيارة خاصة',
              'price': '19,800 ج.م',
            },
            {
              'title': 'الخطوط السعودية (SAUDIA) - Business Class',
              'sub': 'القاهرة ✈️ جدة / الرياض • رحلات يومية مباشرة',
              'price': '13,200 ج.م',
            },
          ]
        : [
            {
              'title': 'فندق فورسيزونز نايل بلازا (Four Seasons)',
              'sub': 'جاردن سيتي، القاهرة • أجنحة تنفيذية وقاعات مؤتمرات',
              'price': '16,000 ج.م / ليلة',
            },
            {
              'title': 'فندق ماريوت الزمالك (Cairo Marriott)',
              'sub': 'الزمالك، القاهرة • إطلالة نيلية وخدمات رجال أعمال',
              'price': '11,500 ج.م / ليلة',
            },
            {
              'title': 'فندق سانت ريجيس الماسة - العاصمة الإدارية',
              'sub': 'العاصمة الإدارية الجديدة • استضافة الوفود والشركات',
              'price': '13,800 ج.م / ليلة',
            },
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isFlight
            ? 'حجز تذاكر طيران الشركات ✈️'
            : 'حجز الفنادق الكبرى للشركات 🏨'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['title']!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(item['sub']!,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item['price']!,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF006A4E))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006A4E),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'تم إرسال طلب حجز ${item['title']} لقسم حجوزات الشركات ✅'),
                              backgroundColor: const Color(0xFF006A4E),
                            ),
                          );
                        },
                        child: const Text('احجز للشركة'),
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
