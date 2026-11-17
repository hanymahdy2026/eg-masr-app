import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String supabaseUrl = 'https://bdbdimphbrsezftindck.supabase.co';
const String supabaseKey = 'sb_publishable_Zik6vfMWUdxgdws1wrshjg_GeiJiqcq';

Map<String, String> get _headers => {
      'apikey': supabaseKey,
      'Authorization': 'Bearer $supabaseKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

void main() {
  runApp(const EgMasrApp());
}

class EgMasrApp extends StatelessWidget {
  const EgMasrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EG مصر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0D47A1),
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LoginScreen(),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _selectedRole = 'employee';
  bool _isLoading = false;

  Future<void> _loginAndSync() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final checkRes = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/users?phone=eq.${_phoneCtrl.text.trim()}'),
        headers: _headers,
      );

      Map<String, dynamic> userData;
      final list = jsonDecode(checkRes.body) as List;

      if (list.isNotEmpty) {
        userData = list.first;
      } else {
        final createRes = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/users'),
          headers: _headers,
          body: jsonEncode({
            'full_name': _nameCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'role': _selectedRole,
            'wallet_balance': 500,
          }),
        );
        userData = (jsonDecode(createRes.body) as List).first;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: MainDashboard(user: userData),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تأكد من الإنترنت: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_bus_filled, size: 56, color: Color(0xFF0D47A1)),
                  const SizedBox(height: 12),
                  const Text('EG مصر', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                  const Text('منصة النقل الذكي والتواصل المباشر', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'اكتب اسمك', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'رقم الموبايل', prefixIcon: Icon(Icons.phone_android), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(labelText: 'الصفة', prefixIcon: Icon(Icons.badge), border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'employee', child: Text('موظف / راكب')),
                      DropdownMenuItem(value: 'driver', child: Text('كابتن / سائق باص')),
                      DropdownMenuItem(value: 'admin', child: Text('إدارة التشغيل')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val!),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _loginAndSync,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('دخول للتطبيق', style: TextStyle(fontSize: 16)),
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
}

class MainDashboard extends StatefulWidget {
  final Map<String, dynamic> user;
  const MainDashboard({super.key, required this.user});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _tabIndex = 0;
  List<dynamic> _buses = [];
  List<dynamic> _subscriptions = [];
  List<dynamic> _messages = [];
  final _msgCtrl = TextEditingController();
  Timer? _chatTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _chatTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _chatTimer?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final busRes = await http.get(Uri.parse('$supabaseUrl/rest/v1/live_buses?select=*'), headers: _headers);
      final subRes = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/subscriptions?user_id=eq.${widget.user['id']}&order=created_at.desc'),
        headers: _headers,
      );
      await _fetchMessages();
      if (mounted) {
        setState(() {
          _buses = jsonDecode(busRes.body);
          _subscriptions = jsonDecode(subRes.body);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchMessages() async {
    try {
      final res = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/messages?select=*&order=created_at.asc&limit=50'),
        headers: _headers,
      );
      if (mounted && res.statusCode == 200) {
        setState(() => _messages = jsonDecode(res.body));
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    await http.post(
      Uri.parse('$supabaseUrl/rest/v1/messages'),
      headers: _headers,
      body: jsonEncode({
        'sender_name': widget.user['full_name'],
        'sender_phone': widget.user['phone'],
        'text': text,
      }),
    );
    await _fetchMessages();
  }

  Future<void> _bookPackage(String planName, String routeName, int trips) async {
    await http.post(
      Uri.parse('$supabaseUrl/rest/v1/subscriptions'),
      headers: _headers,
      body: jsonEncode({
        'user_id': widget.user['id'],
        'plan_name': planName,
        'route_name': routeName,
        'trips_remaining': trips,
        'status': 'active',
      }),
    );
    await _fetchAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الاشتراك بنجاح!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _simulateBusMove(Map<String, dynamic> bus) async {
    final newLat = (bus['lat'] as num) + 0.0045;
    final newLng = (bus['lng'] as num) + 0.0038;
    await http.patch(
      Uri.parse('$supabaseUrl/rest/v1/live_buses?id=eq.${bus['id']}'),
      headers: _headers,
      body: jsonEncode({'lat': newLat, 'lng': newLng, 'speed': 62}),
    );
    await _fetchAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: Text('EG مصر • ${widget.user['full_name']}', style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(onPressed: _fetchAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _tabIndex,
              children: [
                _buildLiveBusesTab(),
                _buildPackagesTab(),
                _buildMySubscriptionsTab(),
                _buildChatTab(),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.gps_fixed), label: 'الباصات'),
          NavigationDestination(icon: Icon(Icons.card_membership), label: 'الباقات'),
          NavigationDestination(icon: Icon(Icons.qr_code_2), label: 'تذاكري'),
          NavigationDestination(icon: Icon(Icons.chat), label: 'الشات'),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('ابدأ المحادثة الآن... أي رسالة بتظهر للطرف التاني فوراً!'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    final isMe = m['sender_phone'] == widget.user['phone'];
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF0D47A1) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m['sender_name'] ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isMe ? Colors.amberAccent : const Color(0xFF0D47A1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m['text'] ?? '',
                              style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالتك هنا...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF0D47A1),
                radius: 24,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveBusesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _buses.length,
      itemBuilder: (context, index) {
        final bus = _buses[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('باص رقم: ${bus['bus_number']} (${bus['driver_name']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text('الخط: ${bus['route_name']}'),
                Text('السرعة: ${bus['speed']} كم/س • GPS: ${bus['lat']}, ${bus['lng']}'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _simulateBusMove(bus),
                  icon: const Icon(Icons.navigation),
                  label: const Text('تحديث موقع الباص الآن'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPackagesTab() {
    final plans = [
      {'title': 'باقة العاشر - التجمع (شهرية)', 'route': 'العاشر من رمضان - التجمع الخامس', 'trips': 44, 'price': '1,200 ج.م'},
      {'title': 'باقة العاشر - مدينة نصر (شهرية)', 'route': 'العاشر من رمضان - مكرم عبيد', 'trips': 44, 'price': '1,100 ج.م'},
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plans.length,
      itemBuilder: (context, i) {
        final p = plans[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(p['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${p['route']} • ${p['price']}'),
            trailing: FilledButton(
              onPressed: () => _bookPackage(p['title'] as String, p['route'] as String, p['trips'] as int),
              child: const Text('اشتراك'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMySubscriptionsTab() {
    if (_subscriptions.isEmpty) return const Center(child: Text('لا توجد باقات مفعلة بعد.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _subscriptions.length,
      itemBuilder: (context, i) {
        final s = _subscriptions[i];
        return Card(
          color: const Color(0xFF0D47A1),
          child: ListTile(
            title: Text(s['plan_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('${s['route_name']} • متبقي ${s['trips_remaining']} رحلة', style: const TextStyle(color: Colors.white70)),
            trailing: const Icon(Icons.qr_code_2, color: Colors.white, size: 40),
          ),
        );
      },
    );
  }
}
