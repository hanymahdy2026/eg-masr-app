import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseAnonKey = 'sb_publishable_bQ1u1u3iE9h5w_g7Y5k1A_q2R8t6Y4u2';
const String adminEmail = 'h27n4y200@gmail.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const EgMasrApp());
}

final supabase = Supabase.instance.client;

const Map<String, Map<String, String>> appTranslations = {
  'ar': {
    'appName': 'EG Masr',
    'personal': 'حساب شخصي',
    'company': 'حساب شركات',
    'name': 'الاسم بالكامل',
    'contact': 'رقم الهاتف أو البريد الإلكتروني (Gmail)',
    'sendOtp': 'إرسال كود التفعيل (4 أرقام)',
    'enterOtp': 'أدخل كود التفعيل (4 أرقام)',
    'verify': 'تأكيد الدخول',
    'companyName': 'اسم المنشأة / الشركة',
    'companyPhone': 'رقم المنشأة',
    'address': 'عنوان المنشأة',
    'taxReg': 'رقم التسجيل الضريبي',
    'managerName': 'اسم المسؤول',
    'registerCompany': 'تسجيل المنشأة',
    'pendingApproval': 'طلبك قيد المراجعة من الإدارة',
    'chats': 'المحادثات والجروبات',
    'contacts': 'جهات الاتصال',
    'myQr': 'الباركود',
    'admin': 'الأدمن',
    'newGroup': 'إنشاء جروب جديد',
    'groupName': 'اسم الجروب',
    'selectMembers': 'اختر الأعضاء',
    'create': 'إنشاء',
    'typeMsg': 'اكتب رسالة بالعربي أو الإنجليزي أو رابط...',
    'logout': 'تسجيل خروج',
  },
  'en': {
    'appName': 'EG Masr',
    'personal': 'Personal Account',
    'company': 'Company Account',
    'name': 'Full Name',
    'contact': 'Phone Number or Email (Gmail)',
    'sendOtp': 'Send 4-Digit Code',
    'enterOtp': 'Enter 4-Digit Code',
    'verify': 'Verify & Login',
    'companyName': 'Company / Facility Name',
    'companyPhone': 'Facility Phone Number',
    'address': 'Address',
    'taxReg': 'Tax Registration Number',
    'managerName': 'Manager Name',
    'registerCompany': 'Register Company',
    'pendingApproval': 'Your company is pending admin approval',
    'chats': 'Chats & Groups',
    'contacts': 'Contacts',
    'myQr': 'My QR',
    'admin': 'Admin',
    'newGroup': 'Create New Group',
    'groupName': 'Group Name',
    'selectMembers': 'Select Members',
    'create': 'Create',
    'typeMsg': 'Type a message or link...',
    'logout': 'Logout',
  },
};

class EgMasrApp extends StatefulWidget {
  const EgMasrApp({super.key});
  @override
  State<EgMasrApp> createState() => _EgMasrAppState();
}

class _EgMasrAppState extends State<EgMasrApp> {
  String _lang = 'ar';
  Map<String, dynamic>? _currentUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('lang') ?? 'ar';
    final savedContact = prefs.getString('user_contact');
    setState(() => _lang = savedLang);

