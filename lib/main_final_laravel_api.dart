import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flip_card/flip_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  final TextEditingController _urlController = TextEditingController();

  Map<String, dynamic>? employeeData;
  bool isLoading = true;
  String? deviceId;
  String baseUrl = "http://192.168.0.103:8000"; // ডিফল্ট ইউআরএল

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await _getDeviceId();
    // সেভ করা বেজ ইউআরএল চেক করা
    String? savedUrl = await storage.read(key: 'base_url');
    if (savedUrl != null) baseUrl = savedUrl;

    await _loadSavedData();
  }

  Future<void> _getDeviceId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      var iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor;
    }
  }

  Future<void> _loadSavedData() async {
    String? cachedData = await storage.read(key: 'saved_id_data');
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

  // সিক্রেট কোড চেক এবং ইউআরএল পরিবর্তন ডায়ালগ
  void _checkSecretCode(String val) {
    if (val == "426948") {
      _idController.clear();
      _showUrlConfigDialog();
    }
  }

  void _showUrlConfigDialog() {
    _urlController.text = baseUrl;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("API Configuration"),
        content: TextField(
          controller: _urlController,
          decoration: const InputDecoration(labelText: "Server Base URL"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await storage.write(key: 'base_url', value: _urlController.text);
              setState(() => baseUrl = _urlController.text);
              Navigator.pop(context);
              _showSnackBar("URL Updated Successfully");
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchData(String empId) async {
    if (empId.isEmpty) return;
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/employee/$empId'));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        var front = data['company_digital_id']['front_side'];

        if (front['active'] == 1) {
          if (front['mac_id'] == null || front['mac_id'] == deviceId) {
            await storage.write(key: 'saved_id_data', value: response.body);
            setState(() {
              employeeData = data;
              isLoading = false;
            });
          } else {
            _showSnackBar("Unauthorized Device! (Mac Mismatch)");
            setState(() => isLoading = false);
          }
        } else {
          _showSnackBar("Access Revoked: ID is Inactive");
          _handleLogout();
        }
      } else {
        _showSnackBar("Employee not found!");
        setState(() => isLoading = false);
      }
    } catch (e) {
      _showSnackBar("Connection Error! Check Server.");
      setState(() => isLoading = false);
    }
  }

  void _handleLogout() async {
    await storage.delete(key: 'saved_id_data');
    setState(() {
      employeeData = null;
      isLoading = false;
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (employeeData == null) return _buildLoginLayout();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text("Digital Identity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) => val == 'refresh' ? _fetchData(employeeData!['company_digital_id']['front_side']['employee_id']) : _handleLogout(),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text("Update Data"))),
              const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout, color: Colors.red), title: Text("Logout", style: TextStyle(color: Colors.red)))),
            ],
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildFlipCard(context),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginLayout() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.badge_outlined, size: 100, color: Color(0xFF7077db)),
            const SizedBox(height: 20),
            const Text("Intellect Digital ID", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            // const Text("Secure Corporate Verification System", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            Text("Device ID: $deviceId", style: const TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 40),
            TextField(
              controller: _idController,
              onChanged: _checkSecretCode,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_pin),
                hintText: "Enter Employee ID",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7077db), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => _fetchData(_idController.text),
                child: const Text("Access Identity Card", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipCard(BuildContext context) {
    var design = employeeData!['company_digital_id']['design_system'];
    var front = employeeData!['company_digital_id']['front_side'];
    var back = employeeData!['company_digital_id']['back_side'];
    Color primaryColor = Color(int.parse(design['colors']['primary'].replaceAll('#', '0xff')));
    double radius = double.parse(design['card_style']['border_radius'].replaceAll('px', ''));

    return FlipCard(
      front: _CardSide(isFront: true, primary: primaryColor, radius: radius, data: front, backData: back),
      back: _CardSide(isFront: false, primary: primaryColor, radius: radius, data: front, backData: back),
    );
  }
}

class _CardSide extends StatelessWidget {
  final bool isFront; final Color primary; final double radius; final dynamic data; final dynamic backData;
  const _CardSide({required this.isFront, required this.primary, required this.radius, required this.data, required this.backData});

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width * 0.88;
    if (width > 360) width = 360;

    return Container(
      width: width, height: width * 1.58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: isFront ? _buildFrontLayout(context) : _buildBackLayout(context),
      ),
    );
  }

  Widget _buildFrontLayout(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          width: double.infinity, height: 120,
          color: primary,
          child: Column(children: [
            FittedBox(child: Text(data['company_name'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5))),
            Text("ABN: ${data['abn']}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -50),
          child: Column(children: [
            CircleAvatar(radius: 65, backgroundColor: Colors.white, child: CircleAvatar(radius: 60, backgroundImage: CachedNetworkImageProvider(data['photo_url']))),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: FittedBox(child: Text(data['full_name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1D2939)))),
            ),
            Text(data['designation'].toString().toUpperCase(), style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _infoRow("EMPLOYEE ID", data['employee_id'], "BLOOD GROUP", data['blood_group']),
              const Divider(height: 1),
              _infoRow("ISSUE DATE", data['issue_date'], "EXPIRY DATE", data['expiry_date']),
              const Divider(height: 1),
              _infoRow("EMPLOYMENT", data['employment_type'], "STATUS", "ACTIVE"),
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          width: double.infinity,
          color: const Color(0xFF1D2939),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.verified_user, color: Colors.greenAccent, size: 14),
            SizedBox(width: 8),
            Text("OFFICIAL DIGITAL IDENTITY", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ]),
        )
      ],
    );
  }

  Widget _buildBackLayout(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 25),
        const Text("SECURITY & COMPLIANCE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey, letterSpacing: 1.2)),
        const Spacer(),
        QrImageView(data: backData['security']['qr_code_data'], size: 160, eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: primary)),
        const Spacer(),
        _backInfoItem(Icons.email_outlined, "OFFICIAL EMAIL", backData['contact_info']['email']),
        _backInfoItem(Icons.business_outlined, "OFFICE LOCATION", "${backData['location']['building']}, ${backData['location']['office_address']}"),
        _backInfoItem(Icons.emergency_share_outlined, "EMERGENCY CONTACT", backData['contact_info']['emergency_contact_phone']),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(backData['compliance_text'] + " If found, please return to the nearest branch.",
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic)),
        ),
      ],
    );
  }

  Widget _infoRow(String l1, String v1, String l2, String v2) {
    return Row(children: [
      Expanded(child: _labelVal(l1, v1)),
      Expanded(child: _labelVal(l2, v2)),
    ]);
  }

  Widget _labelVal(String l, String v) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF344054))),
    ]);
  }

  Widget _backInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: primary.withOpacity(0.6)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]))
      ]),
    );
  }
}