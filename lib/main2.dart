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
  Map<String, dynamic>? employeeData;
  bool isLoading = true;
  String? deviceId;

  @override
  void initState() {
    super.initState();
    initApp();
    debugPrint('Hello');
  }



  // অ্যাপ শুরু হওয়ার লজিক
  Future<void> initApp() async {
    await getId(); // প্রথমে ডিভাইস আইডি নেওয়া

    await loadData(); // তারপর ডাটা লোড করা


  }

  // ডিভাইস আইডি (Mac/Android ID) সংগ্রহ করা
  Future<void> getId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id; // ইউনিক অ্যান্ড্রয়েড আইডি
    } else if (Platform.isIOS) {
      var iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor;
    }
  }

  Future<void> loadData() async {
    String? cachedData = await storage.read(key: 'encrypted_employee_data');
    if (cachedData != null) {
      setState(() {
        employeeData = json.decode(cachedData);
        isLoading = false;
      });
    } else {
      await refreshDataFromServer();
    }
  }

  // রিফ্রেশ ফাংশন - যা এপিআই থেকে ফ্রেশ ডাটা নিবে
  Future<void> refreshDataFromServer() async {
    setState(() => isLoading = true);
    try {
      // আপনার এপিআই এন্ডপয়েন্ট
      final response = await http.get(Uri.parse('http://192.168.0.103:8000/api/employee/ISL-2026-101'));

      if (response.statusCode == 200) {
        await storage.write(key: 'encrypted_employee_data', value: response.body);

        var decodedData = jsonDecode(response.body);
        String formattedJson = JsonEncoder.withIndent('  ').convert(decodedData);

        // এটি সরাসরি Android Studio-র Logcat এ দেখাবে
        dev.log(formattedJson, name: 'API_RESPONSE');


        setState(() {
          employeeData = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection Failed!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // ১. Active Status চেক করা
    bool isActive = employeeData?['active'] == true || employeeData?['active'] == "true";

    // ২. Mac/Device ID ম্যাচিং (আপনার এপিআই-তে 'mac_id' ফিল্ড থাকতে হবে)
    bool isAuthorizedDevice = employeeData?['mac_id'] == deviceId;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text("Digital ID", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        actions: [
          // থ্রি ডট মেনু (Popup Menu)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'refresh') refreshDataFromServer();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.black),
                    SizedBox(width: 10),
                    Text("Refresh Data"),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(isActive, isAuthorizedDevice),
    );
  }

  Widget _buildBody(bool isActive, bool isAuthorizedDevice) {


    if (!isActive) {
      return _buildErrorState(Icons.lock_person, "ID Card Inactive", "Please contact HR to activate your ID.");
    }

    // মনে রাখবেন: প্রথমবার টেস্ট করার সময় এটি false হতে পারে যদি ডাটাবেসে আপনার ফোনের আইডি না থাকে
    if (!isAuthorizedDevice) {
      return _buildErrorState(Icons.phonelink_lock, "Unauthorized Device", "This ID can only be used on the registered device.\nYour ID: $deviceId");
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: buildAustralianIDCard(context),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(IconData icon, String title, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.redAccent),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: refreshDataFromServer, child: const Text("Try Sync Again"))
          ],
        ),
      ),
    );
  }

  // --- কার্ড ডিজাইন সেকশন (আগের রেসপন্সিভ ডিজাইন) ---
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

// _CardSide ক্লাসটি আগের কোড থেকেই ব্যবহার করবেন (কোনো পরিবর্তন লাগবে না)
class _CardSide extends StatelessWidget {
  final bool isFront; final Color primary; final double radius; final dynamic data; final dynamic backData;
  const _CardSide({required this.isFront, required this.primary, required this.radius, required this.data, required this.backData});

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double cardWidth = screenWidth * 0.85; if (cardWidth > 350) cardWidth = 350;
    return Container(
      width: cardWidth, height: cardWidth * 1.6,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: isFront ? _buildFrontLayout(context) : _buildBackLayout(context),
      ),
    );
  }

  // ... (বাকি ডিজাইন কোড আগের মতোই থাকবে)
  Widget _buildFrontLayout(BuildContext context) => Center(child: Text(data['full_name'])); // Placeholder
  Widget _buildBackLayout(BuildContext context) => Center(child: Text("Back Side")); // Placeholder
}