    if (savedContact != null) {
      final user = await supabase
          .from('users_profiles')
          .select()
          .eq('contact_info', savedContact)
          .maybeSingle();
      if (user != null) setState(() => _currentUser = user);
    }
    setState(() => _loading = false);
  }

  Future<void> _toggleLang() async {
    final next = _lang == 'ar' ? 'en' : 'ar';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', next);
    setState(() => _lang = next);
  }

  String tr(String key) => appTranslations[_lang]?[key] ?? key;

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
          : _currentUser == null
              ? AuthScreen(
                  lang: _lang,
                  onToggleLang: _toggleLang,
                  tr: tr,
                  onLoginSuccess: (user) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('user_contact', user['contact_info'].toString());
                    setState(() => _currentUser = user);
                  },
                )
              : HomeScreen(
                  user: _currentUser!,
                  lang: _lang,
                  onToggleLang: _toggleLang,
                  tr: tr,
                  onLogout: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_contact');
                    setState(() => _currentUser = null);
                  },
                ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final String lang;
  final VoidCallback onToggleLang;
  final String Function(String) tr;
  final Function(Map<String, dynamic>) onLoginSuccess;

  const AuthScreen({
    super.key,
    required this.lang,
    required this.onToggleLang,
    required this.tr,
    required this.onLoginSuccess,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  String _generatedOtp = '';

  final _compNameCtrl = TextEditingController();
  final _compPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _sendCode() {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) return;
    final code = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    setState(() {
      _generatedOtp = code;
      _otpSent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('كود التفعيل المكون من 4 أرقام: $code'),
        duration: const Duration(seconds: 15),
      ),
    );
  }

  Future<void> _verifyPersonal() async {
    if (_otpCtrl.text.trim() != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود التفعيل غير صحيح')),
      );
      return;
    }
    final contact = _contactCtrl.text.trim().toLowerCase();
    final isAdmin = contact == adminEmail.toLowerCase();
    final res = await supabase
        .from('users_profiles')
        .upsert({
          'full_name': _nameCtrl.text.trim(),
          'contact_info': contact,
          'account_type': 'personal',
          'is_admin': isAdmin,
        }, onConflict: 'contact_info')
        .select()
        .single();
    widget.onLoginSuccess(res);
  }

  Future<void> _registerCompany() async {
    if (_compNameCtrl.text.isEmpty ||
        _compPhoneCtrl.text.isEmpty ||
        _addressCtrl.text.isEmpty ||
        _taxCtrl.text.isEmpty ||
        _managerCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إدخال جميع بيانات المنشأة')),
      );
      return;
    }
    final contact = _compPhoneCtrl.text.trim().toLowerCase();
    final existing = await supabase
        .from('companies')
        .select()
        .eq('contact_info', contact)
        .maybeSingle();

    if (existing != null) {
      if (existing['status'] == 'approved') {
        final user = await supabase
            .from('users_profiles')
            .upsert({
              'full_name': existing['company_name'],
              'contact_info': contact,
              'account_type': 'company',
              'is_admin': false,
            }, onConflict: 'contact_info')
            .select()
            .single();
        widget.onLoginSuccess(user);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.tr('pendingApproval'))),
          );
        }
      }
      return;
    }

    await supabase.from('companies').insert({
      'company_name': _compNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'plot_number': _compPhoneCtrl.text.trim(),
      'tax_reg_number': _taxCtrl.text.trim(),
      'manager_name': _managerCtrl.text.trim(),
      'contact_info': contact,
      'status': 'pending',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.tr('pendingApproval'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tr('appName')),
        actions: [
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(
              widget.lang == 'ar' ? 'English' : 'عربي',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: widget.tr('personal')),
            Tab(text: widget.tr('company')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: widget.tr('name'))),
                const SizedBox(height: 12),
                TextField(controller: _contactCtrl, decoration: InputDecoration(labelText: widget.tr('contact'))),
                const SizedBox(height: 16),
                if (!_otpSent)
                  ElevatedButton(onPressed: _sendCode, child: Text(widget.tr('sendOtp')))
                else ...[
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(labelText: widget.tr('enterOtp')),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _verifyPersonal, child: Text(widget.tr('verify'))),
                ],
              ],
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _compNameCtrl, decoration: InputDecoration(labelText: widget.tr('companyName'))),
                TextField(controller: _compPhoneCtrl, decoration: InputDecoration(labelText: widget.tr('companyPhone'))),
                TextField(controller: _addressCtrl, decoration: InputDecoration(labelText: widget.tr('address'))),
                TextField(controller: _taxCtrl, decoration: InputDecoration(labelText: widget.tr('taxReg'))),
                TextField(controller: _managerCtrl, decoration: InputDecoration(labelText: widget.tr('managerName'))),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _registerCompany, child: Text(widget.tr('registerCompany'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String lang;
  final VoidCallback onToggleLang;
  final String Function(String) tr;
  final VoidCallback onLogout;

  const HomeScreen({
    super.key,
    required this.user,
    required this.lang,
    required this.onToggleLang,
    required this.tr,
    required this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user['is_admin'] == true ||
        widget.user['contact_info'].toString().toLowerCase() == adminEmail.toLowerCase();

    final pages = <Widget>[
      ChatsAndGroupsTab(user: widget.user, tr: widget.tr),
      ContactsScreen(user: widget.user, tr: widget.tr),
      QrScreen(user: widget.user, tr: widget.tr),
      if (isAdmin) AdminScreen(tr: widget.tr),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.tr('appName')} - ${widget.user['full_name']}'),
        actions: [
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(
              widget.lang == 'ar' ? 'EN' : 'عربي',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat), label: widget.tr('chats')),
          NavigationDestination(icon: const Icon(Icons.contacts), label: widget.tr('contacts')),
          NavigationDestination(icon: const Icon(Icons.qr_code), label: widget.tr('myQr')),
          if (isAdmin) NavigationDestination(icon: const Icon(Icons.admin_panel_settings), label: widget.tr('admin')),
        ],
      ),
    );
  }
}

class ChatsAndGroupsTab extends StatefulWidget {
  final Map<String, dynamic> user;
  final String Function(String) tr;

