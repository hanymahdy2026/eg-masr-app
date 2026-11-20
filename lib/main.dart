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
          userPhone: _savedPhone!, accountType: _accountType);
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

  String _normalizePhone(String input) {
    String p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('20') && p.length == 12) p = '0${p.substring(2)}';
    if (p.length == 10 && p.startsWith('1')) p = '0$p';
    return p;
  }

  void _sendOtpOnApp() {
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
    final code = (100000 + Random().nextInt(899999)).toString();
    setState(() {
      _generatedOtp = code;
      _otpSent = true;
      _otpCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('كود التأكيد المتغير الخاص بك هو: $code ✅'),
        backgroundColor: const Color(0xFF006A4E),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future _verifyAndEnter() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (_otpCtrl.text.trim() != _generatedOtp || _generatedOtp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('كود التأكيد غير صحيح!'), backgroundColor: Colors.red),
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
                  content: Text('طلب شركتك ما زال في انتظار موافقة الإدارة ⏳')),
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
                      child: Icon(Icons.account_balance_wallet,
                          size: 34, color: Color(0xFFD4AF37)),
                    ),
                    const SizedBox(height: 10),
                    const Text('EG MASR',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF006A4E))),
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
                          labelText: 'عنوان المنشأة',
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
                          labelText: 'الرقم الضريبي',
                          prefixIcon: const Icon(Icons.receipt_long),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _delegateCtrl,
                        decoration: InputDecoration(
                          labelText: 'اسم المفوض',
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
    _pages = [
      ChatsAndGroupsTab(currentUserPhone: w.userPhone),
      SocialFeedTab(
          currentUserPhone: w.userPhone,
          isAdmin: w.userPhone == adminPhoneNumber),
      DirectPayAndQrTab(
          currentUserPhone: w.userPhone,
          isAdmin: w.userPhone == adminPhoneNumber),
      ServicesTab(
          currentUserPhone: w.userPhone,
          isCorporate:
              w.accountType == 'corporate' || w.userPhone == adminPhoneNumber),
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
              icon: Icon(Icons.grid_view_outlined), label: 'الخدمات والتوصيل'),
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
                    decoration: const InputDecoration(labelText: 'اسم الجروب')),
                const SizedBox(height: 10),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      final ph = u['phone'].toString();
                      return CheckboxListTile(
                        value: selectedPhones.contains(ph),
                        title: Text(u['full_name'] ?? ph),
                        onChanged: (v) => setSt(() => v == true
                            ? selectedPhones.add(ph)
                            : selectedPhones.remove(ph)),
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
          actions: [
            IconButton(
                icon: const Icon(Icons.group_add),
                onPressed: _createGroupDialog)
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
                                isFriend: _friendPhones.contains(ph),
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
  final bool isFriend;
  final VoidCallback? onRelationChanged;

  const ChatRoomScreen({
    super.key,
    required this.myPhone,
    required this.roomId,
    required this.peerPhone,
    required this.title,
    required this.isGroup,
    this.isFriend = false,
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
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
      _sendMessage('📍 موقعي الحالي:\n$mapsUrl', type: 'location');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(w.title),
        actions: [
          IconButton(
              icon: const Icon(Icons.location_on),
              onPressed: _sendMyLiveLocation),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchMessages),
          if (!w.isGroup)
            PopupMenuButton(
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'friend', child: Text('إضافة كصديق 👥')),
                PopupMenuItem(
                    value: 'block',
                    child:
                        Text('حظر (Block) 🚫', style: TextStyle(color: Colors.red))),
              ],
              onSelected: (v) async {
                await supabase.from('user_relations').insert({
                  'user_phone': w.myPhone,
                  'target_phone': w.peerPhone,
                  'relation_type': v,
                });
                w.onRelationChanged?.call();
                if (v == 'block' && mounted) Navigator.pop(context);
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
                    icon: const Icon(Icons.location_on, color: Colors.red),
                    onPressed: _sendMyLiveLocation),
                IconButton(
                  icon: const Icon(Icons.photo, color: Color(0xFF006A4E)),
                  onPressed: () async {
                    final f =
                        await _picker.pickImage(source: ImageSource.gallery);
                    if (f != null) _sendMessage('📷 صورة: ${f.name}');
                  },
                ),
                Expanded(
                  child: _isRecording
                      ? Text('🔴 جاري التسجيل... $_recordSeconds ث',
                          style: const TextStyle(color: Colors.red))
                      : TextField(
                          controller: _msgCtrl,
                          decoration: const InputDecoration(
                              hintText: 'اكتب رسالتك...',
                              border: InputBorder.none),
                          onSubmitted: _sendMessage,
                        ),
                ),
                IconButton(
                    icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic),
                    onPressed: _toggleVoiceRecording),
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
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('🌍 العامة')),
                    DropdownMenuItem(
                        value: 'friends', child: Text('👥 الأصدقاء')),
                    DropdownMenuItem(value: 'only_me', child: Text('🔒 أنا فقط')),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => privacy = v.toString());
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: contentCtrl,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(hintText: 'اكتب منشورك...')),
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
                  'content': contentCtrl.text.trim(),
                  'media_url': uploadedUrl,
                  'media_type': mediaType,
                  'privacy': privacy,
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

class DirectPayAndQrTab extends StatefulWidget {
  final String currentUserPhone;
  final bool isAdmin;
  const DirectPayAndQrTab(
      {super.key, required this.currentUserPhone, required this.isAdmin});
  @override
  State createState() => _DirectPayAndQrTabState();
}

