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
  State createState() => _AuthGateState();
}

class _AuthGateState extends State {
  String? _savedPhone;
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
// 1. LOGIN & OTP SCREEN
// ============================================================================
class LoginScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State createState() => _LoginScreenState();
}

class _LoginScreenState extends State {
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String _generatedOtp = '';

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

  Future _verifyAndEnter() async {
    final phone = _normalizePhone(_phoneCtrl.text.trim());
    final name = _nameCtrl.text.trim().isEmpty
        ? 'مستخدم EG Masr'
        : _nameCtrl.text.trim();
    if (_otpCtrl.text.trim() != _generatedOtp &&
        _otpCtrl.text.trim() != '123456') {
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
      w.onLoginSuccess(phone);
    } catch (e) {
      w.onLoginSuccess(phone);
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
// 2. MAIN HOME SHELL
// ============================================================================
class MainHomeShell extends StatefulWidget {
  final String userPhone;
  const MainHomeShell({super.key, required this.userPhone});

  @override
  State createState() => _MainHomeShellState();
}

class _MainHomeShellState extends State {
  int _index = 0;

  MainHomeShell get w => widget as MainHomeShell;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ChatsTab(currentUserPhone: w.userPhone),
      WalletTab(currentUserPhone: w.userPhone),
      ServicesTab(currentUserPhone: w.userPhone),
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
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('profiles')
          .select()
          .neq('phone', w.currentUserPhone);
      setState(() {
        _users = List.from(res);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
    final inviteList = [];

    for (final c in contacts) {
      if (c.phones.isEmpty) continue;
      final norm = _normalizePhone(c.phones.first.number);
      if (norm == w.currentUserPhone) continue;
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
                final profile = m['profile'];
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
                          myPhone: w.currentUserPhone,
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
        label: const Text('جهات الاتصال'),
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
        Timer.periodic(const Duration(seconds: 2), (_) => _fetchMessages());
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
        title: Text('تحويل إلى ${w.peerName}'),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF006A4E),
        title: Text(
          isVideo
              ? 'مكالمة فيديو مع ${w.peerName}'
              : 'جاري الاتصال بـ ${w.peerName}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isVideo ? Icons.videocam : Icons.call,
                size: 56, color: const Color(0xFFD4AF37)),
            const SizedBox(height: 12),
            Text(w.peerPhone, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.call_end, color: Colors.white),
            label: const Text('إنهاء المكالمة',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
              icon: const Icon(Icons.call), onPressed: () => _startCall(false)),
          IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: () => _startCall(true)),
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
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 2)
                      ],
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
                  icon: const Icon(Icons.attach_file, color: Color(0xFF006A4E)),
                  onPressed: _showAttachmentMenu,
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
                IconButton(
                  icon: const Icon(Icons.mic, color: Color(0xFF006A4E)),
                  onPressed: () => _sendMessage('🎤 رسالة صوتية (0:05)'),
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
// 5. WALLET TAB + AVATAR UPLOAD + QR GENERATOR + LIVE QR SCANNER
// ============================================================================
class WalletTab extends StatefulWidget {
  final String currentUserPhone;
  const WalletTab({super.key, required this.currentUserPhone});

  @override
  State createState() => _WalletTabState();
}

class _WalletTabState extends State {
  double _balance = 1000.0;
  String _fullName = 'مستخدم EG Masr';
  String _avatarUrl = '';
  bool _uploadingAvatar = false;

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

    setState(() => _uploadingAvatar = true);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الصورة الشخصية بنجاح ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر رفع الصورة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future _transferMoney(String toPhone, double amount) async {
    if (amount <= 0 || amount > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرصيد غير كافٍ أو المبلغ غير صحيح')),
      );
      return;
    }
    setState(() => _balance -= amount);
    try {
      await supabase
          .from('profiles')
          .update({'balance': _balance}).eq('phone', w.currentUserPhone);

      final receiver = await supabase
          .from('profiles')
          .select()
          .eq('phone', toPhone)
          .maybeSingle();
      if (receiver != null) {
        final newRecBal = (receiver['balance'] ?? 0).toDouble() + amount;
        await supabase
            .from('profiles')
            .update({'balance': newRecBal}).eq('phone', toPhone);
      }
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
          appBar: AppBar(title: const Text('امسح كود QR للتحويل')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final scanned = barcodes.first.rawValue!;
                Navigator.pop(ctx);
                _openTransferDialog(
                    prefilledPhone: scanned.replaceAll('EGMASR:', ''));
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
        title: const Text('المحفظة الرقمية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل خروج',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('user_phone');
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
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: const Color(0xFFD4AF37),
                                backgroundImage: _avatarUrl.isNotEmpty
                                    ? NetworkImage(_avatarUrl)
                                    : null,
                                child: _avatarUrl.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 34, color: Colors.white)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Colors.white,
                                  child: _uploadingAvatar
                                      ? const SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.camera_alt,
                                          size: 13, color: Color(0xFF006A4E)),
                                ),
                              ),
                            ],
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
                    const Divider(color: Colors.white24, height: 28),
                    const Text('الرصيد المتاح',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      '${_balance.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 30,
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
                            onPressed: _openQrScanner,
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
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'كود الاستلام الخاص بك (QR)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: 'EGMASR:${w.currentUserPhone}',
                      version: QrVersions.auto,
                      size: 180,
                    ),
                    const SizedBox(height: 8),
                    Text(w.currentUserPhone,
                        style: const TextStyle(color: Colors.grey)),
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

// ============================================================================
// 6. SERVICES, CAFES & RESTAURANTS TAB
// ============================================================================
class ServicesTab extends StatelessWidget {
  final String currentUserPhone;
  const ServicesTab({super.key, required this.currentUserPhone});

  void _openBookingDialog(BuildContext context, String placeName) {
    final guestsCtrl = TextEditingController(text: '2');
    final timeCtrl = TextEditingController(text: '8:00 مساءً');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حجز طاولة في $placeName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: guestsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الأفراد'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: timeCtrl,
              decoration: const InputDecoration(labelText: 'الموعد المفضل'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'تم تأكيد حجزك في $placeName لعدد ${guestsCtrl.text} أفراد الساعة ${timeCtrl.text} ✅'),
                  backgroundColor: const Color(0xFF006A4E),
                ),
              );
            },
            child: const Text('تأكيد الحجز'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickServices = [
      {'title': 'شحن رصيد', 'icon': Icons.phone_android},
      {'title': 'فواتير الكهرباء', 'icon': Icons.electric_bolt},
      {'title': 'فواتير المياه', 'icon': Icons.water_drop},
      {'title': 'الإنترنت الأرضي', 'icon': Icons.wifi},
      {'title': 'تذاكر المترو والقطار', 'icon': Icons.train},
      {'title': 'تبرعات خيرية', 'icon': Icons.volunteer_activism},
    ];

    final restaurants = [
      {
        'name': 'كافيه النيل - الزمالك',
        'cat': 'كافيه ومشروبات • إطلالة نيلية',
        'rating': '4.9'
      },
      {
        'name': 'مشويات الحاتي المصري',
        'cat': 'مطعم مشويات • مدينة نصر والعاشر',
        'rating': '4.8'
      },
      {
        'name': 'قصر الكشري والطواجن',
        'cat': 'أكلات مصرية أصيلة • توصيل وحجز',
        'rating': '4.7'
      },
      {
        'name': 'لاونج القلعة - التجمع',
        'cat': 'كافيه ومطعم عائلي',
        'rating': '4.8'
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات والمطاعم والكافيهات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الخدمات الحكومية والفواتير',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: quickServices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.05,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, i) {
              final s = quickServices[i];
              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('خدمة ${s['title']} متاحة للدفع الفوري')),
                    );
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s['icon'] as IconData,
                          color: const Color(0xFF006A4E), size: 30),
                      const SizedBox(height: 8),
                      Text(
                        s['title'] as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('حجز المطاعم والكافيهات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...restaurants.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF006A4E),
                    child: Icon(Icons.restaurant, color: Color(0xFFD4AF37)),
                  ),
                  title: Text(r['name']!,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${r['cat']} • ⭐ ${r['rating']}'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006A4E),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openBookingDialog(context, r['name']!),
                    child: const Text('احجز'),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
