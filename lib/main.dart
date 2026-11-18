import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey = 'sb_publishable_bQ1u1u3iE9h5w_g7Y5k1A_q2R8t6Y4u2';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrApp());
}

final supabase = Supabase.instance.client;

class EgMasrApp extends StatefulWidget {
  const EgMasrApp({super.key});
  @override
  State<EgMasrApp> createState() => _EgMasrAppState();
}

class _EgMasrAppState extends State<EgMasrApp> {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user_contact');
    if (saved != null) {
      final data = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', saved)
          .maybeSingle();
      if (data != null) _user = data;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EG Masr',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF075E54)),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _user == null
              ? LoginScreen(onSuccess: (u) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('user_contact', u['contact_info'].toString());
                  setState(() => _user = u);
                })
              : ChatsHomeScreen(
                  user: _user!,
                  onLogout: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_contact');
                    setState(() => _user = null);
                  },
                ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _codeSent = false;
  String _generatedCode = '';

  void _sendOtp() {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('من فضلك اكتب الاسم ورقم الهاتف أو Gmail')),
      );
      return;
    }
    final code = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    setState(() {
      _generatedCode = code;
      _codeSent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('كود التأكيد المكون من 4 أرقام: $code'),
        duration: const Duration(seconds: 20),
      ),
    );
  }

  Future<void> _verifyAndLogin() async {
    if (_otpCtrl.text.trim() != _generatedCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود التأكيد غير صحيح، تأكد من الـ 4 أرقام')),
      );
      return;
    }
    final contact = _contactCtrl.text.trim().toLowerCase();
    final res = await supabase
        .from('users_profiles')
        .upsert({
          'full_name': _nameCtrl.text.trim(),
          'contact_info': contact,
          'account_type': 'personal',
        }, onConflict: 'contact_info')
        .select()
        .single();
    widget.onSuccess(res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EG Masr - تسجيل الدخول'),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'الاسم (عربي أو English)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _contactCtrl,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف أو حساب Gmail',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            if (!_codeSent)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _sendOtp,
                  child: const Text('إرسال كود التأكيد (4 أرقام)'),
                ),
              )
            else ...[
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'أدخل كود التأكيد (4 أرقام)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _verifyAndLogin,
                  child: const Text('تأكيد والدخول للشات'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChatsHomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const ChatsHomeScreen({super.key, required this.user, required this.onLogout});

  @override
  State<ChatsHomeScreen> createState() => _ChatsHomeScreenState();
}

class _ChatsHomeScreenState extends State<ChatsHomeScreen> {
  List<dynamic> _users = [];
  List<dynamic> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final myContact = widget.user['contact_info'].toString();
    final uRes = await supabase.from('users_profiles').select();
    final gRes = await supabase.from('groups').select().order('created_at', ascending: false);

    final myGroups = List.from(gRes).where((g) {
      final members = List<String>.from(g['members'] ?? []);
      return members.contains(myContact) || g['created_by'] == myContact;
    }).toList();

    if (mounted) {
      setState(() {
        _users = List.from(uRes).where((u) => u['contact_info'] != myContact).toList();
        _groups = myGroups;
      });
    }
  }

  Future<void> _createGroupDialog() async {
    final nameCtrl = TextEditingController();
    final selected = <String>{widget.user['contact_info'].toString()};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('إنشاء جروب جديد'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم الجروب'),
                ),
                const SizedBox(height: 10),
                const Text('اختر الأعضاء:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 200,
                  child: ListView(
                    children: _users.map((u) {
                      final contact = u['contact_info'].toString();
                      return CheckboxListTile(
                        title: Text(u['full_name']?.toString() ?? ''),
                        subtitle: Text(contact),
                        value: selected.contains(contact),
                        onChanged: (v) {
                          setDlg(() {
                            if (v == true) {
                              selected.add(contact);
                            } else {
                              selected.remove(contact);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await supabase.from('groups').insert({
                  'group_name': nameCtrl.text.trim(),
                  'created_by': widget.user['contact_info'],
                  'members': selected.toList(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EG Masr'),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroupDialog,
        backgroundColor: const Color(0xFF25D366),
        icon: const Icon(Icons.group_add, color: Colors.white),
        label: const Text('جروب جديد', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        children: [
          if (_groups.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('الجروبات (Groups)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
            ),
            ..._groups.map((g) => ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFF075E54), child: Icon(Icons.groups, color: Colors.white)),
                  title: Text(g['group_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${(g['members'] as List).length} أعضاء'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatRoomScreen(
                        user: widget.user,
                        chatId: 'group_${g['id']}',
                        title: g['group_name'].toString(),
                        subtitle: '${(g['members'] as List).length} أعضاء',
                      ),
                    ),
                  ),
                )),
            const Divider(),
          ],
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('الأرقام وجهات الاتصال (1 إلى 1)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          ),
          ..._users.map((u) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(u['full_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(u['contact_info']?.toString() ?? ''),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(
                      user: widget.user,
                      chatId: u['contact_info'].toString(),
                      title: u['full_name'].toString(),
                      subtitle: u['contact_info'].toString(),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String chatId;
  final String title;
  final String subtitle;

  const ChatRoomScreen({
    super.key,
    required this.user,
    required this.chatId,
    required this.title,
    required this.subtitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  final _picker = ImagePicker();
  List<dynamic> _messages = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final res = await supabase.from('messages').select().order('created_at', ascending: true);
    final me = widget.user['contact_info'].toString();
    final target = widget.chatId;

    final list = List.from(res).where((m) {
      if (target.startsWith('group_')) {
        return m['receiver_contact'] == target;
      }
      return (m['sender_contact'] == me && m['receiver_contact'] == target) ||
          (m['sender_contact'] == target && m['receiver_contact'] == me);
    }).toList();

    if (mounted) setState(() => _messages = list);
  }

  Future<void> _send({String type = 'text', String? text, String? url}) async {
    final content = text ?? _msgCtrl.text.trim();
    if (content.isEmpty && url == null) return;
    _msgCtrl.clear();

    await supabase.from('messages').insert({
      'sender_name': widget.user['full_name'],
      'sender_contact': widget.user['contact_info'],
      'receiver_contact': widget.chatId,
      'content': content,
      'msg_type': type,
      'media_url': url,
    });
    _loadMessages();
  }

  Future<void> _sendMedia(bool isVideo) async {
    final file = isVideo
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last;
    final path = '${DateTime.now().millisecondsSinceEpoch}.$ext';

    await supabase.storage.from('chat_media').uploadBinary(path, bytes);
    final publicUrl = supabase.storage.from('chat_media').getPublicUrl(path);
    await _send(type: isVideo ? 'video' : 'image', text: isVideo ? 'فيديو - اضغط للمشاهدة' : 'صورة', url: publicUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final isMe = m['sender_contact'] == widget.user['contact_info'];
                final type = m['msg_type'] ?? 'text';
                final url = m['media_url']?.toString();
                final content = m['content']?.toString() ?? '';

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Card(
                    color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m['sender_name']} (${m['sender_contact']})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.teal),
                          ),
                          const SizedBox(height: 4),
                          if (type == 'image' && url != null)
                            Image.network(url, width: 220, height: 220, fit: BoxFit.cover)
                          else if (type == 'video' && url != null)
                            InkWell(
                              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                              child: Text(content, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                            )
                          else
                            InkWell(
                              onTap: () {
                                if (content.startsWith('http')) {
                                  launchUrl(Uri.parse(content), mode: LaunchMode.externalApplication);
                                }
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
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.image, color: Colors.teal), onPressed: () => _sendMedia(false)),
                IconButton(icon: const Icon(Icons.videocam, color: Colors.teal), onPressed: () => _sendMedia(true)),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة عربي / English أو لينك...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send, color: Color(0xFF075E54)), onPressed: () => _send()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
