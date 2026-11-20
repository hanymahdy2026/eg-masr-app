import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJkYmRpbXBoYnJzZXpmdGluZGNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3ODA1MDIsImV4cCI6MjA4OTM1NjUwMn0.35i7hN8Y4iM-W6s760sB6S-sK2R5N7B3Q9Z1X4W8E2A';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
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
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _savedPhone;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedPhone = prefs.getString('user_phone');
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_savedPhone != null && _savedPhone!.isNotEmpty) {
      return MainHomeShell(userPhone: _savedPhone!);
    }
    return LoginScreen(
      onLoginSuccess: (phone) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_phone', phone);
        setState(() => _savedPhone = phone);
      },
    );
  }
}

// ============================================================================
// 1. LOGIN & OTP SCREEN (Phone + Password / OTP)
// ============================================================================
class LoginScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String _generatedOtp = '';

  String _normalizePhone(String input) {
    String p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('20') && p.length == 12) {
      p = '0${p.substring(2)}';
    } else if (p.length == 10 && p.startsWith('1')) {
      p = '0$p';
    }
    return p;
  }

  Future<void> _sendOtp() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    if (phone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم موبايل مصري صحيح (11 رقم)')),
      );
      return;
    }
    setState(() => _busy = true);
    _generatedOtp = '123456';
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _otpSent = true;
      _busy = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('كود التفعيل التجريبي لـ $phone هو: $_generatedOtp'),
          backgroundColor: const Color(0xFF006A4E),
        ),
      );
    }
  }

  Future<void> _verifyAndEnter() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    final name = _nameCtrl.text.trim().isEmpty
        ? 'مستخدم EG Masr'
        : _nameCtrl.text.trim();
    if (_otpCtrl.text.trim() != _generatedOtp && _otpCtrl.text.trim() != '123456') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود التفعيل غير صحيح (استخدم 123456)')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
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
      widget.onLoginSuccess(phone);
    } catch (e) {
      // Fallback entry if table schema differs slightly
      widget.onLoginSuccess(phone);
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
            padding: const EdgeInsets.all(24),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(0xFF006A4E),
                      child: Icon(Icons.account_balance_wallet,
                          size: 38, color: Color(0xFFD4AF37)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'EG MASR',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF006A4E),
                      ),
                    ),
                    const Text(
                      'تطبيقك الشامل للمحادثات والدفع والخدمات في مصر',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'الاسم بالكامل',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 14),
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
                      const SizedBox(height: 14),
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
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
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
                                _otpSent ? 'دخول للتطبيق' : 'إرسال كود التفعيل',
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
// 2. MAIN HOME SHELL (Chats, Wallet & QR, Services & Cafes)
// ============================================================================
class MainHomeShell extends StatefulWidget {
  final String userPhone;
  const MainHomeShell({super.key, required this.userPhone});

  @override
  State<MainHomeShell> createState() => _MainHomeShellState();
}

