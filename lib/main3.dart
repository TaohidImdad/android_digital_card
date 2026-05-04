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

  Future<void> initApp() async {
    await getId();
    await loadData();
  }

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

  Future<void> loadData() async {
    String? cachedData = await storage.read(key: 'encrypted_employee_data');
    if (cachedData != null) {
      var decoded = json.decode(cachedData);
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

  Future<void> fetchData(String empId) async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://192.168.0.103:8000/api/employee/$empId'));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        var front = data['company_digital_id']['front_side'];

        if (front['active'] == 1) {
          if (front['mac_id'] == null || front['mac_id'] == deviceId) {
            await storage.write(key: 'encrypted_employee_data', value: response.body);
            setState(() {
              employeeData = data;
              isLoading = false;
            });
          } else {
            _msg("এই আইডিটি অন্য ডিভাইসে নিবন্ধিত!");
            setState(() => isLoading = false);
          }
        } else {
          _msg("আইডিটি ইন-অ্যাক্টিভ!");
          _logout();
        }
      } else {
        _msg("সঠিক আইডি দিন।");
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _msg("সার্ভারে কানেক্ট হতে পারছে না!");
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
    if (employeeData == null) return _buildLoginScreen();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text("Intellect Digital ID", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => fetchData(employeeData!['company_digital_id']['front_side']['employee_id'])
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: _buildFlipCard(),
        ),
      ),
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings, size: 80, color: Color(0xFF7077db)),
            const SizedBox(height: 20),
            const Text("Employee ID Verification", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Device ID: $deviceId", style: const TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 30),
            TextField(
              controller: _idController,
              decoration: InputDecoration(
                  hintText: "Enter Employee ID",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true, fillColor: Colors.grey[100]
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7077db), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => fetchData(_idController.text),
                child: const Text("Login", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipCard() {
    var design = employeeData!['company_digital_id']['design_system'];
    var front = employeeData!['company_digital_id']['front_side'];
    var back = employeeData!['company_digital_id']['back_side'];

    Color primaryColor = Color(int.parse(design['colors']['primary'].replaceAll('#', '0xff')));
    double radius = double.parse(design['card_style']['border_radius'].replaceAll('px', ''));

    return FlipCard(
      front: _CardLayout(isFront: true, primary: primaryColor, radius: radius, data: front, backData: back),
      back: _CardLayout(isFront: false, primary: primaryColor, radius: radius, data: front, backData: back),
    );
  }
}

class _CardLayout extends StatelessWidget {
  final bool isFront; final Color primary; final double radius; final dynamic data; final dynamic backData;
  const _CardLayout({required this.isFront, required this.primary, required this.radius, required this.data, required this.backData});

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width * 0.85;
    if (width > 350) width = 350;

    return Container(
      width: width, height: width * 1.58,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 2)]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Background Design
            Positioned(top: -50, right: -50, child: CircleAvatar(radius: 100, backgroundColor: primary.withOpacity(0.1))),
            isFront ? _buildFrontSide() : _buildBackSide(),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontSide() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          width: double.infinity, color: primary,
          child: Column(
            children: [
              Image.network(data['company_logo_url'], height: 40, color: Colors.white, errorBuilder: (c,e,s) => const Icon(Icons.business, color: Colors.white)),
              const SizedBox(height: 5),
              Text(data['company_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
        ),
        const SizedBox(height: 25),
        CircleAvatar(radius: 65, backgroundColor: primary, child: CircleAvatar(radius: 60, backgroundImage: NetworkImage(data['photo_url']))),
        const SizedBox(height: 15),
        Text(data['full_name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(data['designation'], style: TextStyle(fontSize: 16, color: Colors.grey[600], letterSpacing: 0.5)),
        const Spacer(),
        _infoRow("Employee ID", data['employee_id']),
        _infoRow("Blood Group", data['blood_group']),
        _infoRow("Issue Date", data['issue_date']),
        const SizedBox(height: 20),
        Container(height: 10, width: double.infinity, color: primary),
      ],
    );
  }

  Widget _buildBackSide() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          const Text("Contact Information", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          _backInfo(Icons.email, backData['contact_info']['email']),
          _backInfo(Icons.phone, backData['contact_info']['phone']),
          const Spacer(),
          QrImageView(data: backData['security']['qr_code_data'], size: 140, foregroundColor: primary),
          const SizedBox(height: 10),
          const Text("Scan to Verify Identity", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(backData['compliance_text'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _backInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [Icon(icon, size: 16, color: primary), const SizedBox(width: 10), Text(text, style: const TextStyle(fontSize: 13))]),
    );
  }
}