import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey = 'sb_publishable_bQ1u1u3iE9h5w_g7Y5k1A_q2R8t6Y4u2';
const String adminEmail = 'h27n4y200@gmail.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrSuperApp());
}

final supabase = Supabase.instance.client;

class EgMasrSuperApp extends StatefulWidget {
  const EgMasrSuperApp({super.key});
  @override
  State<EgMasrSuperApp> createState() => _EgMasrSuperAppState();
}

class _EgMasrSuperAppState extends State<EgMasrSuperApp> {
  String lang = 'ar';
  Map<String, dynamic>? currentUser;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedContact = prefs.getString('user_contact');
    if (savedContact != null) {
      final res = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', savedContact)
          .maybeSingle();
      if (res != null) {
        currentUser = res;
      }
    }
    setState(() => loading = false);
  }

  void _toggleLang() => setState(() => lang = lang == 'ar' ? 'en' : 'ar');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EG Masr Super App',
      theme: ThemeData(
        primaryColor: const Color(0xFF07C160),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF07C160)),
        useMaterial3: true,
      ),
      home: Directionality(
        textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : currentUser == null
                ? AuthScreen(
                    lang: lang,
                    onToggleLang: _toggleLang,
                    onLoginSuccess: (u) => setState(() => currentUser = u),
                  )
                : SuperHomeScreen(
                    user: currentUser!,
                    lang: lang,
                    onToggleLang: _toggleLang,
                    onLogout: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('user_contact');
                      setState(() => currentUser = null);
                    },
                  ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final String lang;
  final VoidCallback onToggleLang;
  final Function(Map<String, dynamic>) onLoginSuccess;
  const AuthScreen({super.key, required this.lang, required this.onToggleLang, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String accountType = 'personal';
  String? generatedOtp;
  bool busy = false;

  bool get isAr => widget.lang == 'ar';

  void _sendOtp() {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isAr ? 'اكتب الاسم ورقم الهاتف أو الإيميل' : 'Enter name & phone/email')),
      );
      return;
    }
    final code = (1000 + Random().nextInt(9000)).toString();
    setState(() => generatedOtp = code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF07C160),
        duration: const Duration(seconds: 6),
        content: Text(isAr ? 'كود التفعيل الخاص بك: $code' : 'Your OTP Code:$code'),
      ),
    );
  }

  Future<void> _verifyAndLogin() async {
    if (_otpCtrl.text.trim() != generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isAr ? 'كود التفعيل غير صحيح' : 'Invalid OTP')),
      );
      return;
    }
    setState(() => busy = true);
    try {
      final contact = _contactCtrl.text.trim().toLowerCase();
      final name = _nameCtrl.text.trim();
      final isAdmin = contact == adminEmail.toLowerCase();

      final existing = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', contact)
          .maybeSingle();

      Map<String, dynamic> userData;
      if (existing != null) {
        userData = existing;
      } else {
        userData = await supabase.from('users_profiles').insert({
          'full_name': name,
          'contact_info': contact,
          'account_type': accountType,
          'wallet_balance': 1000.0,
          'is_admin': isAdmin,
        }).select().single();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_contact', contact);
      widget.onLoginSuccess(userData);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EG Masr'),
        actions: [
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(isAr ? 'English' : 'عربي', style: const TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.public, size: 72, color: Color(0xFF07C160)),
            const SizedBox(height: 12),
            Text(
              isAr ? 'منصة مصر الشاملة (شبيه WeChat)' : 'EG Masr Super App',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'personal', label: Text(isAr ? 'حساب شخصي' : 'Personal'), icon: const Icon(Icons.person)),
                ButtonSegment(value: 'company', label: Text(isAr ? 'حساب شركات' : 'Business'), icon: const Icon(Icons.business)),
              ],
              selected: {accountType},
              onSelectionChanged: (s) => setState(() => accountType = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: isAr ? 'الاسم بالكامل / اسم الشركة' : 'Full Name / Company',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactCtrl,
              decoration: InputDecoration(
                labelText: isAr ? 'رقم الهاتف أو البريد (Gmail)' : 'Phone or Gmail',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (generatedOtp == null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _sendOtp,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
                  child: Text(isAr ? 'إرسال كود التفعيل (4 أرقام)' : 'Send 4-Digit OTP'),
                ),
              )
            else ...[
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'أدخل الكود ($generatedOtp)' : 'Enter OTP ($generatedOtp)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : _verifyAndLogin,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
                  child: busy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(isAr ? 'تأكيد الدخول' : 'Verify & Login'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SuperHomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String lang;
  final VoidCallback onToggleLang;
  final VoidCallback onLogout;
  const SuperHomeScreen({
    super.key,
    required this.user,
    required this.lang,
    required this.onToggleLang,
    required this.onLogout,
  });

  @override
  State<SuperHomeScreen> createState() => _SuperHomeScreenState();
}

class _SuperHomeScreenState extends State<SuperHomeScreen> {
  int idx = 0;
  bool get isAr => widget.lang == 'ar';

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user['is_admin'] == true;
    final pages = [
      ChatsTab(user: widget.user, isAr: isAr),
      MomentsTab(user: widget.user, isAr: isAr),
      ServicesTab(user: widget.user, isAr: isAr),
      WalletMeTab(user: widget.user, isAr: isAr, onLogout: widget.onLogout),
      if (isAdmin) AdminTab(isAr: isAr),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF07C160),
        foregroundColor: Colors.white,
        title: Text(isAr ? 'EG Masr الشامل' : 'EG Masr Super'),
        actions: [
          IconButton(icon: const Icon(Icons.language), onPressed: widget.onToggleLang),
        ],
      ),
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat), label: isAr ? 'الدردشات' : 'Chats'),
          NavigationDestination(icon: const Icon(Icons.camera), label: isAr ? 'اللحظات' : 'Moments'),
          NavigationDestination(icon: const Icon(Icons.grid_view), label: isAr ? 'الخدمات' : 'Services'),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet), label: isAr ? 'محفظتي' : 'Me & Pay'),
          if (isAdmin) NavigationDestination(icon: const Icon(Icons.admin_panel_settings), label: isAr ? 'الإدارة' : 'Admin'),
        ],
      ),
    );
  }
}