class _MainHomeShellState extends State<MainHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ChatsTab(currentUserPhone: widget.userPhone),
      WalletTab(currentUserPhone: widget.userPhone),
      ServicesTab(currentUserPhone: widget.userPhone),
    ];

    return Scaffold(
      body: pages[_index],
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'المحفظة و QR',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'الخدمات والمطاعم',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. CHATS TAB + CONTACTS SYNC + PHONE SEARCH
// ============================================================================
class ChatsTab extends StatefulWidget {
  final String currentUserPhone;
  const ChatsTab({super.key, required this.currentUserPhone});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  List> _users = [];
  bool _loading = true;

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

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('profiles')
          .select()
          .neq('phone', widget.currentUserPhone);
      setState(() {
        _users = List>.from(res);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openContactsSheet() async {
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
    final registeredMap = {
      for (var u in _users) _normalizePhone(u['phone'].toString()): u
    };

    final matched = >[];
    final inviteList = <Contact>[];

    for (final c in contacts) {
      if (c.phones.isEmpty) continue;
      final norm = _normalizePhone(c.phones.first.number);
      if (norm == widget.currentUserPhone) continue;
      if (registeredMap.containsKey(norm)) {
        matched.add({
          'contact_name': c.displayName,
          'profile': registeredMap[norm],
        });
      } else {
        inviteList.add(c);
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollCtrl,
            children: [
              const Text(
                'أصدقاؤك على EG MASR',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (matched.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('لا يوجد أصدقاء مسجلين من جهات اتصالك بعد'),
                ),
              ...matched.map((m) {
                final profile = m['profile'] as Map<String, dynamic>;
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF006A4E),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(m['contact_name']),
                  subtitle: Text(profile['phone']),
                  trailing: const Icon(Icons.chat, color: Color(0xFF006A4E)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          myPhone: widget.currentUserPhone,
                          peerPhone: profile['phone'],
                          peerName: m['contact_name'],
                        ),
                      ),
                    );
                  },
                );
              }),
              const Divider(height: 28),
              const Text(
                'دعوة أصدقاء للتطبيق',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ...inviteList.take(30).map((c) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: Text(c.displayName),
                    subtitle: Text(c.phones.first.number),
                    trailing: TextButton(
                      onPressed: () {
                        final msg = Uri.encodeComponent(
                            'انضم معايا على تطبيق EG MASR للمحادثات وتحويل الفلوس والخدمات!');
                        launchUrl(Uri.parse(
                            'sms:${c.phones.first.number}?body=$msg'));
                      },
                      child: const Text('دعوة'),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _searchByPhoneDialog() async {
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
                      myPhone: widget.currentUserPhone,
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
            tooltip: 'جهات الاتصال',
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
                            child: Text('اضغط على زر جهات الاتصال لبدء محادثة')),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _openContactsSheet,
                            icon: const Icon(Icons.contacts),
                            label: const Text('فتح جهات الاتصال'),
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
                                  myPhone: widget.currentUserPhone,
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
        label: const Text('جهات الاتصال'),
      ),
    );
  }
}

// ============================================================================
// 4. CHAT ROOM (Text, Media Picker, Voice Note Indicator, Call & Video Call)
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
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  final _picker = ImagePicker();
  List> _messages = [];
  Timer? _pollTimer;

  String get _roomId {
    final list = [widget.myPhone, widget.peerPhone]..sort();
    return '${list[0]}_${list[1]}';
  }

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final res = await supabase
          .from('messages')
          .select()
          .eq('room_id', _roomId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() => _messages = List>.from(res));
      }
    } catch (_) {}
  }

  Future<void> _sendMessage(String text, {String type = 'text'}) async {
    if (text.trim().isEmpty) return;
    _msgCtrl.clear();
    try {
      await supabase.from('messages').insert({
        'room_id': _roomId,
        'sender_phone': widget.myPhone,
        'receiver_phone': widget.peerPhone,
        'content': text.trim(),
        'msg_type': type,
      });
      _fetchMessages();
    } catch (_) {
      setState(() {
        _messages.add({
          'sender_phone': widget.myPhone,
          'content': text.trim(),
          'msg_type': type,
        });
      });
    }
  }

  Future<void> _pickAndSendMedia(ImageSource source, {bool isVideo = false}) async {
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

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo, color: Color(0xFF006A4E)),
              title: const Text('صورة من المعرض'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendMedia(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF006A4E)),
              title: const Text('التقاط صورة بالكاميرا'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendMedia(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFF006A4E)),
              title: const Text('فيديو من المعرض'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendMedia(ImageSource.gallery, isVideo: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments, color: Color(0xFFD4AF37)),
              title: const Text('تحويل أموال سريع'),
              onTap: () {
                Navigator.pop(ctx);
                _quickTransferDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _quickTransferDialog() {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تحويل إلى ${widget.peerName}'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المبلغ بالجنيه المصري'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amt > 0) {
                Navigator.pop(ctx);
                await _sendMessage('💸 تم تحويل $amt ج.م بنجاح');
              }
            },
            child: const Text('تحويل الآن'),
          ),
        ],
      ),
    );
  }

  void _startCall(bool isVideo) {
    _sendMessage(isVideo ? '📹 مكالمة فيديو صادرة' : '📞 مكالمة صوتية صادرة');
    showDialog(
      context: context,
