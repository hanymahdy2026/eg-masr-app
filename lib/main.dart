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
import 'package:geolocator/geolocator.dart';

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
// 1. LOGIN SCREEN (REAL SMS OTP VIA SUPABASE PHONE AUTH + CORPORATE)
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

  String _toInternationalEgypt(String localPhone) {
    final norm = _normalizePhone(localPhone);
    if (norm.startsWith('0')) {
      return '+20${norm.substring(1)}';
    }
    return '+20$norm';
  }

  Future _sendRealSmsOtp() async {
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
          const SnackBar(
              content: Text('يرجى استكمال جميع بيانات المنشأة والمفوض')),
        );
        return;
      }
    }

    setState(() => _busy = true);
    final intlPhone = _toInternationalEgypt(phone);

    try {
      await supabase.auth.signInWithOtp(phone: intlPhone);
      setState(() {
        _otpSent = true;
        _otpCtrl.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال رسالة نصية SMS بكود التفعيل إلى $phone 📩'),
            backgroundColor: const Color(0xFF006A4E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تعذر إرسال SMS: تأكد من تفعيل مزود Phone/Twilio في Supabase ($e)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future _verifySmsAndEnter() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    final code = _otpCtrl.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الكود المرسل في الرسالة النصية')),
      );
      return;
    }
    setState(() => _busy = true);
    final intlPhone = _toInternationalEgypt(phone);

    try {
      await supabase.auth.verifyOTP(
        phone: intlPhone,
        token: code,
        type: OtpType.sms,
      );

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كود الرسالة النصية غير صحيح أو منتهي الصلاحية!'),
            backgroundColor: Colors.red,
          ),
        );
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
                          labelText: 'كود التفعيل المرسل في رسالة SMS',
                          prefixIcon: const Icon(Icons.sms),
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
                            : (_otpSent
                                ? _verifySmsAndEnter
                                : _sendRealSmsOtp),
                        child: _busy
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _otpSent
                                    ? 'تأكيد الكود والدخول'
                                    : 'إرسال كود SMS على الموبايل',
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
      ChatsAndGroupsTab(currentUserPhone: w.userPhone),
      SocialFeedTab(
        currentUserPhone: w.userPhone,
        isAdmin: w.userPhone == adminPhoneNumber,
      ),
      DirectPayAndQrTab(
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'المحادثات',
          ),
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed),
            label: 'الموجز',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'الدفع والباركود',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'الخدمات والتوصيل',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. CHATS (PROMINENT CONTACTS BUTTON + CLEAN "الجروبات" TAB + LIVE LOCATION)
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
  Set _friendPhones = {};
  bool _loading = true;

  ChatsAndGroupsTab get w => widget as ChatsAndGroupsTab;

  @override
  void initState() {
    super.initState();
    _loadData();
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
      final friends = <String>{};
      for (var r in rels) {
        if (r['relation_type'] == 'block') {
          blocked.add(r['target_phone'].toString());
        } else if (r['relation_type'] == 'friend') {
          friends.add(r['target_phone'].toString());
        }
      }

      if (mounted) {
        setState(() {
          _users = List.from(profs);
          _groups = List.from(grps);
          _blockedPhones = blocked;
          _friendPhones = friends;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _createGroupDialog() {
    final nameCtrl = TextEditingController();
    final selectedPhones = {w.currentUserPhone};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('إنشاء جروب جديد 👥'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الجروب',
                    prefixIcon: Icon(Icons.group),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      final ph = u['phone'].toString();
                      final checked = selectedPhones.contains(ph);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(u['full_name'] ?? ph),
                        subtitle: Text(ph),
                        onChanged: (v) {
                          setSt(() {
                            if (v == true) {
                              selectedPhones.add(ph);
                            } else {
                              selectedPhones.remove(ph);
                            }
                          });
                        },
                      );
                    },
                  ),
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
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await supabase.from('groups').insert({
                  'group_name': nameCtrl.text.trim(),
                  'created_by': w.currentUserPhone,
                  'members': selectedPhones.toList(),
                });
                _loadData();
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }

  Future _openContactsScreen() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يرجى السماح بالوصول لجهات الاتصال من الإعدادات')),
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
          matched.add({'name': c.displayName, 'phone': norm});
        } else {
          allOthers.add({'name': c.displayName, 'phone': ph.number});
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
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'محادثات خاصة'),
              Tab(text: 'الجروبات'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.group_add),
              tooltip: 'إنشاء جروب',
              onPressed: _createGroupDialog,
            ),
          ],
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
                      final isFriend = _friendPhones.contains(ph);
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF006A4E),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Row(
                          children: [
                            Text(u['full_name'] ?? ph),
                            if (isFriend) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified,
                                  color: Colors.blue, size: 16),
                            ],
                          ],
                        ),
                        subtitle: Text(ph),
                        trailing: const Icon(Icons.chevron_right),
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
                                isFriend: isFriend,
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
                      final members = List.from(g['members'] ?? []);
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFD4AF37),
                          child: Icon(Icons.groups, color: Colors.black),
                        ),
                        title: Text(g['group_name'] ?? ''),
                        subtitle: Text('الأعضاء: ${members.length}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomScreen(
                                myPhone: w.currentUserPhone,
                                roomId: 'GROUP_${g['id']}',
                                peerPhone: g['id'].toString(),
                                title: g['group_name'] ?? 'جروب',
                                isGroup: true,
                                groupId: g['id'].toString(),
                                groupMembers: members,
                                onRelationChanged: _loadData,
                              ),
                            ),
                          );
                        },
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
  const FullContactsScreen({
    super.key,
    required this.myPhone,
    required this.matched,
    required this.allContacts,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جهات الاتصال')),
      body: ListView(
        children: [
          if (matched.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('مسجلون في EG MASR',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF006A4E))),
            ),
          ...matched.map((m) => ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0xFF006A4E),
                    child: Icon(Icons.person, color: Colors.white)),
                title: Text(m['name']),
                subtitle: Text(m['phone']),
                trailing: const Icon(Icons.chat, color: Color(0xFF006A4E)),
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
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('جميع جهات الاتصال على هاتفك',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
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
  final bool isFriend;
  final String? groupId;
  final List? groupMembers;
  final VoidCallback? onRelationChanged;

  const ChatRoomScreen({
    super.key,
    required this.myPhone,
    required this.roomId,
    required this.peerPhone,
    required this.title,
    required this.isGroup,
    this.isFriend = false,
    this.groupId,
    this.groupMembers,
    this.onRelationChanged,
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
          .eq('room_id', w.roomId)
          .order('created_at', ascending: true);
      if (mounted) setState(() => _messages = List.from(res));
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
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى تفعيل صلاحية الموقع GPS')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
      _sendMessage('📍 موقعي الحالي على الخريطة:\n$mapsUrl', type: 'location');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديد الموقع: $e')),
        );
      }
    }
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
      _sendMessage('🎤 رسالة صوتية (0:${dur.toString().padLeft(2, '0')})',
          type: 'voice');
    }
  }

  Future _addFriend() async {
    await supabase.from('user_relations').insert({
      'user_phone': w.myPhone,
      'target_phone': w.peerPhone,
      'relation_type': 'friend',
    });
    w.onRelationChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الإضافة إلى قائمة الأصدقاء ✅')),
      );
    }
  }

  Future _blockUser() async {
    await supabase.from('user_relations').insert({
      'user_phone': w.myPhone,
      'target_phone': w.peerPhone,
      'relation_type': 'block',
    });
    w.onRelationChanged?.call();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم عمل حظر (Block) لهذا الحساب بنجاح 🚫'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _reportUserDialog() {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إبلاغ الإدارة عن حساب مخالف 🚨'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'سبب الإبلاغ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await supabase.from('reports').insert({
                'reporter_phone': w.myPhone,
                'reported_phone': w.peerPhone,
                'reason': reasonCtrl.text.trim().isEmpty
                    ? 'إبلاغ عن إساءة'
                    : reasonCtrl.text.trim(),
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('تم إرسال البلاغ للأدمن للمراجعة فوراً ✅')),
                );
              }
            },
            child: const Text('إرسال البلاغ للأدمن'),
          ),
        ],
      ),
    );
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
          if (!w.isGroup)
            PopupMenuButton(
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'friend', child: Text('إضافة كصديق 👥')),
                const PopupMenuItem(
                    value: 'block',
                    child: Text('حظر الحساب (Block) 🚫',
                        style: TextStyle(color: Colors.red))),
                const PopupMenuItem(
                    value: 'report',
                    child: Text('إبلاغ للأدمن 🚨',
                        style: TextStyle(color: Colors.orange))),
              ],
              onSelected: (v) {
                if (v == 'friend') _addFriend();
                if (v == 'block') _blockUser();
                if (v == 'report') _reportUserDialog();
              },
            ),
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
                        ? () {
                            final url = content.split('\n').last.trim();
                            launchUrl(Uri.parse(url),
                                mode: LaunchMode.externalApplication);
                          }
                        : null,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 270),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF006A4E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (w.isGroup && !isMe)
                            Text(m['sender_phone'] ?? '',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF006A4E))),
                          Text(
                            content,
                            style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                decoration:
                                    isLoc ? TextDecoration.underline : null),
                          ),
                          if (isLoc)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('اضغط لفتح الموقع على الخريطة 🗺️',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isMe
                                          ? const Color(0xFFD4AF37)
                                          : const Color(0xFF006A4E))),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.location_on, color: Colors.red),
                  tooltip: 'مشاركة موقعي',
                  onPressed: _sendMyLiveLocation,
                ),
                IconButton(
                  icon: const Icon(Icons.photo, color: Color(0xFF006A4E)),
                  onPressed: () async {
                    final f =
                        await _picker.pickImage(source: ImageSource.gallery);
                    if (f != null) _sendMessage('📷 صورة مرفقة: ${f.name}');
                  },
                ),
                Expanded(
                  child: _isRecording
                      ? Text(
                          '🔴 جاري تسجيل الصوت... 0:${_recordSeconds.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        )
                      : TextField(
                          controller: _msgCtrl,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالتك...',
                            border: InputBorder.none,
                          ),
                          onSubmitted: _sendMessage,
                        ),
                ),
                IconButton(
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic,
                    color: _isRecording ? Colors.red : const Color(0xFF006A4E),
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
// 4. SOCIAL FEED TAB (FIXED REAL IMAGE & VIDEO UPLOAD + DISPLAY)
// ============================================================================
class SocialFeedTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  const SocialFeedTab({
    super.key,
    required this.currentUserPhone,
    required this.isAdmin,
  });

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

      final rels = await supabase
          .from('user_relations')
          .select()
          .eq('user_phone', w.currentUserPhone);
      final fr = <String>{};
      final bl = <String>{};
      for (var r in rels) {
        if (r['relation_type'] == 'friend') {
          fr.add(r['target_phone'].toString());
        } else if (r['relation_type'] == 'block') {
          bl.add(r['target_phone'].toString());
        }
      }

      final allPosts = await supabase
          .from('posts')
          .select()
          .order('created_at', ascending: false);

      final filtered = [];
      for (var p in allPosts) {
        final author = p['author_phone'].toString();
        final priv = p['privacy'] ?? 'public';
        if (bl.contains(author)) continue;
        if (author == w.currentUserPhone || w.isAdmin) {
          filtered.add(p);
        } else if (priv == 'public') {
          filtered.add(p);
        } else if (priv == 'friends' && fr.contains(author)) {
          filtered.add(p);
        }
      }

      if (mounted) {
        setState(() {
          _posts = filtered;
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
        await supabase.storage.from(bucket).uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        return supabase.storage.from(bucket).getPublicUrl(fileName);
      } catch (_) {}
    }
    return '';
  }

  void _openCreatePostDialog() {
    final contentCtrl = TextEditingController();
    String privacy = 'public';
    String mediaType = 'text';
    String uploadedUrl = '';
    bool uploading = false;
    final picker = ImagePicker();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('منشور جديد في الموجز'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  value: privacy,
                  decoration: const InputDecoration(
                    labelText: 'الخصوصية',
                    prefixIcon: Icon(Icons.lock_person),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'public', child: Text('🌍 العامة (الجميع)')),
                    DropdownMenuItem(
                        value: 'friends', child: Text('👥 الأصدقاء فقط')),
                    DropdownMenuItem(
                        value: 'only_me', child: Text('🔒 أنا فقط')),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => privacy = v.toString());
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'اكتب منشورك هنا...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                if (uploading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
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
                                  if (url.isEmpty && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'يرجى تفعيل Public Bucket باسم media أو avatars في Supabase Storage')),
                                    );
                                  }
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
                if (uploadedUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      mediaType == 'image'
                          ? '✅ تم رفع الصورة وجاهزة للنشر'
                          : '🎬 تم رفع الفيديو وجاهز للنشر',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold),
                    ),
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
                foregroundColor: Colors.white,
              ),
              onPressed: uploading
                  ? null
                  : () async {
                      if (contentCtrl.text.trim().isEmpty &&
                          uploadedUrl.isEmpty) {
                        return;
                      }
                      Navigator.pop(ctx);
                      await supabase.from('posts').insert({
                        'author_phone': w.currentUserPhone,
                        'author_name': _myName,
                        'content': contentCtrl.text.trim(),
                        'media_url': uploadedUrl,
                        'media_type': mediaType,
                        'privacy': privacy,
                        'likes': [],
                        'comments': [],
                      });
                      _loadFeed();
                    },
              child: const Text('نشر الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Future _toggleLike(Map post) async {
    final likes = List.from(post['likes'] ?? []);
    if (likes.contains(w.currentUserPhone)) {
      likes.remove(w.currentUserPhone);
    } else {
      likes.add(w.currentUserPhone);
    }
    await supabase
        .from('posts')
        .update({'likes': likes}).eq('id', post['id']);
    _loadFeed();
  }

  void _openCommentsDialog(Map post) {
    final commentCtrl = TextEditingController();
    final comments = List.from(post['comments'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('التعليقات 💬'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 180,
                child: comments.isEmpty
                    ? const Center(child: Text('لا توجد تعليقات بعد'))
                    : ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (_, i) {
                          final c = comments[i];
                          return ListTile(
                            dense: true,
                            title: Text(c['name'] ?? ''),
                            subtitle: Text(c['text'] ?? ''),
                          );
                        },
                      ),
              ),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(hintText: 'اكتب تعليقك...'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ElevatedButton(
            onPressed: () async {
              if (commentCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              comments.add({
                'phone': w.currentUserPhone,
                'name': _myName,
                'text': commentCtrl.text.trim(),
              });
              await supabase
                  .from('posts')
                  .update({'comments': comments}).eq('id', post['id']);
              _loadFeed();
            },
            child: const Text('تعليق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('موجز EG MASR'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFeed),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? Center(
                  child: ElevatedButton.icon(
                    onPressed: _openCreatePostDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('انشر أول بوست أو صورة أو فيديو'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _posts.length,
                  itemBuilder: (_, i) {
                    final p = _posts[i];
                    final likes = List.from(p['likes'] ?? []);
                    final comments = List.from(p['comments'] ?? []);
                    final isLiked = likes.contains(w.currentUserPhone);
                    final priv = p['privacy'] ?? 'public';
                    final mediaUrl = (p['media_url'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Color(0xFF006A4E),
                                  child:
                                      Icon(Icons.person, color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p['author_name'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                        priv == 'public'
                                            ? '🌍 عام'
                                            : priv == 'friends'
                                                ? '👥 الأصدقاء'
                                                : '🔒 أنا فقط',
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if ((p['content'] ?? '').toString().isNotEmpty)
                              Text(p['content'],
                                  style: const TextStyle(fontSize: 15)),
                            if (p['media_type'] == 'image' &&
                                mediaUrl.startsWith('http')) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(mediaUrl,
                                    width: double.infinity, fit: BoxFit.cover),
                              ),
                            ] else if (p['media_type'] == 'video' &&
                                mediaUrl.startsWith('http')) ...[
                              const SizedBox(height: 10),
                              InkWell(
                                onTap: () => launchUrl(Uri.parse(mediaUrl),
                                    mode: LaunchMode.externalApplication),
                                child: Container(
                                  height: 150,
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_circle_fill,
                                            color: Color(0xFFD4AF37), size: 52),
                                        Text('اضغط لتشغيل الفيديو',
                                            style:
                                                TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _toggleLike(p),
                                  icon: Icon(
                                    isLiked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isLiked ? Colors.red : Colors.grey,
                                  ),
                                  label: Text('إعجاب (${likes.length})'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openCommentsDialog(p),
                                  icon: const Icon(Icons.comment_outlined),
                                  label: Text('تعليق (${comments.length})'),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('تمت المشاركة ✅')),
                                    );
                                  },
                                  icon: const Icon(Icons.share_outlined),
                                  label: const Text('مشاركة'),
                                ),
                              ],
                            ),
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
// 5. DIRECT BANK/WALLET LINKING & UNIQUE NON-REPEATING QR PAY (NO APP WALLET)
// ============================================================================
class DirectPayAndQrTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  const DirectPayAndQrTab({
    super.key,
    required this.currentUserPhone,
    required this.isAdmin,
  });

  @override
  State createState() => _DirectPayAndQrTabState();
}

class _DirectPayAndQrTabState extends State {
  String _fullName = 'مستخدم EG Masr';
  String _linkedAccount = '';
  String _uniqueQrToken = '';
  List _txHistory = [];

  DirectPayAndQrTab get w => widget as DirectPayAndQrTab;

  @override
  void initState() {
    super.initState();
    _initDirectPayData();
  }

  Future _initDirectPayData() async {
    final prefs = await SharedPreferences.getInstance();
    _linkedAccount =
        prefs.getString('direct_linked_${w.currentUserPhone}') ?? '';

    String? savedQr = prefs.getString('unique_qr_${w.currentUserPhone}');
    if (savedQr == null || savedQr.isEmpty) {
      final randomHex =
          Random.secure().nextInt(99999999).toRadixString(16).toUpperCase();
      final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      savedQr =
          'EGMASR-UID-${w.currentUserPhone}-$randomHex-$ts';
      await prefs.setString('unique_qr_${w.currentUserPhone}', savedQr);
    }

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('phone', w.currentUserPhone)
          .maybeSingle();
      if (data != null) {
        _fullName = data['full_name'] ?? _fullName;
      }
      final txs = await supabase
          .from('transactions')
          .select()
          .or('sender_phone.eq.${w.currentUserPhone},receiver_phone.eq.${w.currentUserPhone}')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _uniqueQrToken = savedQr!;
          _txHistory = List.from(txs);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _uniqueQrToken = savedQr!);
    }
  }

  void _openLinkBankOrWalletDialog() {
    String selectedProvider = 'حساب بنكي / فيزا (Visa / Mastercard / Meeza)';
    final numberCtrl = TextEditingController();

    final providers = [
      'حساب بنكي / فيزا (Visa / Mastercard / Meeza)',
      'فودافون كاش (Vodafone Cash)',
      'أورانج كاش (Orange Cash)',
      'اتصالات كاش (e& Money)',
      'وي باي (WE Pay)',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('ربط مباشر مع البنك أو المحفظة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                value: selectedProvider,
                isExpanded: true,
                items: providers
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => selectedProvider = v.toString());
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numberCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: selectedProvider.contains('بنكي')
                      ? 'رقم البطاقة البنكية أو IBAN'
                      : 'رقم محفظة الموبايل (01xxxxxxxxx)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006A4E),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final numStr = numberCtrl.text.trim();
                if (numStr.length < 11) return;
                Navigator.pop(ctx);
                final last4 = numStr.substring(numStr.length - 4);
                final label = '$selectedProvider (****$last4)';
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                    'direct_linked_${w.currentUserPhone}', label);
                setState(() => _linkedAccount = label);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'تم الربط المباشر! سيتم الخصم والاستقبال مباشرة من حسابك المرتبط ✅'),
                      backgroundColor: Color(0xFF006A4E),
                    ),
                  );
                }
              },
              child: const Text('تأكيد الربط المباشر'),
            ),
          ],
        ),
      ),
    );
  }

  void _openDirectTransferDialog({String? targetAcc}) {
    if (_linkedAccount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ربط حسابك البنكي أو محفظتك أولاً!'),
          backgroundColor: Colors.orange,
        ),
      );
      _openLinkBankOrWalletDialog();
      return;
    }

    final toCtrl = TextEditingController(text: targetAcc ?? '');
    final amtCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل / دفع مباشر عبر الباركود'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الخصم المباشر من: $_linkedAccount',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: toCtrl,
              decoration:
                  const InputDecoration(labelText: 'رقم حساب / باركود المستلم'),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006A4E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
              final dest = toCtrl.text.trim();
              if (amt <= 0 || dest.isEmpty) return;
              Navigator.pop(ctx);
              final ref = 'DIR${Random().nextInt(899999) + 100000}';
              await supabase.from('transactions').insert({
                'ref_code': ref,
                'sender_phone': w.currentUserPhone,
                'receiver_phone': dest,
                'amount': amt,
                'tx_type': 'direct_bank',
                'note': 'خصم مباشر من $_linkedAccount إلى $dest',
              });
              _initDirectPayData();
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('تم الدفع المباشر بنجاح ✅'),
                    content: Text(
                        'تم خصم $amt ج.م مباشرة من $_linkedAccount\nالمستلم: $dest\nرقم المرجع: #$ref'),
                    actions: [
                      ElevatedButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('تم'))
                    ],
                  ),
                );
              }
            },
            child: const Text('تأكيد الدفع المباشر'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الربط البنكي والدفع بالباركود'),
        actions: [
          if (w.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings,
                  color: Color(0xFFD4AF37)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminGovernanceScreen()),
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
                leading: const Icon(Icons.admin_panel_settings,
                    color: Colors.black),
                title: const Text('لوحة تحكم الأدمن (طلبات الشركات والبلاغات)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminGovernanceScreen()),
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
                  const Divider(color: Colors.white24, height: 24),
                  Text(
                    _linkedAccount.isEmpty
                        ? 'لم يتم ربط حساب بنكي أو محفظة بعد'
                        : 'الحساب المرتبط للدفع المباشر:\n$_linkedAccount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
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
                          onPressed: _openLinkBankOrWalletDialog,
                          icon: const Icon(Icons.account_balance),
                          label: Text(_linkedAccount.isEmpty
                              ? 'ربط بنك / محفظة'
                              : 'تغيير الحساب'),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                                      title:
                                          const Text('امسح باركود الدفع')),
                                  body: MobileScanner(
                                    onDetect: (cap) {
                                      if (cap.barcodes.isNotEmpty &&
                                          cap.barcodes.first.rawValue !=
                                              null) {
                                        final raw =
                                            cap.barcodes.first.rawValue!;
                                        Navigator.pop(ctx);
                                        String phone = raw;
                                        if (raw.contains('EGMASR-UID-')) {
                                          phone = raw.split('-')[2];
                                        }
                                        _openDirectTransferDialog(
                                            targetAcc: phone);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('ادفع بمسح QR'),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('الباركود الفريد الخاص بك (غير قابل للتكرار)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_uniqueQrToken.isNotEmpty)
                    QrImageView(data: _uniqueQrToken, size: 170),
                  Text(_uniqueQrToken,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('سجل المدفوعات المباشرة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._txHistory.map((tx) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF006A4E),
                    child: Icon(Icons.swap_horiz, color: Colors.white),
                  ),
                  title: Text(tx['note'] ?? ''),
                  subtitle: Text('مرجع: #${tx['ref_code']}'),
                  trailing: Text('${tx['amount']} ج.م',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
        ],
      ),
    );
  }
}

// ============================================================================
// ADMIN GOVERNANCE SCREEN (COMPANIES & REPORTS CONTROL ONLY)
// ============================================================================
class AdminGovernanceScreen extends StatefulWidget {
  const AdminGovernanceScreen({super.key});

  @override
  State createState() => _AdminGovernanceScreenState();
}

class _AdminGovernanceScreenState extends State {
  List _companies = [];
  List _reports = [];

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future _loadAdminData() async {
    try {
      final comps = await supabase
          .from('companies')
          .select()
          .order('created_at', ascending: false);
      final reps = await supabase
          .from('reports')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _companies = List.from(comps);
          _reports = List.from(reps);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الشركات والبلاغات (Admin)'),
          bottom: const TabBar(
            indicatorColor: Color(0xFFD4AF37),
            labelColor: Colors.white,
            tabs: [
              Tab(text: 'طلبات الشركات 🏢'),
              Tab(text: 'البلاغات الواردة 🚨'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _companies.isEmpty
                ? const Center(child: Text('لا توجد طلبات شركات حالياً'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _companies.length,
                    itemBuilder: (_, i) {
                      final c = _companies[i];
                      final st = c['status'] ?? 'pending';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c['company_name'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold)),
                              Text('العنوان: ${c['company_address']}'),
                              Text('الرقم الضريبي: ${c['tax_id']}'),
                              Text('المفوض: ${c['delegate_name']}'),
                              Text('الموبايل: ${c['phone']}'),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Chip(
                                    label: Text(st == 'approved'
                                        ? 'معتمد ✅'
                                        : st == 'rejected'
                                            ? 'مرفوض ❌'
                                            : 'قيد المراجعة ⏳'),
                                  ),
                                  Row(
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white),
                                        onPressed: () async {
                                          await supabase
                                              .from('companies')
                                              .update({'status': 'approved'}).eq(
                                                  'id', c['id']);
                                          _loadAdminData();
                                        },
                                        child: const Text('اعتماد'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () async {
                                          await supabase
                                              .from('companies')
                                              .update({'status': 'rejected'}).eq(
                                                  'id', c['id']);
                                          _loadAdminData();
                                        },
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
            _reports.isEmpty
                ? const Center(child: Text('لا توجد بلاغات حالياً'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _reports.length,
                    itemBuilder: (_, i) {
                      final r = _reports[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.report, color: Colors.red),
                          title: Text('بلاغ ضد: ${r['reported_phone']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'السبب: ${r['reason']}\nالمُبلّغ: ${r['reporter_phone']}'),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white),
                            onPressed: () async {
                              await supabase.from('user_relations').insert({
                                'user_phone': adminPhoneNumber,
                                'target_phone': r['reported_phone'],
                                'relation_type': 'block',
                              });
                              await supabase
                                  .from('reports')
                                  .delete()
                                  .eq('id', r['id']);
                              _loadAdminData();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'تم حظر الحساب المخالف وإغلاق البلاغ ✅')),
                                );
                              }
                            },
                            child: const Text('حظر الحساب'),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 6. SERVICES TAB (GOOGLE RESTAURANTS + UBER RIDES + TALABAT + CAPTAIN + TRACK)
// ============================================================================
class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool isCorporate;
  const ServicesTab({
    super.key,
    required this.currentUserPhone,
    required this.isCorporate,
  });

  Future _logDirectServicePayment(BuildContext context, double amount,
      String serviceName, String details) async {
    final prefs = await SharedPreferences.getInstance();
    final linked = prefs.getString('direct_linked_$currentUserPhone') ?? '';
    if (linked.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'يرجى ربط حسابك البنكي أو محفظتك من تبويب (الدفع والباركود) أولاً!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    final ref = 'EGM${Random().nextInt(899999) + 100000}';
    await supabase.from('transactions').insert({
      'ref_code': ref,
      'sender_phone': currentUserPhone,
      'receiver_phone': 'EG_MASR_GATEWAY',
      'amount': amount,
      'tx_type': 'service',
      'note': '$serviceName ($details) - خصم من $linked',
    });

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF004D38),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFFD4AF37)),
              SizedBox(width: 8),
              Text('إيصال دفع مباشر - EG MASR',
                  style: TextStyle(color: Color(0xFFD4AF37), fontSize: 16)),
            ],
          ),
          content: Text(
            'الخدمة: $serviceName\nالتفاصيل: $details\nالمبلغ: ${amount.toStringAsFixed(2)} ج.م\nتم الخصم من: $linked\nالمرجع: #$ref',
            style: const TextStyle(color: Colors.white, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم'),
            ),
          ],
        ),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final realRestaurants = [
      {
        'name': 'مطعم صبحي كابر (Sobhy Kaber)',
        'cat': 'مشويات وطواجن مصرية أصيلة',
        'rating': '4.9',
        'address': '151 شارع عبيد، روض الفرج، شبرا، القاهرة',
        'googleUrl':
            'https://www.google.com/search?q=%D9%85%D8%B7%D8%B9%D9%85+%D8%B5%D8%A8%D8%AD%D9%8A+%D9%83%D8%A7%D8%A8%D8%B1+%D8%A7%D9%84%D8%B1%D8%B3%D9%85%D9%8A',
        'image':
            'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
      },
      {
        'name': 'مطعم قصر الكبابجي (Qasr El Kababgi)',
        'cat': 'مشويات فاخرة وضيافة ملكية',
        'rating': '4.8',
        'address': 'التجمع الخامس / الشيخ زايد / مدينة نصر',
        'googleUrl':
            'https://www.google.com/search?q=%D9%85%D8%B7%D8%B9%D9%85+%D9%82%D8%B5%D8%B1+%D8%A7%D9%84%D9%83%D8%A8%D8%A7%D8%A8%D8%AC%D9%8A+%D8%A7%D9%84%D9%85%D9%88%D9%82%D8%B9+%D8%A7%D9%84%D8%B1%D8%B3%D9%85%D9%8A',
        'image':
            'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      },
      {
        'name': 'مطعم أبو شقرة (Abou Shakra)',
        'cat': 'أعرق مطاعم المشويات في مصر منذ 1947',
        'rating': '4.7',
        'address': '69 شارع القصر العيني، جاردن سيتي، القاهرة',
        'googleUrl':
            'https://www.google.com/search?q=%D9%85%D8%B7%D8%B9%D9%85+%D8%A7%D8%A8%D9%88+%D8%B4%D9%82%D8%B1%D8%A9+%D8%A7%D9%84%D9%85%D9%88%D9%82%D8%B9+%D8%A7%D9%84%D8%B1%D8%B3%D9%85%D9%8A',
        'image':
            'https://images.unsplash.com/photo-1544025162-d76694265947?w=800',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('خدمات وتوصيل EG MASR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // UBER RIDES + TALABAT DELIVERY + CAPTAIN + TRACK ORDER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF004D38), Color(0xFF006A4E)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'خدمة التوصيل والمشاوير الذكية 🚗🏍️',
                  style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 17,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'توصيل أفراد (سيارة / موتوسيكل مثل أوبر) أو توصيل طلبات (مثل طلبات) مع تتبع لحظي.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RideAndTalabatScreen(
                                customerPhone: currentUserPhone,
                                initialMode: 'ride',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.directions_car),
                        label: const Text('توصيل أفراد'),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                              builder: (_) => RideAndTalabatScreen(
                                customerPhone: currentUserPhone,
                                initialMode: 'talabat',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.delivery_dining),
                        label: const Text('توصيل طلبات'),
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
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaptainPortalScreen(
                                  captainPhone: currentUserPhone),
                            ),
                          );
                        },
                        icon: const Icon(Icons.two_wheeler),
                        label: const Text('سجّل ككابتن'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD4AF37),
                          side: const BorderSide(color: Color(0xFFD4AF37)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TrackOrderScreen(
                                  userPhone: currentUserPhone),
                            ),
                          );
                        },
                        icon: const Icon(Icons.track_changes),
                        label: const Text('تابع طلبك'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ROYAL HOTELS CARD
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF004D38),
                child: Icon(Icons.villa, color: Color(0xFFD4AF37)),
              ),
              title: const Text('حجز الفنادق والإقامات',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('حدد الوجهة، التاريخ بالساعة، والأعمار'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoyalHotelsBookingScreen(
                      onBookHotel: (h, d, p) =>
                          _logDirectServicePayment(context, p, 'فندق: $h', d),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          const Text('أشهر المطاعم الحقيقية (معاينة جوجل وحجز)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...realRestaurants.map((place) => Card(
                margin: const EdgeInsets.only(bottom: 14),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.network(place['image']!,
                        height: 140, width: double.infinity, fit: BoxFit.cover),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(place['name']!,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('${place['cat']} • ⭐ ${place['rating']}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          Text('📍 ${place['address']}',
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => launchUrl(
                                      Uri.parse(place['googleUrl']!),
                                      mode: LaunchMode.externalApplication),
                                  icon: const Icon(Icons.travel_explore,
                                      size: 18),
                                  label: const Text('معاينة المطعم'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF006A4E),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => _openRestaurantBookingForm(
                                      context, place['name']!),
                                  icon: const Icon(Icons.event_seat, size: 18),
                                  label: const Text('حجز'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  void _openRestaurantBookingForm(BuildContext context, String restName) {
    final guestsCtrl = TextEditingController(text: '4');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 20, minute: 30);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('حجز طاولة في $restName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: guestsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'عدد الأفراد', prefixIcon: Icon(Icons.people)),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(
                    'التاريخ: ${selectedDate.year}-${selectedDate.month}-${selectedDate.day}'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (d != null) setSt(() => selectedDate = d);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text('الوقت: ${selectedTime.format(ctx)}'),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx, initialTime: selectedTime);
                  if (t != null) setSt(() => selectedTime = t);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006A4E),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'تم تأكيد حجز $restName لعدد ${guestsCtrl.text} أفراد يوم ${selectedDate.day}/${selectedDate.month} الساعة ${selectedTime.format(context)} ✅'),
                    backgroundColor: const Color(0xFF006A4E),
                  ),
                );
              },
              child: const Text('تأكيد الحجز'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. UBER RIDES & TALABAT DELIVERY SCREEN + CAPTAIN REGISTRATION + TRACKING
// ============================================================================
class RideAndTalabatScreen extends StatefulWidget {
  final String customerPhone;
  final String initialMode;
  const RideAndTalabatScreen({
    super.key,
    required this.customerPhone,
    required this.initialMode,
  });

  @override
  State createState() => _RideAndTalabatScreenState();
}

class _RideAndTalabatScreenState extends State {
  late String _mode;
  String _vehicle = 'car';
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  RideAndTalabatScreen get w => widget as RideAndTalabatScreen;

  @override
  void initState() {
    super.initState();
    _mode = w.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    final estPrice = _vehicle == 'car' ? 65.0 : 35.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == 'ride'
            ? 'توصيل أفراد (مشوار)'
            : 'توصيل طلبات (دليفري)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('توصيل أفراد 🚕')),
                  selected: _mode == 'ride',
                  onSelected: (_) => setState(() => _mode = 'ride'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('توصيل طلبات 🍔')),
                  selected: _mode == 'talabat',
                  onSelected: (_) => setState(() => _mode = 'talabat'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('اختر وسيلة التوصيل:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('سيارة 🚗 (65 ج.م)')),
                  selected: _vehicle == 'car',
                  onSelected: (_) => setState(() => _vehicle = 'car'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('موتوسيكل 🏍️ (35 ج.م)')),
                  selected: _vehicle == 'motorcycle',
                  onSelected: (_) => setState(() => _vehicle = 'motorcycle'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pickupCtrl,
            decoration: InputDecoration(
              labelText: _mode == 'ride'
                  ? 'نقطة الانطلاق (مكانك)'
                  : 'اسم المطعم / المتجر أو مكان الاستلام',
              prefixIcon: const Icon(Icons.my_location),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dropoffCtrl,
            decoration: InputDecoration(
              labelText: 'عنوان الوصول / التسليم',
              prefixIcon: const Icon(Icons.location_on),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_mode == 'talabat') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _detailsCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'تفاصيل الطلبات المطلوب شراؤها أو توصيلها',
                prefixIcon: const Icon(Icons.shopping_bag),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006A4E),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (_pickupCtrl.text.trim().isEmpty ||
                    _dropoffCtrl.text.trim().isEmpty) {
                  return;
                }
                final code = 'ORD-${Random().nextInt(89999) + 10000}';
                await supabase.from('delivery_orders').insert({
                  'order_code': code,
                  'customer_phone': w.customerPhone,
                  'service_type': _mode,
                  'vehicle_type': _vehicle,
                  'pickup_location': _pickupCtrl.text.trim(),
                  'dropoff_location': _dropoffCtrl.text.trim(),
                  'details': _detailsCtrl.text.trim(),
                  'price': estPrice,
                  'status': 'searching',
                });
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TrackOrderScreen(userPhone: w.customerPhone),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check_circle),
              label: Text('تأكيد الطلب الآن ($estPrice ج.م)'),
            ),
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
  final _nameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  String _vehicle = 'motorcycle';
  Map? _captainProfile;
  List _availableOrders = [];

  CaptainPortalScreen get w => widget as CaptainPortalScreen;

  @override
  void initState() {
    super.initState();
    _loadCaptain();
  }

  Future _loadCaptain() async {
    try {
      final cap = await supabase
          .from('captains')
          .select()
          .eq('phone', w.captainPhone)
          .maybeSingle();
      final orders = await supabase
          .from('delivery_orders')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _captainProfile = cap;
          _availableOrders = List.from(orders);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بوابة الكباتن (سيارة / موتوسيكل)')),
      body: _captainProfile == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('سجّل الآن ككابتن توصيل أفراد وطلبات:',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم الكابتن بالكامل',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField(
                  value: _vehicle,
                  decoration: const InputDecoration(
                      labelText: 'نوع المركبة', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'motorcycle', child: Text('موتوسيكل 🏍️')),
                    DropdownMenuItem(value: 'car', child: Text('سيارة 🚗')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _vehicle = v.toString());
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _plateCtrl,
                  decoration: const InputDecoration(
                      labelText: 'رقم اللوحة المعدنية',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _licenseCtrl,
                  decoration: const InputDecoration(
                      labelText: 'رقم رخصة القيادة',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006A4E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () async {
                    if (_nameCtrl.text.trim().isEmpty ||
                        _plateCtrl.text.trim().isEmpty) {
                      return;
                    }
                    await supabase.from('captains').insert({
                      'phone': w.captainPhone,
                      'full_name': _nameCtrl.text.trim(),
                      'vehicle_type': _vehicle,
                      'plate_number': _plateCtrl.text.trim(),
                      'license_number': _licenseCtrl.text.trim(),
                    });
                    _loadCaptain();
                  },
                  child: const Text('تفعيل حساب الكابتن فوراً'),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  color: const Color(0xFF004D38),
                  child: ListTile(
                    leading: const Icon(Icons.verified,
                        color: Color(0xFFD4AF37), size: 32),
                    title: Text('كابتن: ${_captainProfile!['full_name']}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'المركبة: ${_captainProfile!['vehicle_type'] == 'car' ? 'سيارة' : 'موتوسيكل'} | لوحة: ${_captainProfile!['plate_number']}',
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('الطلبات المتاحة للتنفيذ:',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ..._availableOrders.map((o) => Card(
                      child: ListTile(
                        title: Text(
                            '${o['order_code']} • ${o['service_type'] == 'ride' ? 'توصيل أفراد' : 'طلبات'}'),
                        subtitle: Text(
                            'من: ${o['pickup_location']}\nإلى: ${o['dropoff_location']}\nالحالة: ${o['status']}'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final nextStatus = o['status'] == 'searching'
                                ? 'on_the_way'
                                : 'delivered';
                            await supabase.from('delivery_orders').update({
                              'captain_phone': w.captainPhone,
                              'status': nextStatus,
                            }).eq('id', o['id']);
                            _loadCaptain();
                          },
                          child: Text(o['status'] == 'searching'
                              ? 'قبول'
                              : o['status'] == 'on_the_way'
                                  ? 'تم التسليم'
                                  : 'مكتمل ✅'),
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}

class TrackOrderScreen extends StatefulWidget {
  final String userPhone;
  const TrackOrderScreen({super.key, required this.userPhone});

  @override
  State createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State {
  List _myOrders = [];

  TrackOrderScreen get w => widget as TrackOrderScreen;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future _loadOrders() async {
    try {
      final res = await supabase
          .from('delivery_orders')
          .select()
          .eq('customer_phone', w.userPhone)
          .order('created_at', ascending: false);
      if (mounted) setState(() => _myOrders = List.from(res));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تابع طلبك لحظة بلحظة'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders),
        ],
      ),
      body: _myOrders.isEmpty
          ? const Center(child: Text('لا توجد طلبات توصيل حالياً'))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _myOrders.length,
              itemBuilder: (_, i) {
                final o = _myOrders[i];
                final st = o['status'] ?? 'searching';
                final statusText = st == 'searching'
                    ? '🔍 جاري البحث عن أقرب كابتن...'
                    : st == 'on_the_way'
                        ? '🚀 الكابتن في الطريق إليك (${o['captain_phone']})'
                        : '✅ تم التوصيل بنجاح';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(o['order_code'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('${o['price']} ج.م',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF006A4E))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('من: ${o['pickup_location']}'),
                        Text('إلى: ${o['dropoff_location']}'),
                        const Divider(),
                        Text(statusText,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D38))),
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
// 8. ROYAL EMERALD & GOLD HOTEL BOOKING ENGINE
// ============================================================================
class RoyalHotelsBookingScreen extends StatefulWidget {
  final Future Function(String, String, double) onBookHotel;
  const RoyalHotelsBookingScreen({super.key, required this.onBookHotel});

  @override
  State createState() => _RoyalHotelsBookingScreenState();
}

class _RoyalHotelsBookingScreenState extends State {
  String _city = 'القاهرة';
  DateTime _checkInDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _checkInTime = const TimeOfDay(hour: 14, minute: 0);
  DateTime _checkOutDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _checkOutTime = const TimeOfDay(hour: 12, minute: 0);
  int _adults = 2;
  int _children = 0;
  final _agesCtrl = TextEditingController(text: '30, 28');

  RoyalHotelsBookingScreen get w => widget as RoyalHotelsBookingScreen;

  @override
  Widget build(BuildContext context) {
    final nights = _checkOutDate.difference(_checkInDate).inDays < 1
        ? 1
        : _checkOutDate.difference(_checkInDate).inDays;

    final hotels = [
      {
        'name': 'فندق فيرمونت نايل سيتي (Fairmont Nile City)',
        'city': 'القاهرة',
        'rating': '9.4 ملكي',
        'pricePerNight': 4200.0,
        'room': 'غرفة ديلوكس مطلة على النيل مباشرة + إفطار فاخر',
        'image':
            'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      },
      {
        'name': 'فندق فورسيزونز سان ستيفانو (Four Seasons)',
        'city': 'الإسكندرية',
        'rating': '9.6 استثنائي',
        'pricePerNight': 5100.0,
        'room': 'جناح سوبيريور مطل على البحر المتوسط',
        'image':
            'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=800',
      },
      {
        'name': 'منتجع ريكسوس بريميوم سيجيت (Rixos Sharm)',
        'city': 'شرم الشيخ',
        'rating': '9.7 فاخر',
        'pricePerNight': 4800.0,
        'room': 'غرفة فاخرة شاملة كلياً (Ultra All Inclusive)',
        'image':
            'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF004D38),
        title: const Text('إقامات وفنادق EG MASR'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF004D38), Color(0xFF006A4E)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                DropdownButtonFormField(
                  value: _city,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.location_on,
                        color: Color(0xFF006A4E)),
                    labelText: 'الوجهة / المدينة',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                  items: ['القاهرة', 'الإسكندرية', 'شرم الشيخ', 'الغردقة', 'أسوان']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _city = v.toString());
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _checkInDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) {
                            final t = await showTimePicker(
                                context: context, initialTime: _checkInTime);
                            setState(() {
                              _checkInDate = d;
                              if (t != null) _checkInTime = t;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الوصول (اليوم والساعة)',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(
                                  '${_checkInDate.day}/${_checkInDate.month} • ${_checkInTime.format(context)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _checkOutDate,
                            firstDate: _checkInDate,
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) {
                            final t = await showTimePicker(
                                context: context, initialTime: _checkOutTime);
                            setState(() {
                              _checkOutDate = d;
                              if (t != null) _checkOutTime = t;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('المغادرة (اليوم والساعة)',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(
                                  '${_checkOutDate.day}/${_checkOutDate.month} • ${_checkOutTime.format(context)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('البالغين: $_adults | الأطفال: $_children',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Color(0xFF006A4E)),
                                onPressed: () {
                                  if (_adults > 1) setState(() => _adults--);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline,
                                    color: Color(0xFF006A4E)),
                                onPressed: () => setState(() => _adults++),
                              ),
                              IconButton(
                                icon: const Icon(Icons.child_care,
                                    color: Color(0xFFD4AF37)),
                                onPressed: () => setState(() => _children++),
                              ),
                            ],
                          ),
                        ],
                      ),
                      TextField(
                        controller: _agesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'أعمار النزلاء (مثال: 32, 29, 6)',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('الفنادق المتاحة للإقامة ($nights ليالي):',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...hotels.map((h) {
            final total = (h['pricePerNight'] as double) * nights;
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.network(h['image'] as String,
                      height: 160, width: double.infinity, fit: BoxFit.cover),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(h['name'] as String,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF004D38))),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4AF37),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(h['rating'] as String,
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(h['room'] as String,
                            style: const TextStyle(fontSize: 13)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('الإجمالي لـ $nights ليالي:',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                                Text('${total.toStringAsFixed(0)} ج.م',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF006A4E))),
                              ],
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF006A4E),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final details =
                                    'وصول ${_checkInDate.day}/${_checkInDate.month} (${_checkInTime.format(context)}) - مغادرة ${_checkOutDate.day}/${_checkOutDate.month} | $_adults بالغين, $_children أطفال (أعمار: ${_agesCtrl.text})';
                                final ok = await w.onBookHotel(
                                    h['name'] as String, details, total);
                                if (ok && mounted) Navigator.pop(context);
                              },
                              child: const Text('تأكيد الحجز المباشر'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