class ChatsTab extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool isAr;
  const ChatsTab({super.key, required this.user, required this.isAr});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  List<dynamic> users = [];
  List<dynamic> groups = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final u = await supabase.from('users_profiles').select().neq('contact_info', widget.user['contact_info']);
    final g = await supabase.from('groups').select();
    if (mounted) setState(() { users = u; groups = g; });
  }

  void _createGroupDialog() {
    final gCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.isAr ? 'إنشاء جروب جديد' : 'New Group'),
        content: TextField(controller: gCtrl, decoration: InputDecoration(hintText: widget.isAr ? 'اسم الجروب' : 'Group name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () async {
              if (gCtrl.text.trim().isEmpty) return;
              await supabase.from('groups').insert({
                'group_name': gCtrl.text.trim(),
                'created_by': widget.user['contact_info'],
                'members': [widget.user['contact_info']],
              });
              if (mounted) Navigator.pop(context);
              _loadData();
            },
            child: Text(widget.isAr ? 'إنشاء' : 'Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF07C160),
        foregroundColor: Colors.white,
        onPressed: _createGroupDialog,
        icon: const Icon(Icons.group_add),
        label: Text(widget.isAr ? 'جروب جديد' : 'New Group'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: [
            if (groups.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.isAr ? 'المجموعات (Groups)' : 'Groups', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              ...groups.map((g) => ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFF07C160), child: Icon(Icons.groups, color: Colors.white)),
                    title: Text(g['group_name']),
                    subtitle: Text(widget.isAr ? 'جروب عام' : 'Group Chat'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          currentUser: widget.user,
                          targetId: 'group_${g['id']}',
                          targetName: g['group_name'],
                          isAr: widget.isAr,
                        ),
                      ),
                    ),
                  )),
            ],
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.isAr ? 'المستخدمون وجهات الاتصال' : 'Contacts & Users', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            ...users.map((u) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: u['account_type'] == 'company' ? Colors.blue : Colors.teal,
                    child: Icon(u['account_type'] == 'company' ? Icons.business : Icons.person, color: Colors.white),
                  ),
                  title: Row(
                    children: [
                      Text(u['full_name']),
                      if (u['account_type'] == 'company') ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: Colors.blue, size: 16),
                      ]
                    ],
                  ),
                  subtitle: Text(u['contact_info']),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatRoomScreen(
                        currentUser: widget.user,
                        targetId: u['contact_info'],
                        targetName: u['full_name'],
                        isAr: widget.isAr,
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final String targetId;
  final String targetName;
  final bool isAr;
  const ChatRoomScreen({super.key, required this.currentUser, required this.targetId, required this.targetName, required this.isAr});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  List<dynamic> msgs = [];
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final me = widget.currentUser['contact_info'];
    final target = widget.targetId;
    final data = await supabase.from('messages').select().order('created_at', ascending: true);
    final filtered = data.where((m) {
      if (target.startsWith('group_')) return m['receiver_contact'] == target;
      return (m['sender_contact'] == me && m['receiver_contact'] == target) ||
          (m['sender_contact'] == target && m['receiver_contact'] == me);
    }).toList();
    if (mounted) setState(() => msgs = filtered);
  }

  Future<void> _send({String type = 'text', String? overrideText}) async {
    final text = overrideText ?? _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    await supabase.from('messages').insert({
      'sender_name': widget.currentUser['full_name'],
      'sender_contact': widget.currentUser['contact_info'],
      'receiver_contact': widget.targetId,
      'content': text,
      'msg_type': type,
    });
    _fetch();
  }

  Future<void> _pickMedia(bool isVideo) async {
    final picker = ImagePicker();
    final file = isVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      _send(type: isVideo ? 'video' : 'image', overrideText: '${isVideo ? "🎥 فيديو" : "🖼️ صورة"}: ${file.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.currentUser['contact_info'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.targetName), backgroundColor: const Color(0xFF07C160), foregroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final isMe = m['sender_contact'] == me;
                final content = m['content'] ?? '';
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF95EC69) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe) Text(m['sender_name'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
                        InkWell(
                          onTap: () {
                            if (content.startsWith('http')) {
                              launchUrl(Uri.parse(content), mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Text(
                            content,
                            style: TextStyle(
                              color: content.startsWith('http') ? Colors.blue : Colors