  const ChatsAndGroupsTab({super.key, required this.user, required this.tr});

  @override
  State<ChatsAndGroupsTab> createState() => _ChatsAndGroupsTabState();
}

class _ChatsAndGroupsTabState extends State<ChatsAndGroupsTab> {
  List<dynamic> _groups = [];
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myContact = widget.user['contact_info'];
    final gRes = await supabase.from('groups').select().order('created_at', ascending: false);
    final uRes = await supabase.from('users_profiles').select();
    final myGroups = List.from(gRes).where((g) {
      final members = List<String>.from(g['members'] ?? []);
      return members.contains(myContact) || g['created_by'] == myContact;
    }).toList();

    if (mounted) {
      setState(() {
        _groups = myGroups;
        _users = List.from(uRes).where((u) => u['contact_info'] != myContact).toList();
      });
    }
  }

  Future<void> _showCreateGroupDialog() async {
    final nameCtrl = TextEditingController();
    final selected = <String>{widget.user['contact_info'].toString()};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(widget.tr('newGroup')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: widget.tr('groupName'))),
                const SizedBox(height: 10),
                Text(widget.tr('selectMembers'), style: const TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 200,
                  child: ListView(
                    children: _users.map((u) {
                      final contact = u['contact_info'].toString();
                      return CheckboxListTile(
                        title: Text(u['full_name']?.toString() ?? ''),
                        subtitle: Text(contact),
                        value: selected.contains(contact),
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
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
                _load();
              },
              child: Text(widget.tr('create')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGroupDialog,
        icon: const Icon(Icons.group_add),
        label: Text(widget.tr('newGroup')),
      ),
      body: ListView(
        children: [
          if (_groups.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('الجروبات (Groups)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ..._groups.map((g) => ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.groups, color: Colors.white)),
                  title: Text(g['group_name']?.toString() ?? ''),
                  subtitle: Text('${(g['members'] as List).length} أعضاء'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        user: widget.user,
                        chatId: 'group_${g['id']}',
                        title: g['group_name'].toString(),
                        tr: widget.tr,
                      ),
                    ),
                  ),
                )),
            const Divider(),
          ],
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('المحادثات الفردية (1 to 1)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ..._users.map((u) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(u['full_name']?.toString() ?? ''),
                subtitle: Text(u['contact_info']?.toString() ?? ''),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      user: widget.user,
                      chatId: u['contact_info'].toString(),
                      title: u['full_name'].toString(),
                      tr: widget.tr,
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String chatId;
  final String title;
  final String Function(String) tr;

  const ChatScreen({
    super.key,
    required this.user,
    required this.chatId,
    required this.title,
    required this.tr,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _isRecording = false;
  List<dynamic> _messages = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    final res = await supabase.from('messages').select().order('created_at', ascending: true);
    final myContact = widget.user['contact_info'];
    final target = widget.chatId;

    final filtered = List.from(res).where((m) {
      if (target.startsWith('group_')) {
        return m['receiver_contact'] == target;
      } else {
        return (m['sender_contact'] == myContact && m['receiver_contact'] == target) ||
            (m['sender_contact'] == target && m['receiver_contact'] == myContact);
      }
    }).toList();

    if (mounted) setState(() => _messages = filtered);
  }

  Future<void> _sendMessage({String type = 'text', String? content, String? mediaUrl}) async {
    final text = content ?? _msgCtrl.text.trim();
    if (text.isEmpty && mediaUrl == null) return;
    _msgCtrl.clear();

    await supabase.from('messages').insert({
      'sender_name': widget.user['full_name'],
      'sender_contact': widget.user['contact_info'],
      'receiver_contact': widget.chatId,
      'content': text,
      'msg_type': type,
      'media_url': mediaUrl,
    });
    _fetchMessages();
  }

  Future<void> _pickAndUpload(bool isVideo) async {
    final file = isVideo
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last;
    final path = '${DateTime.now().millisecondsSinceEpoch}.$ext';

    await supabase.storage.from('chat_media').uploadBinary(path, bytes);
    final url = supabase.storage.from('chat_media').getPublicUrl(path);
    await _sendMessage(type: isVideo ? 'video' : 'image', content: isVideo ? 'فيديو' : 'صورة', mediaUrl: url);
  }

  Future<void> _toggleAudio() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
        await supabase.storage.from('chat_media').uploadBinary(fileName, bytes);
        final url = supabase.storage.from('chat_media').getPublicUrl(fileName);
        await _sendMessage(type: 'audio', content: 'رسالة صوتية', mediaUrl: url);
      }
    } else {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        await _recorder.start(const RecordConfig(), path: '${dir.path}/rec.m4a');
        setState(() => _isRecording = true);
      }
    }
  }

  Future<void> _sendLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition();
    final url = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    await _sendMessage(type: 'location', content: 'موقعي الجغرافي', mediaUrl: url);
  }

  Future<void> _startCall(bool isVideo) async {
    final room = 'EGMasr_${widget.chatId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
    final callUrl = isVideo
        ? 'https://meet.jit.si/$room'
        : 'https://meet.jit.si/$room#config.startWithVideoMuted=true';
    await _sendMessage(
      type: 'call',
      content: isVideo ? 'مكالمة فيديو مباشرة - اضغط للانضمام' : 'مكالمة صوتية مباشرة - اضغط للانضمام',
      mediaUrl: callUrl,
    );
    await launchUrl(Uri.parse(callUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () => _startCall(false)),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => _startCall(true)),
        ],
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
                            m['sender_name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                          ),
                          const SizedBox(height: 4),
                          if (type == 'image' && url != null)
                            Image.network(url, width: 200, height: 200, fit: BoxFit.cover)
                          else if (type == 'audio' && url != null)
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill, size: 32, color: Colors.teal),
                              onPressed: () => _player.play(UrlSource(url)),
                            )
                          else if ((type == 'video' || type == 'location' || type == 'call') && url != null)
                            InkWell(
                              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                              child: Text(
                                '${m['content']}',
                                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                              ),
                            )
                          else
                            InkWell(
                              onTap: () {
                                final txt = m['content'].toString();
                                if (txt.startsWith('http')) launchUrl(Uri.parse(txt), mode: LaunchMode.externalApplication);
                              },
                              child: Text(m['content']?.toString() ?? ''),
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
                IconButton(icon: const Icon(Icons.image), onPressed: () => _pickAndUpload(false)),
                IconButton(icon: const Icon(Icons.video_library), onPressed: () => _pickAndUpload(true)),
                IconButton(icon: const Icon(Icons.location_on), onPressed: _sendLocation),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : null),
                  onPressed: _toggleAudio,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(hintText: widget.tr('typeMsg')),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: () => _sendMessage()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String Function(String) tr;

  const ContactsScreen({super.key, required this.user, required this.tr});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<dynamic> _users = [];
  List<Contact> _phoneContacts = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final res = await supabase.from('users_profiles').select();
    if (mounted) setState(() => _users = List.from(res));

    if (await FlutterContacts.requestPermission()) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      if (mounted) setState(() => _phoneContacts = contacts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _users.where((u) {
      final q = _search.toLowerCase();
      return u['full_name'].toString().toLowerCase().contains(q) ||
          u['contact_info'].toString().toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الرقم...'),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              ...filteredUsers.map((u) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(u['full_name']?.toString() ?? ''),
                    subtitle: Text(u['contact_info']?.toString() ?? ''),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: widget.user,
                          chatId: u['contact_info'].toString(),
                          title: u['full_name'].toString(),
                          tr: widget.tr,
                        ),
                      ),
                    ),
                  )),
              const Divider(),
              ..._phoneContacts
                  .where((c) => c.displayName.toLowerCase().contains(_search.toLowerCase()))
                  .map((c) => ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.phone)),
                        title: Text(c.displayName),
                        subtitle: Text(c.phones.isNotEmpty ? c.phones.first.number : ''),
                      )),
            ],
          ),
        ),
      ],
    );
  }
}

class QrScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  final String Function(String) tr;

  const QrScreen({super.key, required this.user, required this.tr});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QrImageView(data: 'egmasr:${user['contact_info']}', size: 240),
          const SizedBox(height: 16),
          Text(user['full_name']?.toString() ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(user['contact_info']?.toString() ?? ''),
        ],
      ),
    );
  }
}

class AdminScreen extends StatefulWidget {
  final String Function(String) tr;
  const AdminScreen({super.key, required this.tr});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<dynamic> _companies = [];

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    final res = await supabase.from('companies').select().order('created_at', ascending: false);
    if (mounted) setState(() => _companies = List.from(res));
  }

  Future<void> _updateStatus(String id, String status) async {
    await supabase.from('companies').update({'status': status}).eq('id', id);
    _loadCompanies();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _companies.length,
      itemBuilder: (context, i) {
        final c = _companies[i];
        return Card(
          child: ListTile(
            title: Text(c['company_name']?.toString() ?? ''),
            subtitle: Text(
              'المسؤول: ${c['manager_name']}\nرقم المنشأة: ${c['plot_number']}\nالعنوان: ${c['address']}\nالضريبي: ${c['tax_reg_number']}\nالحالة: ${c['status']}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () => _updateStatus(c['id'].toString(), 'approved'),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () => _updateStatus(c['id'].toString(), 'rejected'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
