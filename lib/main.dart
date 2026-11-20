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
// 1. LOGIN SCREEN (DYNAMIC RANDOM OTP + INDIVIDUAL & CORPORATE)
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
          const SnackBar(
              content: Text('يرجى استكمال جميع بيانات المنشأة والمفوض')),
        );
        return;
      }
    }

    final newCode = (100000 + Random.secure().nextInt(900000)).toString();
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
              Text('كود التحقق (OTP)'),
            ],
          ),
          content: Text(
            'كود الدخول المتغير الخاص برقم $phone هو:\n\n$newCode',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
        const SnackBar(content: Text('كود التفعيل غير صحيح!')),
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
// 2. MAIN HOME SHELL (4 TABS: CHATS/GROUPS, FEED, WALLET, SERVICES/BOOKING)
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'المحفظة',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'الخدمات',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. CHATS (1-TO-1 + UNLIMITED GROUPS + BLOCK + REPORT + FRIENDS)
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

  void _createUnlimitedGroupDialog() {
    final nameCtrl = TextEditingController();
    final selectedPhones = {w.currentUserPhone};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('إنشاء جروب مفتوح العدد 👥'),
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
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('اختر الأعضاء (عدد مفتوح):',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
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
              child: const Text('إنشاء الجروب'),
            ),
          ],
        ),
      ),
    );
  }

  Future _openContactsSheet() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) return;
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
              Tab(text: 'محادثات خاصة (1 إلى 1)'),
              Tab(text: 'الجروبات (مفتوحة العدد)'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.group_add),
              tooltip: 'إنشاء جروب',
              onPressed: _createUnlimitedGroupDialog,
            ),
            IconButton(
              icon: const Icon(Icons.contacts),
              onPressed: _openContactsSheet,
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
                        subtitle: Text('عدد الأعضاء: ${members.length} عضو'),
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
          onPressed: _createUnlimitedGroupDialog,
          icon: const Icon(Icons.group_add),
          label: const Text('جروب جديد'),
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
            labelText: 'سبب الإبلاغ (إزعاج / احتيال / محتوى مخالف)',
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

  void _addMemberToGroupDialog() {
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة عضو جديد للجروب'),
        content: TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'رقم موبايل العضو'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final p = phoneCtrl.text.trim();
              if (p.length >= 11 && w.groupId != null) {
                Navigator.pop(ctx);
                final updated = List.from(w.groupMembers ?? [])..add(p);
                await supabase
                    .from('groups')
                    .update({'members': updated}).eq('id', w.groupId!);
                w.onRelationChanged?.call();
                _sendMessage('➕ قام ${w.myPhone} بإضافة $p إلى الجروب');
              }
            },
            child: const Text('إضافة'),
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
              icon: const Icon(Icons.refresh), onPressed: _fetchMessages),
          if (w.isGroup)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: _addMemberToGroupDialog,
            )
          else
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
                          m['content'].toString(),
                          style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87),
                        ),
                      ],
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
// 4. SOCIAL FEED TAB (FACEBOOK / INSTAGRAM STYLE + PRIVACY + BLOCK + REPORT)
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
  Set _friends = {};
  Set _blocked = {};
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
          _friends = fr;
          _blocked = bl;
          _posts = filtered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCreatePostDialog() {
    final contentCtrl = TextEditingController();
    String privacy = 'public';
    String mediaType = 'text';
    String? uploadedUrl;
    final picker = ImagePicker();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('إنشاء منشور جديد في الموجز'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  value: privacy,
                  decoration: const InputDecoration(
                    labelText: 'خصوصية المنشور (من يمكنه الرؤية؟)',
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
                    hintText: 'بم تفكر؟ شارك صورك أو فيديوهاتك القصيرة...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final img = await picker.pickImage(
                              source: ImageSource.gallery, imageQuality: 70);
                          if (img != null) {
                            try {
                              final bytes = await img.readAsBytes();
                              final path =
                                  'post_${DateTime.now().millisecondsSinceEpoch}.jpg';
                              await supabase.storage
                                  .from('avatars')
                                  .uploadBinary(path, bytes);
                              final url = supabase.storage
                                  .from('avatars')
                                  .getPublicUrl(path);
                              setSt(() {
                                uploadedUrl = url;
                                mediaType = 'image';
                              });
                            } catch (_) {
                              setSt(() => mediaType = 'image');
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
                        onPressed: () async {
                          final vid = await picker.pickVideo(
                              source: ImageSource.gallery);
                          if (vid != null) {
                            setSt(() {
                              uploadedUrl = vid.name;
                              mediaType = 'video';
                            });
                          }
                        },
                        icon: const Icon(Icons.video_library),
                        label: const Text('فيديو قصير'),
                      ),
                    ),
                  ],
                ),
                if (mediaType != 'text')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        mediaType == 'image'
                            ? '✅ تم إرفاق صورة'
                            : '🎬 تم إرفاق فيديو قصير (Reels)',
                        style: const TextStyle(color: Colors.green)),
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
                if (contentCtrl.text.trim().isEmpty && mediaType == 'text') {
                  return;
                }
                Navigator.pop(ctx);
                await supabase.from('posts').insert({
                  'author_phone': w.currentUserPhone,
                  'author_name': _myName,
                  'content': contentCtrl.text.trim(),
                  'media_url': uploadedUrl ?? '',
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
                    label: const Text('انشر أول بوست أو فيديو قصير'),
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
                                if (p['author_phone'] != w.currentUserPhone)
                                  PopupMenuButton(
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'friend',
                                          child: Text('إضافة صديق 👥')),
                                      const PopupMenuItem(
                                          value: 'block',
                                          child: Text('حظر (Block) 🚫',
                                              style: TextStyle(
                                                  color: Colors.red))),
                                      const PopupMenuItem(
                                          value: 'report',
                                          child: Text('إبلاغ للأدمن 🚨',
                                              style: TextStyle(
                                                  color: Colors.orange))),
                                    ],
                                    onSelected: (v) async {
                                      final target =
                                          p['author_phone'].toString();
                                      if (v == 'friend') {
                                        await supabase
                                            .from('user_relations')
                                            .insert({
                                          'user_phone': w.currentUserPhone,
                                          'target_phone': target,
                                          'relation_type': 'friend',
                                        });
                                        _loadFeed();
                                      } else if (v == 'block') {
                                        await supabase
                                            .from('user_relations')
                                            .insert({
                                          'user_phone': w.currentUserPhone,
                                          'target_phone': target,
                                          'relation_type': 'block',
                                        });
                                        _loadFeed();
                                      } else if (v == 'report') {
                                        await supabase.from('reports').insert({
                                          'reporter_phone': w.currentUserPhone,
                                          'reported_phone': target,
                                          'reason':
                                              'إبلاغ عن منشور مخالف في الموجز',
                                        });
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'وصل البلاغ للأدمن فوراً 🚨')),
                                          );
                                        }
                                      }
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if ((p['content'] ?? '').toString().isNotEmpty)
                              Text(p['content'],
                                  style: const TextStyle(fontSize: 15)),
                            if (p['media_type'] == 'image' &&
                                (p['media_url'] ?? '')
                                    .toString()
                                    .startsWith('http')) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(p['media_url'],
                                    fit: BoxFit.cover),
                              ),
                            ] else if (p['media_type'] == 'video') ...[
                              const SizedBox(height: 10),
                              Container(
                                height: 140,
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.play_circle_fill,
                                          color: Color(0xFFD4AF37), size: 48),
                                      Text('فيديو قصير (EG MASR Reels)',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ],
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
                                          content: Text(
                                              'تمت مشاركة المنشور على صفحتك ✅')),
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
// 5. WALLET TAB (EG MASR QR + WALLETS + ADMIN REPORTS & COMPANIES)
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
  String _linkedMethod = '';
  List _txHistory = [];

  WalletTab get w => widget as WalletTab;

  @override
  void initState() {
    super.initState();
    _loadAllWalletData();
  }

  Future _loadAllWalletData() async {
    final prefs = await SharedPreferences.getInstance();
    _linkedMethod =
        prefs.getString('linked_method_${w.currentUserPhone}') ?? '';
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

  void _openLinkPaymentMethodDialog() {
    String selectedProvider = 'فودافون كاش (Vodafone Cash)';
    final numberCtrl = TextEditingController();
    final depositCtrl = TextEditingController();

    final providers = [
      'بطاقة بنكية (Visa / Mastercard / Meeza)',
      'فودافون كاش (Vodafone Cash)',
      'أورانج كاش (Orange Cash)',
      'اتصالات كاش (e& Money)',
      'وي باي (WE Pay)',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('ربط فيزا أو محفظة إلكترونية'),
          content: SingleChildScrollView(
            child: Column(
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
                    labelText: selectedProvider.contains('بطاقة')
                        ? 'رقم الفيزا (16 رقم)'
                        : 'رقم المحفظة (01xxxxxxxxx)',
                  ),
                ),
                const SizedBox(height: 12),
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final numStr = numberCtrl.text.trim();
                final amt = double.tryParse(depositCtrl.text.trim()) ?? 0.0;
                if (numStr.length < 11) return;
                Navigator.pop(ctx);
                final last4 = numStr.substring(numStr.length - 4);
                final label = '$selectedProvider (****$last4)';
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                    'linked_method_${w.currentUserPhone}', label);

                final newBal = _balance + amt;
                final ref = 'EGM${Random().nextInt(899999) + 100000}';
                setState(() {
                  _linkedMethod = label;
                  _balance = newBal;
                });

                await supabase
                    .from('profiles')
                    .update({'balance': newBal}).eq(
                        'phone', w.currentUserPhone);
                if (amt > 0) {
                  await supabase.from('transactions').insert({
                    'ref_code': ref,
                    'sender_phone': 'TOPUP_WALLET',
                    'receiver_phone': w.currentUserPhone,
                    'amount': amt,
                    'tx_type': 'deposit',
                    'note': 'شحن من $label',
                  });
                }
                _loadAllWalletData();
              },
              child: const Text('ربط وشحن الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Future _executeRealTransfer(String toPhone, double amount) async {
    if (amount <= 0 || amount > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('الرصيد غير كافٍ أو المبلغ غير صحيح!'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final newSenderBal = _balance - amount;
    final ref = 'TRX${Random().nextInt(899999) + 100000}';
    setState(() => _balance = newSenderBal);

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
      'note': 'تحويل فوري إلى $toPhone',
    });

    _loadAllWalletData();
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إشعار خصم وتحويل - EG MASR'),
          content: Text(
              'تم خصم ${amount.toStringAsFixed(2)} ج.م وتحويلها إلى $toPhone.\nالرصيد المتاح: ${newSenderBal.toStringAsFixed(2)} ج.م\nمرجع: #$ref'),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('تم'))
          ],
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
        title: const Text('تحويل أموال فوري'),
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
            child: const Text('تأكيد التحويل'),
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
        title: const Text('محفظة EG MASR و QR'),
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
                  MaterialPageRoute(builder: (_) => const AdminMasterScreen()),
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
                title: const Text(
                    'لوحة تحكم الأدمن (الشركات • البلاغات • الطلبات)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminMasterScreen()),
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
                  if (_linkedMethod.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Chip(
                        backgroundColor: Colors.white12,
                        label: Text('🔗 $_linkedMethod',
                            style: const TextStyle(
                                color: Color(0xFFD4AF37), fontSize: 11)),
                      ),
                    ),
                  const Divider(color: Colors.white24, height: 24),
                  const Text('الرصيد المتاح في محفظتك',
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
                          onPressed: _openLinkPaymentMethodDialog,
                          icon: const Icon(Icons.add_card),
                          label: const Text('ربط فيزا / محفظة'),
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
                          label: const Text('تحويل فوري'),
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
                  const Text('الباركود الخاص بحسابك (EG MASR QR)',
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
          const Text('سجل العمليات المالية وكشف الحساب',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
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

class AdminMasterScreen extends StatefulWidget {
  const AdminMasterScreen({super.key});

  @override
  State createState() => _AdminMasterScreenState();
}

class _AdminMasterScreenState extends State {
  List _companies = [];
  List _reports = [];
  List _orders = [];

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
      final txs = await supabase
          .from('transactions')
          .select()
          .eq('tx_type', 'service')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _companies = List.from(comps);
          _reports = List.from(reps);
          _orders = List.from(txs);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة تحكم الأدمن الشاملة'),
          bottom: const TabBar(
            indicatorColor: Color(0xFFD4AF37),
            labelColor: Colors.white,
            tabs: [
              Tab(text: 'الشركات'),
              Tab(text: 'البلاغات 🚨'),
              Tab(text: 'طلبات الشحن/الحجز'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _companies.length,
              itemBuilder: (_, i) {
                final c = _companies[i];
                return Card(
                  child: ListTile(
                    title: Text(c['company_name'] ?? ''),
                    subtitle: Text(
                        'الضريبي: ${c['tax_id']} | الحالة: ${c['status']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          onPressed: () async {
                            await supabase
                                .from('companies')
                                .update({'status': 'approved'}).eq(
                                    'id', c['id']);
                            _loadAdminData();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () async {
                            await supabase
                                .from('companies')
                                .update({'status': 'rejected'}).eq(
                                    'id', c['id']);
                            _loadAdminData();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _reports.length,
              itemBuilder: (_, i) {
                final r = _reports[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.report, color: Colors.red),
                    title: Text('بلاغ ضد: ${r['reported_phone']}'),
                    subtitle: Text(
                        'السبب: ${r['reason']}\nالمُبلّغ: ${r['reporter_phone']}'),
                  ),
                );
              },
            ),
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final o = _orders[i];
                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.receipt, color: Color(0xFF006A4E)),
                    title: Text(o['note'] ?? ''),
                    subtitle: Text(
                        'العميل: ${o['sender_phone']} | مرجع: #${o['ref_code']}'),
                    trailing: Text('${o['amount']} ج.م',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
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
// 6. SERVICES TAB (BOOKING.COM STYLE HOTELS + REAL RESTAURANTS + BILLS/GAMES)
// ============================================================================
class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool isCorporate;
  const ServicesTab({
    super.key,
    required this.currentUserPhone,
    required this.isCorporate,
  });

  Future _chargeUserWalletAndLog(BuildContext context, double amount,
      String serviceName, String details) async {
    try {
      final prof = await supabase
          .from('profiles')
          .select()
          .eq('phone', currentUserPhone)
          .maybeSingle();
      final currentBal = (prof?['balance'] ?? 0.0).toDouble();
      if (currentBal < amount) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'رصيدك الحالي ($currentBal ج.م) غير كافٍ لإتمام العملية ($amount ج.م). اشحن محفظتك أولاً!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final newBal = currentBal - amount;
      final ref = 'EGM${Random().nextInt(899999) + 100000}';
      await supabase
          .from('profiles')
          .update({'balance': newBal}).eq('phone', currentUserPhone);
      await supabase.from('transactions').insert({
        'ref_code': ref,
        'sender_phone': currentUserPhone,
        'receiver_phone': 'EG_MASR_SERVICE',
        'amount': amount,
        'tx_type': 'service',
        'note': '$serviceName ($details)',
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
                Text('إيصال تنفيذ رسمي - EG MASR',
                    style: TextStyle(color: Color(0xFFD4AF37), fontSize: 16)),
              ],
            ),
            content: Text(
              'الخدمة: $serviceName\nالتفاصيل: $details\nالمبلغ المخصوم: ${amount.toStringAsFixed(2)} ج.م\nالرصيد المتبقي: ${newBal.toStringAsFixed(2)} ج.م\nرقم المرجع: #$ref',
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
    } catch (_) {
      return false;
    }
  }

  void _openBookingStyleHotelScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingHotelsScreen(
          onBookHotel: (hotelName, details, totalPrice) =>
              _chargeUserWalletAndLog(
                  context, totalPrice, 'حجز فندق: $hotelName', details),
        ),
      ),
    );
  }

  void _openInAppFawryBillScreen(
      BuildContext context, String title, String inputLabel) {
    final accCtrl = TextEditingController();
    double? fetchedBillAmount;
    bool queried = false;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => Scaffold(
            appBar: AppBar(title: Text('$title - EG MASR')),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: accCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: inputLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006A4E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        if (accCtrl.text.trim().length < 5) return;
                        setSt(() {
                          queried = true;
                          fetchedBillAmount =
                              (65 + Random().nextInt(280)).toDouble();
                        });
                      },
                      child: const Text('استعلام عن الفاتورة / قيمة الشحن'),
                    ),
                  ),
                  if (queried && fetchedBillAmount != null) ...[
                    const SizedBox(height: 20),
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('رقم الحساب: ${accCtrl.text}'),
                            Text(
                                'المبلغ المستحق: ${fetchedBillAmount!.toStringAsFixed(2)} ج.م',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF006A4E))),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD4AF37),
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () async {
                                  final ok = await _chargeUserWalletAndLog(
                                    context,
                                    fetchedBillAmount!,
                                    title,
                                    'رقم ${accCtrl.text}',
                                  );
                                  if (ok && ctx.mounted) Navigator.pop(ctx);
                                },
                                child: const Text('سداد وخصم من المحفظة الآن'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openInAppGameTopupScreen(BuildContext context, bool isPubg) {
    final playerIdCtrl = TextEditingController();
    final packages = isPubg
        ? [
            {'name': '60 شدة PUBG UC', 'price': 45.0},
            {'name': '325 شدة PUBG UC', 'price': 220.0},
            {'name': '660 شدة PUBG UC', 'price': 430.0},
          ]
        : [
            {'name': '100 جوهرة Free Fire', 'price': 40.0},
            {'name': '310 جوهرة Free Fire', 'price': 115.0},
            {'name': '520 جوهرة Free Fire', 'price': 190.0},
          ];
    int selectedIdx = 0;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => Scaffold(
            appBar: AppBar(
                title: Text(isPubg ? 'شحن شدات ببجي PUBG' : 'شحن جواهر فري فاير')),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: playerIdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'أدخل معرف اللاعب (Player ID)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(packages.length, (i) {
                    final pkg = packages[i];
                    return RadioListTile(
                      value: i,
                      groupValue: selectedIdx,
                      title: Text(pkg['name'] as String),
                      subtitle: Text('${pkg['price']} ج.م'),
                      onChanged: (v) {
                        if (v != null) setSt(() => selectedIdx = v as int);
                      },
                    );
                  }),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006A4E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        if (playerIdCtrl.text.trim().length < 5) return;
                        final chosen = packages[selectedIdx];
                        final ok = await _chargeUserWalletAndLog(
                          context,
                          chosen['price'] as double,
                          chosen['name'] as String,
                          'ID: ${playerIdCtrl.text.trim()}',
                        );
                        if (ok && ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('تأكيد الشحن الفوري'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openInAppTrainBookingScreen(BuildContext context) {
    String fromStation = 'القاهرة (رمسيس)';
    String toStation = 'الإسكندرية';
    double ticketPrice = 185.0;
    final stations = [
      'القاهرة (رمسيس)',
      'الإسكندرية',
      'الزقازيق',
      'طنطا',
      'المنصورة',
      'أسيوط',
      'الأقصر',
      'أسوان',
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => Scaffold(
            appBar: AppBar(title: const Text('حجز قطارات مصر (تذكرتي)')),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  DropdownButtonFormField(
                    value: fromStation,
                    decoration: const InputDecoration(labelText: 'محطة القيام'),
                    items: stations
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSt(() => fromStation = v.toString());
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField(
                    value: toStation,
                    decoration: const InputDecoration(labelText: 'محطة الوصول'),
                    items: stations
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSt(() => toStation = v.toString());
                    },
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006A4E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final ok = await _chargeUserWalletAndLog(
                          context,
                          ticketPrice,
                          'تذكرة قطار ($fromStation ⬅️ $toStation)',
                          'درجة أولى مكيفة VIP',
                        );
                        if (ok && ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text('حجز التذكرة الآن ($ticketPrice ج.م)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final realRestaurants = [
      {
        'name': 'مطعم صبحي كابر (Sobhy Kaber)',
        'cat': 'مشويات وطواجن مصرية أصيلة',
        'rating': '4.9',
        'address': '151 شارع عبيد، روض الفرج، شبرا، القاهرة',
        'hours': '11:00 صباحاً - 3:00 صباحاً',
        'website': 'https://www.facebook.com/SobhyKaberOfficial',
        'image':
            'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
      },
      {
        'name': 'مطعم قصر الكبابجي (Qasr El Kababgi)',
        'cat': 'مشويات فاخرة وضيافة ملكية',
        'rating': '4.8',
        'address': 'التجمع الخامس / الشيخ زايد / مدينة نصر',
        'hours': '12:00 ظهراً - 2:00 صباحاً',
        'website': 'https://qasrelkababgi.com',
        'image':
            'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      },
      {
        'name': 'مطعم أبو شقرة (Abou Shakra)',
        'cat': 'أشهر مطاعم المشويات في مصر منذ 1947',
        'rating': '4.7',
        'address': '69 شارع القصر العيني، جاردن سيتي، القاهرة',
        'hours': '10:00 صباحاً - 2:00 صباحاً',
        'website': 'https://aboushakragroup.com',
        'image':
            'https://images.unsplash.com/photo-1544025162-d76694265947?w=800',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('خدمات وحجوزات EG MASR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF003580),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hotel, color: Color(0xFFFEBB02), size: 28),
                    SizedBox(width: 8),
                    Text(
                      'حجز الفنادق المباشر (EG MASR Booking)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'اختر المدينة، تاريخ الوصول والمغادرة بالساعة، عدد الأفراد والأعمار واحجز غرفتك مباشرة من محفظتك.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEBB02),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _openBookingStyleHotelScreen(context),
                    icon: const Icon(Icons.search),
                    label: const Text('بحث وحجز الفنادق الآن',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('خدمات الدفع والشحن الفوري',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.6,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              _serviceTile(Icons.electric_bolt, 'فواتير الكهرباء',
                  () => _openInAppFawryBillScreen(context, 'فاتورة الكهرباء', 'رقم السداد الإلكتروني')),
              _serviceTile(Icons.phone_android, 'شحن رصيد / باقات',
                  () => _openInAppFawryBillScreen(context, 'شحن رصيد موبايل', 'رقم الموبايل')),
              _serviceTile(Icons.sports_esports, 'شدات ببجي PUBG',
                  () => _openInAppGameTopupScreen(context, true)),
              _serviceTile(Icons.videogame_asset, 'جواهر فري فاير',
                  () => _openInAppGameTopupScreen(context, false)),
              _serviceTile(Icons.train, 'قطارات مصر',
                  () => _openInAppTrainBookingScreen(context)),
              _serviceTile(Icons.flight_takeoff, 'حجز طيران',
                  () => launchUrl(Uri.parse('https://www.egyptair.com'), mode: LaunchMode.externalApplication)),
            ],
          ),
          const SizedBox(height: 22),
          const Text('أشهر المطاعم الحقيقية في مصر (معاينة وحجز)',
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
                                      Uri.parse(place['website']!),
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
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => _openRestaurantBookingForm(
                                      context, place['name']!),
                                  icon: const Icon(Icons.event_seat, size: 18),
                                  label: const Text('حجز طاولة'),
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

  Widget _serviceTile(IconData icon, String title, VoidCallback onTap) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF006A4E), size: 30),
            const SizedBox(height: 6),
            Text(title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
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
          title: Text('حجز في $restName'),
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
                title: Text('الساعة: ${selectedTime.format(ctx)}'),
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
// 7. BOOKING.COM REPLICA HOTEL SEARCH & DIRECT BOOKING ENGINE
// ============================================================================
class BookingHotelsScreen extends StatefulWidget {
  final Future Function(String, String, double) onBookHotel;
  const BookingHotelsScreen({super.key, required this.onBookHotel});

  @override
  State createState() => _BookingHotelsScreenState();
}

class _BookingHotelsScreenState extends State {
  String _city = 'القاهرة';
  DateTime _checkInDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _checkInTime = const TimeOfDay(hour: 14, minute: 0);
  DateTime _checkOutDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _checkOutTime = const TimeOfDay(hour: 12, minute: 0);
  int _adults = 2;
  int _children = 0;
  final _agesCtrl = TextEditingController(text: '30, 28');

  BookingHotelsScreen get w => widget as BookingHotelsScreen;

  @override
  Widget build(BuildContext context) {
    final nights = _checkOutDate.difference(_checkInDate).inDays < 1
        ? 1
        : _checkOutDate.difference(_checkInDate).inDays;

    final hotels = [
      {
        'name': 'فندق فيرمونت نايل سيتي (Fairmont Nile City)',
        'city': 'القاهرة',
        'rating': '9.2 استثنائي',
        'stars': 5,
        'pricePerNight': 4200.0,
        'room': 'غرفة ديلوكس مطلة على النيل مباشرة + إفطار',
        'image':
            'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      },
      {
        'name': 'فندق فورسيزونز سان ستيفانو (Four Seasons)',
        'city': 'الإسكندرية',
        'rating': '9.4 ممتاز للغاية',
        'stars': 5,
        'pricePerNight': 5100.0,
        'room': 'جناح سوبيريور مطل على البحر المتوسط',
        'image':
            'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=800',
      },
      {
        'name': 'منتجع ريكسوس بريميوم سيجيت (Rixos Sharm)',
        'city': 'شرم الشيخ',
        'rating': '9.5 رائع',
        'stars': 5,
        'pricePerNight': 4800.0,
        'room': 'غرفة فاخرة شاملة كلياً (Ultra All Inclusive)',
        'image':
            'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003580),
        title: const Text('EG MASR Booking - الفنادق'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF003580),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFEBB02), width: 3),
            ),
            child: Column(
              children: [
                DropdownButtonFormField(
                  value: _city,
                  dropdownColor: Colors.white,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.location_city),
                    labelText: 'الوجهة / المدينة',
                  ),
                  items: ['القاهرة', 'الإسكندرية', 'شرم الشيخ', 'الغردقة', 'أسوان']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _city = v.toString());
                  },
                ),
                const SizedBox(height: 8),
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
                          padding: const EdgeInsets.all(10),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('تاريخ وساعة الوصول',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(
                                  '${_checkInDate.day}/${_checkInDate.month}/${_checkInDate.year} - ${_checkInTime.format(context)}',
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
                          padding: const EdgeInsets.all(10),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('تاريخ وساعة المغادرة',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(
                                  '${_checkOutDate.day}/${_checkOutDate.month}/${_checkOutDate.year} - ${_checkOutTime.format(context)}',
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
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
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () {
                                  if (_adults > 1) setState(() => _adults--);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => setState(() => _adults++),
                              ),
                              IconButton(
                                icon: const Icon(Icons.child_care),
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
          Text('الفنادق المتاحة ($nights ليالي):',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...hotels.map((h) {
            final total = (h['pricePerNight'] as double) * nights;
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
                                      color: Color(0xFF003580))),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF003580),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(h['rating'] as String,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11)),
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
                                backgroundColor: const Color(0xFF003580),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final details =
                                    'وصول ${_checkInDate.day}/${_checkInDate.month} (${_checkInTime.format(context)}) - مغادرة ${_checkOutDate.day}/${_checkOutDate.month} | $_adults بالغين, $_children أطفال (أعمار: ${_agesCtrl.text})';
                                final ok = await w.onBookHotel(
                                    h['name'] as String, details, total);
                                if (ok && mounted) Navigator.pop(context);
                              },
                              child: const Text('احجز الغرفة الآن'),
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
