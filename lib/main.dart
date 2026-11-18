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
    'contact': 'البريد الإلكتروني (Gmail) أو رقم الهاتف',
    'sendOtp': 'إرسال كود التفعيل (6 أرقام)',
    'enterOtp': 'أدخل كود التفعيل (6 أرقام)',
    'verify': 'تأكيد الدخول',
    'companyName': 'اسم الشركة',
    'address': 'عنوان الشركة',
    'plotNumber': 'رقم القطعة',
    'taxReg': 'رقم التسجيل الضريبي',
    'managerName': 'اسم المسؤول',
    'registerCompany': 'تسجيل الشركة',
    'pendingApproval': 'طلبك قيد المراجعة من الإدارة',
    'chats': 'المحادثات',
    'contacts': 'جهات الاتصال',
    'myQr': 'الباركود الخاص بي',
    'admin': 'لوحة الأدمن',
    'publicChat': 'المحادثة العامة (EG Masr)',
    'typeMsg': 'اكتب رسالة أو رابط...',
    'approve': 'قبول',
    'reject': 'رفض',
    'logout': 'تسجيل خروج',
  },
  'en': {
    'appName': 'EG Masr',
    'personal': 'Personal Account',
    'company': 'Company Account',
    'name': 'Full Name',
    'contact': 'Email (Gmail) or Phone Number',
    'sendOtp': 'Send 6-Digit Code',
    'enterOtp': 'Enter 6-Digit Code',
    'verify': 'Verify & Login',
    'companyName': 'Company Name',
    'address': 'Company Address',
    'plotNumber': 'Plot Number',
    'taxReg': 'Tax Registration Number',
    'managerName': 'Manager Name',
    'registerCompany': 'Register Company',
    'pendingApproval': 'Your company is pending admin approval',
    'chats': 'Chats',
    'contacts': 'Contacts',
    'myQr': 'My QR Code',
    'admin': 'Admin Panel',
    'publicChat': 'Public Chat (EG Masr)',
    'typeMsg': 'Type a message or link...',
    'approve': 'Approve',
    'reject': 'Reject',
    'logout': 'Logout',
  },
};

const List> supportedLanguages = [
  {'code': 'ar', 'name': 'العربية'},
  {'code': 'en', 'name': 'English'},
  {'code': 'fr', 'name': 'Français'},
  {'code': 'de', 'name': 'Deutsch'},
  {'code': 'es', 'name': 'Español'},
  {'code': 'it', 'name': 'Italiano'},
  {'code': 'tr', 'name': 'Türkçe'},
  {'code': 'ru', 'name': 'Русский'},
  {'code': 'zh', 'name': '中文'},
  {'code': 'ja', 'name': '日本語'},
  {'code': 'ko', 'name': '한국어'},
  {'code': 'hi', 'name': 'हिन्दी'},
  {'code': 'ur', 'name': 'اردو'},
  {'code': 'pt', 'name': 'Português'},
  {'code': 'nl', 'name': 'Nederlands'},
  {'code': 'pl', 'name': 'Polski'},
  {'code': 'sv', 'name': 'Svenska'},
  {'code': 'el', 'name': 'Ελληνικά'},
  {'code': 'id', 'name': 'Bahasa Indonesia'},
  {'code': 'ms', 'name': 'Bahasa Melayu'},
];

class EgMasrApp extends StatefulWidget {
  const EgMasrApp({super.key});
  @override
  State<EgMasrApp> createState() => _EgMasrAppState();
}

