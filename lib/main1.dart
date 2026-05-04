import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flip_card/flip_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:developer' as dev;

void main() {
  runApp(const MaterialApp(
    home: IDCardScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class IDCardScreen extends StatefulWidget {
  const IDCardScreen({super.key});

  @override
  State<IDCardScreen> createState() => _IDCardScreenState();
}

class _IDCardScreenState extends State<IDCardScreen> {
  final storage = const FlutterSecureStorage();
  final TextEditingController _idController = TextEditingController();

  Map<String, dynamic>? employeeData;
  bool isLoading = true;
  String? deviceId;

  @override
  void initState() {
    super.initState();
    initApp();
  }

  // অ্যাপ শুরুর লজিক
  Future<void> initApp() async {
    await getId();     // ডিভাইস আইডি নেওয়া
    await loadData();   // লোকাল স্টোরেজ চেক করা
  }

  // ডিভাইস আইডি সংগ্রহ
  Future<void> getId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      var iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor;
    }
  }

  // লোকাল ডাটা লোড করা
  Future<void> loadData() async {
    String? cachedData = await storage.read(key: 'encrypted_employee_data');
    if (cachedData != null) {
      var decoded = json.decode(cachedData);
      // এখানে চেক করা হচ্ছে ডাটাটি অ্যাক্টিভ কি না
      if (decoded['company_digital_id']['front_side']['active'] == 1) {
        setState(() {
          employeeData = decoded;
          isLoading = false;
        });
        return;
      }
    }
    setState(() => isLoading = false);
  }

  // এপিআই থেকে ডাটা আনা (লগইন এবং রিফ্রেশ দুটোর জন্যই)
  Future<void> fetchData(String empId) async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://192.168.0.103:8000/api/employee/$empId'));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        var front = data['company_digital_id']['front_side'];

        // শর্ত ১: আইডি অ্যাক্টিভ হতে হবে
        if (front['active'] == 1) {
          // শর্ত ২: মেক আইডি সেট করা থাকলে তা ডিভাইসের সাথে মিলতে হবে
          // যদি এপিআই থেকে mac_id নাল আসে, তবে বর্তমান ডিভাইস আইডি সেভ হবে (আপনার লজিক অনুযায়ী)
          if (front['mac_id'] == null || front['mac_id'] == deviceId) {

            await storage.write(key: 'encrypted_employee_data', value: response.body);

            dev.log(JsonEncoder.withIndent('  ').convert(data), name: 'API_RESPONSE');

            setState(() {
              employeeData = data;
              isLoading = false;
            });
            _msg("সফলভাবে ডাটা লোড হয়েছে");
          } else {
            _msg("এই আইডিটি অন্য ডিভাইসে নিবন্ধিত!");
            setState(() => isLoading = false);
          }
        } else {
          _msg("আইডিটি বর্তমানে অ্যাক্টিভ নয়!");
          _logout();
        }
      } else {
        _msg("Employee ID সঠিক নয় অথবা সার্ভার ডাউন।");
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _msg("Connection Failed!");
    }
  }

  void _logout() async {
    await storage.delete(key: 'encrypted_employee_data');
    setState(() {
      employeeData = null;
      isLoading = false;
    });
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // যদি ডাটা না থাকে তবে লগইন স্ক্রিন দেখাবে
    if (employeeData == null) {
      return _buildLoginScreen();
    }

    // ডাটা থাকলে আগের সেই Flip Card ডিজাইন দেখাবে
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text("Digital ID", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'refresh') fetchData(employeeData!['company_digital_id']['front_side']['employee_id']);
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text("Refresh Data")),
              const PopupMenuItem(value: 'logout', child: Text("Logout")),
            ],
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: buildAustralianIDCard(context),
        ),
      ),
    );
  }

  // --- নতুন ইনপুট স্ক্রিন ডিজাইন ---
  Widget _buildLoginScreen() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.badge, size: 80, color: Color(0xFF7077db)),
            const SizedBox(height: 20),
            const Text("Employee Verification", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Device ID: $deviceId", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 30),
            TextField(
              controller: _idController,
              decoration: InputDecoration(
                hintText: "Employee ID লিখুন (উদা: ISL-2026-101)",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7077db)),
                onPressed: () => fetchData(_idController.text),
                child: const Text("Get My ID Card", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- আপনার আগের ফ্লিপ কার্ড ডিজাইন সেকশন ---
  Widget buildAustralianIDCard(BuildContext context) {
    var design = employeeData!['company_digital_id']['design_system'];
    var front = employeeData!['company_digital_id']['front_side'];
    var back = employeeData!['company_digital_id']['back_side'];

    Color primaryColor = Color(int.parse(design['colors']['primary'].replaceAll('#', '0xff')));
    double borderRadius = double.parse(design['card_style']['border_radius'].replaceAll('px', ''));

    return FlipCard(
      front: _CardSide(isFront: true, primary: primaryColor, radius: borderRadius, data: front, backData: back),
      back: _CardSide(isFront: false, primary: primaryColor, radius: borderRadius, data: front, backData: back),
    );
  }
}

class _CardSide extends StatelessWidget {
  final bool isFront; final Color primary; final double radius; final dynamic data; final dynamic backData;
  const _CardSide({required this.isFront, required this.primary, required this.radius, required this.data, required this.backData});

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double cardWidth = screenWidth * 0.85; if (cardWidth > 350) cardWidth = 350;

    return Container(
      width: cardWidth, height: cardWidth * 1.6,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15)]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: isFront ? _buildFront(context) : _buildBack(context),
      ),
    );
  }

  // এখানে আপনার আগের সেই সুন্দর ফ্রন্ট সাইড ডিজাইনটি বসবে
  Widget _buildFront(BuildContext context) {
    return Column(
      children: [
        Container(height: 100, color: primary, child: Center(child: Text(data['company_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 20),
        CircleAvatar(radius: 60, backgroundImage: NetworkImage(data['photo_url'])),
        const SizedBox(height: 20),
        Text(data['full_name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(data['designation'], style: const TextStyle(color: Colors.grey)),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text("ID: ${data['employee_id']}", style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  // এখানে আপনার আগের সেই সুন্দর ব্যাক সাইড ডিজাইনটি বসবে
  Widget _buildBack(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        QrImageView(data: backData['security']['qr_code_data'], size: 150),
        const SizedBox(height: 20),
        const Text("Scan to Verify", style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}