class _DirectPayAndQrTabState extends State {
  String _linkedAccount = '';
  String _uniqueQrToken = '';
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
      final hex =
          Random.secure().nextInt(99999999).toRadixString(16).toUpperCase();
      savedQr = 'EGMASR-UID-${w.currentUserPhone}-$hex';
      await prefs.setString('unique_qr_${w.currentUserPhone}', savedQr);
    }
    if (mounted) setState(() => _uniqueQrToken = savedQr!);
  }

  void _openLinkDialog() {
    final numCtrl = TextEditingController();
    String provider = 'حساب بنكي / فيزا';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ربط مباشر مع البنك أو المحفظة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              value: provider,
              items: const [
                DropdownMenuItem(
                    value: 'حساب بنكي / فيزا',
                    child: Text('حساب بنكي / فيزا')),
                DropdownMenuItem(
                    value: 'فودافون كاش', child: Text('فودافون كاش')),
                DropdownMenuItem(
                    value: 'أورانج كاش', child: Text('أورانج كاش')),
              ],
              onChanged: (v) {
                if (v != null) provider = v.toString();
              },
            ),
            TextField(
                controller: numCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'رقم البطاقة أو المحفظة')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (numCtrl.text.trim().length < 11) return;
              Navigator.pop(ctx);
              final label =
                  '$provider (****${numCtrl.text.trim().substring(numCtrl.text.trim().length - 4)})';
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                  'direct_linked_${w.currentUserPhone}', label);
              setState(() => _linkedAccount = label);
            },
            child: const Text('حفظ الربط'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الربط البنكي والباركود'),
        actions: [
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
                  Text(
                    _linkedAccount.isEmpty
                        ? 'اربط حسابك البنكي أو محفظتك للدفع المباشر'
                        : 'الحساب المرتبط:\n$_linkedAccount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _openLinkDialog,
                    icon: const Icon(Icons.account_balance),
                    label: const Text('ربط حساب بنكي / محفظة'),
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
                  const Text('الباركود الفريد الخاص بك',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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

class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  final bool isCorporate;
  const ServicesTab(
      {super.key, required this.currentUserPhone, required this.isCorporate});

  @override
  Widget build(BuildContext context) {
    final restaurants = [
      {
        'name': 'مطعم صبحي كابر (Sobhy Kaber)',
        'address': '151 شارع عبيد، شبرا، القاهرة',
        'url': 'https://www.google.com/search?q=مطعم+صبحي+كابر+الرسمي',
      },
      {
        'name': 'مطعم قصر الكبابجي (Qasr El Kababgi)',
        'address': 'التجمع الخامس / الشيخ زايد',
        'url': 'https://www.google.com/search?q=مطعم+قصر+الكبابجي+الرسمي',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('خدمات وتوصيل EG MASR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF004D38),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('التوصيل والمشاوير (أوبر / طلبات) 🚗🏍️',
                      style: TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => RideAndTalabatScreen(
                                    customerPhone: currentUserPhone,
                                    initialMode: 'ride')),
                          ),
                          child: const Text('توصيل أفراد'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => RideAndTalabatScreen(
                                    customerPhone: currentUserPhone,
                                    initialMode: 'talabat')),
                          ),
                          child: const Text('توصيل طلبات'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('المطاعم والحجز',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ...restaurants.map((r) => Card(
                child: ListTile(
                  title: Text(r['name']!),
                  subtitle: Text(r['address']!),
                  trailing: ElevatedButton(
                    onPressed: () => launchUrl(Uri.parse(r['url']!),
                        mode: LaunchMode.externalApplication),
                    child: const Text('معاينة وحجز'),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class RideAndTalabatScreen extends StatefulWidget {
  final String customerPhone;
  final String initialMode;
  const RideAndTalabatScreen(
      {super.key, required this.customerPhone, required this.initialMode});
  @override
  State createState() => _RideAndTalabatScreenState();
}

class _RideAndTalabatScreenState extends State {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  String _vehicle = 'car';
  RideAndTalabatScreen get w => widget as RideAndTalabatScreen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلب توصيل')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('سيارة 🚗')),
                    selected: _vehicle == 'car',
                    onSelected: (_) => setState(() => _vehicle = 'car'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('موتوسيكل 🏍️')),
                    selected: _vehicle == 'motorcycle',
                    onSelected: (_) => setState(() => _vehicle = 'motorcycle'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _fromCtrl,
                decoration: const InputDecoration(labelText: 'من (مكان الاستلام)')),
            const SizedBox(height: 12),
            TextField(
                controller: _toCtrl,
                decoration: const InputDecoration(labelText: 'إلى (مكان الوصول)')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (_fromCtrl.text.isEmpty || _toCtrl.text.isEmpty) return;
                await supabase.from('delivery_orders').insert({
                  'order_code': 'ORD-${Random().nextInt(89999) + 10000}',
                  'customer_phone': w.customerPhone,
                  'service_type': w.initialMode,
                  'vehicle_type': _vehicle,
                  'pickup_location': _fromCtrl.text.trim(),
                  'dropoff_location': _toCtrl.text.trim(),
                  'price': _vehicle == 'car' ? 65.0 : 35.0,
                  'status': 'searching',
                });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('تم إرسال طلبك وجاري البحث عن كابتن ✅')),
                  );
                }
              },
              child: const Text('تأكيد الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}