class _EgMasrAppState extends State<EgMasrApp> {
  String _lang = 'ar';
  Map? _currentUser;
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
      if (user != null) {
        setState(() => _currentUser = user);
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _changeLang(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', code);
    setState(() => _lang = code);
  }

  String tr(String key) {
    return appTranslations[_lang]?[key] ??
        appTranslations['en']?[key] ??
        key;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EG Masr',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _currentUser == null
              ? AuthScreen(
                  lang: _lang,
                  onLangChanged: _changeLang,
                  tr: tr,
                  onLoginSuccess: (user) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('user_contact', user['contact_info']);
                    setState(() => _currentUser = user);
                  },
                )
              : HomeScreen(
                  user: _currentUser!,
                  lang: _lang,
                  onLangChanged: _changeLang,
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
  final Function(String) onLangChanged;
  final String Function(String) tr;
  final Function(Map) onLoginSuccess;

  const AuthScreen({
    super.key,
    required this.lang,
    required this.onLangChanged,
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
  final _addressCtrl = TextEditingController();
  final _plotCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();
  final _compContactCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _sendCode() {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) return;
    final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    setState(() {
      _generatedOtp = code;
      _otpSent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('كود التفعيل الخاص بك: $code'), duration: const Duration(seconds: 10)),
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
    final data = {
      'full_name': _nameCtrl.text.trim(),
      'contact_info': contact,
      'account_type': 'personal',
      'is_admin': isAdmin,
    };
    final res = await supabase
        .from('users_profiles')
        .upsert(data, onConflict: 'contact_info')
        .select()
        .single();
    widget.onLoginSuccess(res);
  }

  Future<void> _registerCompany() async {
    if (_compNameCtrl.text.isEmpty ||
        _addressCtrl.text.isEmpty ||
        _plotCtrl.text.isEmpty ||
        _taxCtrl.text.isEmpty ||
        _managerCtrl.text.isEmpty ||
        _compContactCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء ملء جميع بيانات الشركة')),
      );
      return;
    }
    final contact = _compContactCtrl.text.trim().toLowerCase();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.tr('pendingApproval'))),
        );
      }
      return;
    }

    await supabase.from('companies').insert({
      'company_name': _compNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'plot_number': _plotCtrl.text.trim(),
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
          DropdownButton<String>(
            value: widget.lang,
            underline: const SizedBox(),
            items: supportedLanguages
                .map((l) => DropdownMenuItem(value: l['code'], child: Text(l['name']!)))
                .toList(),
            onChanged: (v) {
              if (v != null) widget.onLangChanged(v);
            },
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
                    maxLength: 6,
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
                TextField(controller: _addressCtrl, decoration: InputDecoration(labelText: widget.tr('address'))),
                TextField(controller: _plotCtrl, decoration: InputDecoration(labelText: widget.tr('plotNumber'))),
                TextField(controller: _taxCtrl, decoration: InputDecoration(labelText: widget.tr('taxReg'))),
                TextField(controller: _managerCtrl, decoration: InputDecoration(labelText: widget.tr('managerName'))),
                TextField(controller: _compContactCtrl, decoration: InputDecoration(labelText: widget.tr('contact'))),
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
  final Map user;
  final String lang;
  final Function(String) onLangChanged;
  final String Function(String) tr;
  final VoidCallback onLogout;

  const HomeScreen({
    super.key,
    required this.user,
    required this.lang,
    required this.onLangChanged,
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

    final pages = [
      ChatScreen(user: widget.user, receiverContact: null, title: widget.tr('publicChat'), tr: widget.tr),
      ContactsScreen(user: widget.user, tr: widget.tr),
      QrScreen(user: widget.user, tr: widget.tr),
      if (isAdmin) AdminScreen(tr: widget.tr),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.tr('appName')} - ${widget.user['full_name']}'),
        actions: [
          DropdownButton<String>(
            value: widget.lang,
            underline: const SizedBox(),
            items: supportedLanguages
                .map((l) => DropdownMenuItem(value: l['code'], child: Text(l['name']!)))
                .toList(),
            onChanged: (v) {
              if (v != null) widget.onLangChanged(v);
            },
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

class ChatScreen extends StatefulWidget {
  final Map user;
  final String? receiverContact;
  final String title;
  final String Function(String) tr;

  const ChatScreen({
    super.key,
    required this.user,
    required this.receiverContact,
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
  List _messages = [];
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
    final target = widget.receiverContact;

    final filtered = List.from(res).where((m) {
      if (target == null) {
        return m['receiver_contact'] == null || m['receiver_contact'] == '';
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
      'receiver_contact': widget.receiverContact,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.receiverContact != null ? AppBar(title: Text(widget.title)) : null,
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
                final url = m['media_url'];

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Card(
                    color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['sender_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          if (type == 'image' && url != null)
                            Image.network(url, width: 200, height: 200, fit: BoxFit.cover)
                          else if (type == 'audio' && url != null)
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => _player.play(UrlSource(url)),
                            )
                          else if ((type == 'video' || type == 'location') && url != null)
                            InkWell(
                              onTap: () => launchUrl(Uri.parse(url)),
                              child: Text('${m['content']} (اضغط للفتح)', style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                            )
                          else
                            InkWell(
                              onTap: () {
                                final txt = m['content'].toString();
                                if (txt.startsWith('http')) launchUrl(Uri.parse(txt));
                              },
                              child: Text(m['content'] ?? ''),
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
                IconButton(icon: const Icon(Icons.videocam), onPressed: () => _pickAndUpload(true)),
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
  final Map user;
  final String Function(String) tr;

  const ContactsScreen({super.key, required this.user, required this.tr});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List _users = [];
  List<Contact> _phoneContacts = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final res = await supabase.from('users_profiles').select();
    setState(() => _users = List.from(res));

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
                    title: Text(u['full_name'] ?? ''),
                    subtitle: Text(u['contact_info'] ?? ''),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: widget.user,
                          receiverContact: u['contact_info'],
                          title: u['full_name'],
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
  final Map user;
  final String Function(String) tr;

  const QrScreen({super.key, required this.user, required this.tr});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QrImageView(
            data: 'egmasr:${user['contact_info']}',
            size: 240,
          ),
          const SizedBox(height: 16),
          Text(user['full_name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(user['contact_info'] ?? ''),
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
  List _companies = [];

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
            title: Text(c['company_name'] ?? ''),
            subtitle: Text(
              'المسؤول: ${c['manager_name']}\nالعنوان: ${c['address']} - قطعة: ${c['plot_number']}\nالضريبي: ${c['tax_reg_number']}\nالحالة: ${c['status']}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () => _updateStatus(c['id'], 'approved'),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () => _updateStatus(c['id'], 'rejected'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
