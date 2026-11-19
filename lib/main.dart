import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey = 'sb_publishable_Zik6vfMWUdxgdws1wrshjg_GeiJiqcq';
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedContact = prefs.getString('user_contact');
      if (savedContact != null) {
        final res = await supabase.from('users_profiles').select().eq('contact_info', savedContact).maybeSingle();
        if (res != null) currentUser = res;
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
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
                    onUserUpdated: (u) => setState(() => currentUser = u),
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
        content: Text(isAr ? 'كود التفعيل الخاص بك: $code' : 'Your OTP Code: $code'),
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

      final existing = await supabase.from('users_profiles').select().eq('contact_info', contact).maybeSingle();

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            Text(isAr ? 'منصة مصر الشاملة' : 'EG Masr Super App', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              decoration: InputDecoration(labelText: isAr ? 'الاسم بالكامل / اسم الشركة' : 'Full Name / Company', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactCtrl,
              decoration: InputDecoration(labelText: isAr ? 'رقم الهاتف أو البريد (Gmail)' : 'Phone or Gmail', border: const OutlineInputBorder()),
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
                decoration: InputDecoration(labelText: isAr ? 'أدخل الكود ($generatedOtp)' : 'Enter OTP ($generatedOtp)', border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : _verifyAndLogin,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
                  child: busy ? const CircularProgressIndicator(color: Colors.white) : Text(isAr ? 'تأكيد الدخول' : 'Verify & Login'),
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
  final Function(Map<String, dynamic>) onUserUpdated;
  final VoidCallback onLogout;
  const SuperHomeScreen({
    super.key,
    required this.user,
    required this.lang,
    required this.onToggleLang,
    required this.onUserUpdated,
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
      WalletMeTab(user: widget.user, isAr: isAr, onUserUpdated: widget.onUserUpdated, onLogout: widget.onLogout),
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
  final _searchCtrl = TextEditingController();
  List<dynamic> users = [];
  List<dynamic> groups = [];
  String query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    var req = supabase.from('users_profiles').select().neq('contact_info', widget.user['contact_info']);
    if (query.isNotEmpty) {
      req = req.or('full_name.ilike.%$query%,contact_info.ilike.%$query%');
    }
    final u = await req.limit(50);
    final g = await supabase.from('groups').select().limit(30);
    if (mounted) setState(() { users = u; groups = g; });
  }

  Future<void> _openPhoneContacts() async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.isAr ? 'يرجى السماح بالوصول لجهات الاتصال' : 'Contacts permission required')),
        );
      }
      return;
    }
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final allAppUsers = await supabase.from('users_profiles').select().neq('contact_info', widget.user['contact_info']);

    final matched = >[];
    for (final c in contacts) {
      for (final p in c.phones) {
        final cleanPhone = p.number.replaceAll(RegExp(r'\s+|-|\+2'), '');
        for (final appU in allAppUsers) {
          final appContact = (appU['contact_info'] ?? '').toString();
          if (cleanPhone.isNotEmpty && (appContact.contains(cleanPhone) || cleanPhone.contains(appContact))) {
            if (!matched.any((m) => m['contact_info'] == appContact)) {
              matched.add({...appU, 'saved_name': c.displayName});
            }
          }
        }
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                widget.isAr ? 'جهات الاتصال المسجلة في التطبيق (${matched.length})' : 'Registered Contacts (${matched.length})',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: matched.isEmpty
                  ? Center(child: Text(widget.isAr ? 'لا يوجد أصدقاء مسجلين من هاتفك بعد' : 'No registered contacts yet'))
                  : ListView.builder(
                      controller: sc,
                      itemCount: matched.length,
                      itemBuilder: (_, i) {
                        final u = matched[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: u['avatar_url'] != null ? NetworkImage(u['avatar_url']) : null,
                            child: u['avatar_url'] == null ? const Icon(Icons.person) : null,
                          ),
                          title: Text(u['saved_name'] ?? u['full_name']),
                          subtitle: Text(u['contact_info']),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatRoomScreen(
                                  currentUser: widget.user,
                                  targetId: u['contact_info'],
                                  targetName: u['saved_name'] ?? u['full_name'],
                                  isAr: widget.isAr,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'contacts_btn',
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            onPressed: _openPhoneContacts,
            icon: const Icon(Icons.contacts),
            label: Text(widget.isAr ? 'جهات الاتصال' : 'Contacts'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'group_btn',
            backgroundColor: const Color(0xFF07C160),
            foregroundColor: Colors.white,
            onPressed: _createGroupDialog,
            icon: const Icon(Icons.group_add),
            label: Text(widget.isAr ? 'جروب جديد' : 'New Group'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                query = v.trim();
                _loadData();
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.isAr ? 'ابحث برقم الهاتف أو الاسم (حتى لو غير مسجل)...' : 'Search any phone or name...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                children: [
                  if (groups.isNotEmpty && query.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(widget.isAr ? 'نتائج البحث والمستخدمون' : 'Users', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  ...users.map((u) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: u['account_type'] == 'company' ? Colors.blue : Colors.teal,
                          backgroundImage: u['avatar_url'] != null ? NetworkImage(u['avatar_url']) : null,
                          child: u['avatar_url'] == null
                              ? Icon(u['account_type'] == 'company' ? Icons.business : Icons.person, color: Colors.white)
                              : null,
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
          ),
        ],
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
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  List<dynamic> msgs = [];
  Timer? timer;
  bool isRecording = false;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
  }

  @override
  void dispose() {
    timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final me = widget.currentUser['contact_info'];
    final target = widget.targetId;
    List<dynamic> data;
    if (target.startsWith('group_')) {
      data = await supabase.from('messages').select().eq('receiver_contact', target).order('created_at', ascending: false).limit(60);
    } else {
      data = await supabase
          .from('messages')
          .select()
          .or('and(sender_contact.eq.$me,receiver_contact.eq.$target),and(sender_contact.eq.$target,receiver_contact.eq.$me)')
          .order('created_at', ascending: false)
          .limit(60);
    }
    if (mounted) setState(() => msgs = data.reversed.toList());
  }

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    await supabase.from('messages').insert({
      'sender_name': widget.currentUser['full_name'],
      'sender_contact': widget.currentUser['contact_info'],
      'receiver_contact': widget.targetId,
      'content': text,
      'msg_type': 'text',
    });
    _fetch();
  }

  Future<void> _uploadAndSendMedia(File file, String type, String ext) async {
    setState(() => uploading = true);
    try {
      final path = 'chat_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('media').upload(path, file);
      final publicUrl = supabase.storage.from('media').getPublicUrl(path);
      await supabase.from('messages').insert({
        'sender_name': widget.currentUser['full_name'],
        'sender_contact': widget.currentUser['contact_info'],
        'receiver_contact': widget.targetId,
        'content': type == 'image' ? '📷 صورة' : (type == 'video' ? '🎥 فيديو' : '🎤 رسالة صوتية'),
        'msg_type': type,
        'media_url': publicUrl,
      });
      _fetch();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final XFile? picked = isVideo
        ? await _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 2))
        : await _picker.pickImage(source: source, imageQuality: 70);
    if (picked == null) return;
    await _uploadAndSendMedia(File(picked.path), isVideo ? 'video' : 'image', isVideo ? 'mp4' : 'jpg');
  }

  Future<void> _toggleRecordAudio() async {
    if (!isRecording) {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: filePath);
        setState(() => isRecording = true);
      }
    } else {
      final path = await _recorder.stop();
      setState(() => isRecording = false);
      if (path != null) {
        await _uploadAndSendMedia(File(path), 'audio', 'm4a');
      }
    }
  }

  void _startCall(bool isVideoCall) {
    final roomUrl = 'https://meet.jit.si/EGMasr_${widget.targetId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
    launchUrl(Uri.parse(roomUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.currentUser['contact_info'];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.targetName),
        backgroundColor: const Color(0xFF07C160),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () => _startCall(false)),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => _startCall(true)),
        ],
      ),
      body: Column(
        children: [
          if (uploading) const LinearProgressIndicator(color: Color(0xFF07C160)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final isMe = m['sender_contact'] == me;
                final type = m['msg_type'] ?? 'text';
                final mediaUrl = m['media_url'];
                final content = m['content'] ?? '';

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 270),
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
                        if (type == 'image' && mediaUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(mediaUrl, height: 180, width: 220, fit: BoxFit.cover),
                          )
                        else if (type == 'video' && mediaUrl != null)
                          InkWell(
                            onTap: () => launchUrl(Uri.parse(mediaUrl), mode: LaunchMode.externalApplication),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_circle_fill, size: 32, color: Colors.red),
                                const SizedBox(width: 8),
                                Text(widget.isAr ? 'اضغط لتشغيل الفيديو' : 'Play Video', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else if (type == 'audio' && mediaUrl != null)
                          InkWell(
                            onTap: () => _player.play(UrlSource(mediaUrl)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow, size: 30, color: Color(0xFF07C160)),
                                const SizedBox(width: 6),
                                Text(widget.isAr ? 'تشغيل التسجيل الصوتي' : 'Play Voice Note'),
                              ],
                            ),
                          )
                        else
                          InkWell(
                            onTap: () {
                              if (content.startsWith('http')) launchUrl(Uri.parse(content), mode: LaunchMode.externalApplication);
                            },
                            child: Text(
                              content,
                              style: TextStyle(
                                color: content.startsWith('http') ? Colors.blue : Colors.black87,
                                decoration: content.startsWith('http') ? TextDecoration.underline : TextDecoration.none,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.attach_file, color: Color(0xFF07C160)),
                  onSelected: (v) {
                    if (v == 'img_gal') _pickMedia(ImageSource.gallery);
                    if (v == 'img_cam') _pickMedia(ImageSource.camera);
                    if (v == 'vid_gal') _pickMedia(ImageSource.gallery, isVideo: true);
                    if (v == 'vid_cam') _pickMedia(ImageSource.camera, isVideo: true);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'img_gal', child: Text(widget.isAr ? '📷 صورة من المعرض' : 'Photo Gallery')),
                    PopupMenuItem(value: 'img_cam', child: Text(widget.isAr ? '📸 التقاط صورة' : 'Take Photo')),
                    PopupMenuItem(value: 'vid_gal', child: Text(widget.isAr ? '🎬 فيديو من المعرض' : 'Video Gallery')),
                    PopupMenuItem(value: 'vid_cam', child: Text(widget.isAr ? '🎥 تسجيل فيديو' : 'Record Video')),
                  ],
                ),
                IconButton(
                  icon: Icon(isRecording ? Icons.stop_circle : Icons.mic, color: isRecording ? Colors.red : const Color(0xFF07C160)),
                  onPressed: _toggleRecordAudio,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: isRecording
                          ? (widget.isAr ? 'جاري التسجيل الصوتي...' : 'Recording...')
                          : (widget.isAr ? 'رسالة أو رابط...' : 'Message or link...'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send, color: Color(0xFF07C160)), onPressed: _sendText),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class MomentsTab extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool isAr;
  const MomentsTab({super.key, required this.user, required this.isAr});

  @override
  State<MomentsTab> createState() => _MomentsTabState();
}

class _MomentsTabState extends State<MomentsTab> {
  List<dynamic> posts = [];

  @override
  void initState() {
    super.initState();
    _loadMoments();
  }

  Future<void> _loadMoments() async {
    final res = await supabase.from('moments').select().order('created_at', ascending: false).limit(40);
    if (mounted) setState(() => posts = res);
  }

  void _newPostDialog() {
    final pCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.isAr ? 'مشاركة لحظة جديدة' : 'New Moment'),
        content: TextField(controller: pCtrl, maxLines: 3, decoration: InputDecoration(hintText: widget.isAr ? 'بم تفكر الآن؟' : 'What is on your mind?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
            onPressed: () async {
              if (pCtrl.text.trim().isEmpty) return;
              await supabase.from('moments').insert({
                'author_name': widget.user['full_name'],
                'author_contact': widget.user['contact_info'],
                'content': pCtrl.text.trim(),
                'likes_count': 0,
              });
              if (mounted) Navigator.pop(context);
              _loadMoments();
            },
            child: Text(widget.isAr ? 'نشر' : 'Post'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF07C160),
        foregroundColor: Colors.white,
        onPressed: _newPostDialog,
        child: const Icon(Icons.edit),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMoments,
        child: posts.isEmpty
            ? Center(child: Text(widget.isAr ? 'لا توجد منشورات في اللحظات بعد' : 'No moments yet'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: posts.length,
                itemBuilder: (_, i) {
                  final p = posts[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(backgroundColor: Color(0xFF07C160), child: Icon(Icons.person, color: Colors.white)),
                              const SizedBox(width: 10),
                              Text(p['author_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(p['content'] ?? '', style: const TextStyle(fontSize: 15)),
                          const Divider(),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.favorite, color: Colors.red),
                                onPressed: () async {
                                  await supabase.from('moments').update({'likes_count': (p['likes_count'] ?? 0) + 1}).eq('id', p['id']);
                                  _loadMoments();
                                },
                              ),
                              Text('${p['likes_count'] ?? 0} ${widget.isAr ? "إعجاب" : "Likes"}'),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class ServicesTab extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool isAr;
  const ServicesTab({super.key, required this.user, required this.isAr});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  List<dynamic> companies = [];

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    final res = await supabase.from('users_profiles').select().eq('account_type', 'company').limit(50);
    if (mounted) setState(() => companies = res);
  }

  @override
  Widget build(BuildContext context) {
    final builtInServices = [
      {'title': widget.isAr ? 'حجز مطاعم وكافيهات' : 'Restaurants & Cafes', 'url': 'https://www.elmenus.com', 'icon': Icons.restaurant_menu},
      {'title': widget.isAr ? 'طلب طعام وكافيه أونلاين' : 'Food & Coffee Delivery', 'url': 'https://www.talabat.com/egypt', 'icon': Icons.local_cafe},
      {'title': widget.isAr ? 'بوابة مصر الرقمية' : 'Digital Egypt', 'url': 'https://digital.gov.eg', 'icon': Icons.account_balance},
      {'title': widget.isAr ? 'مواصلات ومترو القاهرة' : 'Cairo Metro & Transit', 'url': 'https://www.cairometro.gov.eg', 'icon': Icons.directions_subway},
      {'title': widget.isAr ? 'الاستعلام عن الفواتير' : 'Utility Bills', 'url': 'https://www.eehc.gov.eg', 'icon': Icons.receipt_long},
      {'title': widget.isAr ? 'حجز تذاكر القطارات' : 'Egypt Railways', 'url': 'https://obs.enr.gov.eg', 'icon': Icons.train},
    ];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(widget.isAr ? 'الخدمات والمطاعم والكافيهات' : 'Services, Restaurants & Cafes', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.3, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: builtInServices.length,
          itemBuilder: (_, i) {
            final s = builtInServices[i];
            return InkWell(
              onTap: () => launchUrl(Uri.parse(s['url'] as String), mode: LaunchMode.externalApplication),
              child: Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s['icon'] as IconData, color: const Color(0xFF07C160)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(s['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Text(widget.isAr ? 'الحسابات الرسمية للشركات والمطاعم' : 'Official Business & Restaurant Accounts', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (companies.isEmpty)
          Text(widget.isAr ? 'لا توجد حسابات شركات مسجلة بعد' : 'No official companies yet')
        else
          ...companies.map((c) => Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.store, color: Colors.white)),
                  title: Row(
                    children: [
                      Text(c['full_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      const Icon(Icons.verified, color: Colors.blue, size: 18),
                    ],
                  ),
                  subtitle: Text(c['contact_info']),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          currentUser: widget.user,
                          targetId: c['contact_info'],
                          targetName: c['full_name'],
                          isAr: widget.isAr,
                        ),
                      ),
                    ),
                    child: Text(widget.isAr ? 'حجز / تواصل' : 'Book / Chat'),
                  ),
                ),
              )),
      ],
    );
  }
}

class WalletMeTab extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool isAr;
  final Function(Map<String, dynamic>) onUserUpdated;
  final VoidCallback onLogout;
  const WalletMeTab({super.key, required this.user, required this.isAr, required this.onUserUpdated, required this.onLogout});

  @override
  State<WalletMeTab> createState() => _WalletMeTabState();
}

class _WalletMeTabState extends State<WalletMeTab> {
  double balance = 1000.0;
  String? avatarUrl;

  @override
  void initState() {
    super.initState();
    avatarUrl = widget.user['avatar_url'];
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    final res = await supabase.from('users_profiles').select().eq('contact_info', widget.user['contact_info']).maybeSingle();
    if (res != null && mounted) {
      setState(() {
        balance = (res['wallet_balance'] ?? 1000.0).toDouble();
        avatarUrl = res['avatar_url'];
      });
    }
  }

  Future<void> _changeProfilePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    final path = 'avatar_${widget.user['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await supabase.storage.from('media').upload(path, File(picked.path));
    final url = supabase.storage.from('media').getPublicUrl(path);
    final updated = await supabase.from('users_profiles').update({'avatar_url': url}).eq('contact_info', widget.user['contact_info']).select().single();
    widget.onUserUpdated(updated);
    if (mounted) setState(() => avatarUrl = url);
  }

  void _scanQrToPay() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(widget.isAr ? 'امسح باركود المستلم' : 'Scan Receiver QR')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final scannedData = barcodes.first.rawValue!;
                Navigator.pop(context);
                _transferDialog(prefilledReceiver: scannedData);
              }
            },
          ),
        ),
      ),
    );
  }

  void _transferDialog({String? prefilledReceiver}) {
    final toCtrl = TextEditingController(text: prefilledReceiver ?? '');
    final amtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.isAr ? 'تحويل رصيد (EG Pay)' : 'Send Money'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: toCtrl, decoration: InputDecoration(labelText: widget.isAr ? 'رقم هاتف / إيميل / كود المستلم' : 'Receiver contact or QR code')),
            const SizedBox(height: 10),
            TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: widget.isAr ? 'المبلغ بالجنيه' : 'Amount (EGP)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF07C160)),
            onPressed: () async {
              final rawInput = toCtrl.text.trim();
              final receiver = rawInput.startsWith('EGPAY:') ? rawInput.replaceFirst('EGPAY:', '') : rawInput.toLowerCase();
              final amount = double.tryParse(amtCtrl.text.trim()) ?? 0;
              if (receiver.isEmpty || amount <= 0 || amount > balance) return;

              final targetUser = await supabase
                  .from('users_profiles')
                  .select()
                  .or('contact_info.eq.$receiver,wallet_qr_code.eq.$receiver')
                  .maybeSingle();
              if (targetUser == null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isAr ? 'المستلم غير موجود' : 'User not found')));
                return;
              }

              await supabase.from('users_profiles').update({'wallet_balance': balance - amount}).eq('contact_info', widget.user['contact_info']);
              final targetBal = (targetUser['wallet_balance'] ?? 0).toDouble();
              await supabase.from('users_profiles').update({'wallet_balance': targetBal + amount}).eq('id', targetUser['id']);
              await supabase.from('wallet_transactions').insert({
                'sender_contact': widget.user['contact_info'],
                'receiver_contact': targetUser['contact_info'],
                'amount': amount,
              });

              if (mounted) Navigator.pop(context);
              _refreshBalance();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isAr ? 'تم التحويل بنجاح!' : 'Transfer successful!')));
            },
            child: Text(widget.isAr ? 'تحويل الآن' : 'Transfer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrPayload = 'EGPAY:${widget.user['wallet_qr_code'] ?? widget.user['contact_info']}';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GestureDetector(
            onTap: _changeProfilePhoto,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: const Color(0xFF07C160),
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                  child: avatarUrl == null ? const Icon(Icons.person, size: 45, color: Colors.white) : null,
                ),
                const CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.camera_alt, size: 16, color: Color(0xFF07C160))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(widget.user['full_name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(widget.user['contact_info'], style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF07C160),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(widget.isAr ? 'رصيد محفظة EG Pay' : 'EG Pay Wallet Balance', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('${balance.toStringAsFixed(2)} EGP', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF07C160)),
                        onPressed: () => _transferDialog(),
                        icon: const Icon(Icons.send_to_mobile),
                        label: Text(widget.isAr ? 'تحويل بالرقم' : 'Send'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                        onPressed: _scanQrToPay,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(widget.isAr ? 'مسح باركود' : 'Scan QR'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(widget.isAr ? 'الباركود الخاص بمحفظتك (شاركه لاستلام الأموال)' : 'Your Unique Payment QR Code', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          QrImageView(data: qrPayload, version: QrVersions.auto, size: 170),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout, color: Colors.red),
            label: Text(widget.isAr ? 'تسجيل الخروج' : 'Logout', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class AdminTab extends StatefulWidget {
  final bool isAr;
  const AdminTab({super.key, required this.isAr});

  @override
  State<AdminTab> createState() => _AdminTabState();
}

class _AdminTabState extends State<AdminTab> {
  List<dynamic> allUsers = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final res = await supabase.from('users_profiles').select().order('created_at', ascending: false).limit(100);
    if (mounted) setState(() => allUsers = res);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(widget.isAr ? 'لوحة تحكم الإدارة (أحدث ${allUsers.length} مستخدم)' : 'Admin Dashboard (${allUsers.length} users)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...allUsers.map((u) => Card(
              child: ListTile(
                title: Text('${u['full_name']} (${u['account_type']})'),
                subtitle: Text('${u['contact_info']} • الرصيد: ${u['wallet_balance']} EGP'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await supabase.from('users_profiles').delete().eq('id', u['id']);
                    _loadUsers();
                  },
                ),
              ),
            )),
      ],
    );
  }
}
