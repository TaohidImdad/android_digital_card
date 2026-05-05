import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _updateRetryCount = 0;
  String baseUrl = "http://libertycares.intelsofts.com";

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await _getDeviceId();
    String? savedUrl = await storage.read(key: 'base_url');
    if (savedUrl != null) baseUrl = savedUrl;
    await _loadSavedData();

    // ডাটা লোড হওয়ার পর এক্সপায়ারি চেক করা
    if (employeeData != null) {
      _checkDataExpiryAndRefresh();
    }
  }

  Future<void> _checkDataExpiryAndRefresh() async {
    String? lastFetchStr = await storage.read(key: 'last_fetch_time');
    if (lastFetchStr == null) return;

    DateTime lastFetchTime = DateTime.parse(lastFetchStr);
    DateTime currentTime = DateTime.now();

    // ১ সপ্তাহ (৭ দিন) চেক
    if (currentTime.difference(lastFetchTime).inDays >= 7) {

      // ইন্টারনেট চেক
      bool isOnline = await _hasInternet();

      if (isOnline) {
        // নেট থাকলে অটো রিফ্রেশ
        String? empId = employeeData?['front_side']['id'].toString();
        if (empId != null && empId != "N/A") {
          await _fetchData(empId);
        }
      } else {
        // ১ সপ্তাহ পার হয়েছে কিন্তু নেট নেই -> সাইন আউট
        _handleLogout();
        _showSnackBar("Session expired. Please login with internet.");
      }
    }
  }

// ইন্টারনেট চেকের সহজ ফাংশন
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }


  Future<void> _getDeviceId() async {
    var deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        var androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        var iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor;
      }
    } catch (e) {
      deviceId = "Unknown_ID";
    }
  }

  Future<void> _saveDeviceIdToServer(String personId) async {
    try {
      // আপনার দেওয়া URL ফরম্যাট অনুযায়ী POST রিকোয়েস্ট
      await http.put(Uri.parse('$baseUrl/api/HR/Person/SaveDeviceId?personId=$personId'));
    } catch (e) {
      debugPrint("Device ID saving failed: $e");
    }
  }

  Future<void> _loadSavedData() async {
    String? cachedData = await storage.read(key: 'saved_id_data');
    if (cachedData != null) {
      setState(() {
        employeeData = json.decode(cachedData);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  // ম্যাপিং ফাংশন যেখানে Null Safety হ্যান্ডেল করা হয়েছে
  Map<String, dynamic> mapToDigitalId(Map<String, dynamic> api) {
    return {
      "company_digital_id": {
        "is_verified": api["card"]?["isVerified"] ?? false,
        "design_system": {
          "colors": {"primary": api["card"]?["color"]?["primary"] ?? "#7077db"},
          "card_style": {"border_radius": api["card"]?["style"]?["borderRadius"] ?? "16px"}
        },
        "front_side": {
          "id": api["id"].toString() ?? "1",
          "company_name": api["company"]?["name"]?.toString() ?? "N/A",
          "abn": api["company"]?["brn"]?.toString() ?? "N/A",
          "logo_url": api["company"]?["logoUrl"] != null ? "$baseUrl/${api["company"]["logoUrl"]}" : "",
          "full_name": api["name"]?.toString() ?? "N/A",
          "designation": api["position"]?["name"]?.toString() ?? "N/A",
          "employee_id": api["code"]?.toString() ?? "N/A",
          "issue_date": api["card"]?["issueDate"]?.toString().split('T')[0] ?? "N/A",
          "expiry_date": api["card"]?["expiryDate"]?.toString().split('T')[0] ?? "N/A",
          "frontHeaderText": api["card"]?["frontHeaderText"]?.toString() ?? "",
          "frontFooterText": api["card"]?["frontFooterText"]?.toString() ?? "OFFICIAL DIGITAL IDENTITY",
          "blood_group": api["bloodGroup"]?.toString() ?? "N/A",
          "employment_type": api["period"]?.toString() ?? "N/A",
          "photo_url": api["photoUrl"] != null ? "$baseUrl/${api["photoUrl"]}" : "",
        },
        "back_side": {
          "backHeaderText": api["card"]?["backHeaderText"]?.toString() ?? "",
          "backFooterText": api["card"]?["backFooterText"]?.toString() ?? "Scan QR code to verify authenticity",
          "auth_sign_url": api["company"]?["authorizedSignUrl"] != null ? "$baseUrl/${api["company"]["authorizedSignUrl"]}" : "",
          "contact_info": {
            "email": api["email"]?.toString() ?? "N/A",
            "emergency_contact_phone": api["emergencyContact"]?.toString() ?? "N/A",
          },
          "location": {
            "building": api["company"]?["address"]?["building"]?.toString() ?? "",
            "street": api["company"]?["address"]?["street"]?.toString() ?? "N/A",
            "city": api["company"]?["address"]?["city"]?.toString() ?? "N/A",
            "area": api["company"]?["address"]?["area"]?.toString() ?? "N/A",
            "region": api["company"]?["address"]?["region"]?.toString() ?? "N/A",
          },
          "security": {"qr_code_data": api["card"]?["qrCodeData"]?.toString() ?? "No Data"},
          "compliance_text": api["company"]?["complianceText"]?.toString() ?? "",
        }
      }
    };
  }

  Future<void> _fetchData(String empId) async {
    if (empId.isEmpty) return;

    // ইন্টারনেট চেক
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        _showSnackBar("No Internet Connection!");
        return;
      }
    } catch (_) {
      _showSnackBar("No Internet Connection!");
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/HR/Person/IdentityCard?id=$empId'));
      if (response.statusCode == 200) {
        var rawData = jsonDecode(response.body);
        var mappedData = mapToDigitalId(rawData);


        // Mac ID Validation
        String remoteMac = rawData["card"]["macId"] ?? "";
        // debugPrint(remoteMac.toString(), wrapWidth: 1024);
        // যদি সার্ভারে আগে থেকে Mac ID না থাকে (অর্থাৎ প্রথমবার), তবে সেভ করুন
        if (remoteMac == "" || remoteMac == null) {
          await _saveDeviceIdToServer(rawData["id"].toString());
        } else if (remoteMac != deviceId) {
          _showSnackBar("Unauthorized Device!");
          setState(() => isLoading = false);
          return;
        }



        // ডাটা এবং বর্তমান সময় সেভ করা
        await storage.write(key: 'saved_id_data', value: jsonEncode(mappedData));
        await storage.write(key: 'last_fetch_time', value: DateTime.now().toIso8601String());

        setState(() {
          employeeData = mappedData;
          isLoading = false;
        });
      } else {
        _showSnackBar("ID not found!");
        setState(() => isLoading = false);
      }
    } catch (e) {
      _showSnackBar("Connection Error!");
      setState(() => isLoading = false);
    }
  }

  Future<void> _handleUpdateData() async {
    bool isOnline = await _hasInternet();
    bool isCheckOnline= false;
    if (!isOnline) {
      // যদি নেট না থাকে
      _updateRetryCount++; // কাউন্টার ১ বাড়লো

      if (_updateRetryCount == 1) {
        // প্রথমবার নেট নেই
        _showSnackBar("Please check your internet connection to update!");
      } else if (_updateRetryCount >= 2) {
        // দ্বিতীয়বার বা তার বেশিবার নেট নেই
        _updateRetryCount = 0; // কাউন্টার রিসেট করুন
        _handleLogout();
        _showSnackBar("Session expired due to no internet.");
      }
      return;
    }


    _updateRetryCount=0;
    String? empId = employeeData?['company_digital_id']?['front_side']?['id']?.toString();


    if (empId != null && empId != "N/A") {
      await _fetchData(empId);
      _showSnackBar("Data updated successfully!");
    }
  }

  void _handleLogout() async {
    await storage.delete(key: 'saved_id_data');
    setState(() => employeeData = null);
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
        title:  Text( employeeData?["card"]?["frontHeaderText"] ?? "Digital Identity Card", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'refresh') { _handleUpdateData();}
              if (val == 'logout') {
                _handleLogout();
              }
              if (val == 'exit') {SystemNavigator.pop();}
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text("Update"))),
              const PopupMenuItem(value: 'exit', child: ListTile(leading: Icon(Icons.exit_to_app, color: Colors.red), title: Text("Exit"))),
              // const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text("Logout"))),
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
    // অ্যাসেট পাথ (অবশ্যই pubspec.yaml এ থাকতে হবে)
    String companyLogoUrl = "assets/icon.png";

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // অ্যাসেট ইমেজ ব্যবহার
            Container(
              height: 100,
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Image.asset(
                companyLogoUrl,
                fit: BoxFit.contain,
                // যদি ইমেজ না পায় তবে এরর হ্যান্ডেল করবে
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                      Icons.badge_outlined,
                      size: 100,
                      color: Color(0xFF7077db)
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
                "Intellect Digital ID",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 10),
            Text(
                "Device ID: $deviceId",
                style: const TextStyle(color: Colors.grey, fontSize: 10)
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _idController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_pin),
                hintText: "Enter Employee ID",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7077db),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: () => _fetchData(_idController.text),
                child: const Text(
                    "Access Identity Card",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
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
    bool isVerified = employeeData!['company_digital_id']['is_verified'] ?? false;

    Color primaryColor = Color(int.parse(design['colors']['primary'].replaceAll('#', '0xff')));
    double radius = double.parse(design['card_style']['border_radius'].replaceAll('px', ''));

    return Stack(
      alignment: Alignment.center,
      children: [
        ColorFiltered(
          colorFilter: isVerified
              ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
              : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
          child: Opacity(
            opacity: isVerified ? 1.0 : 0.6,
            child: FlipCard(
              front: _CardSide(isFront: true, primary: primaryColor, radius: radius, data: front, backData: back),
              back: _CardSide(isFront: false, primary: primaryColor, radius: radius, data: front, backData: back),
            ),
          ),
        ),
        if (!isVerified)
          IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Text("NOT VERIFIED", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          ),
      ],
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
    String logoUrl = data['logo_url'] ?? "";
    String photoUrl = data['photo_url'] ?? "";

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(15, 20, 15, 50),
          width: double.infinity,
          color: primary,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              logoUrl.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: logoUrl,
                height: 45, width: 45,
                placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                errorWidget: (context, url, error) => const Icon(Icons.business, color: Colors.white, size: 40),
              )
                  : const Icon(Icons.business, color: Colors.white, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['company_name'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                    Text("ABN: ${data['abn']}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -45),
          child: Column(children: [
            CircleAvatar(
                radius: 65,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
                  child: photoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                )
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(data['full_name'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1D2939))),
            ),
            Text(data['designation'].toString().toUpperCase(), style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(children: [
            _infoRow("EMPLOYEE ID", data['employee_id'], "BLOOD GROUP", data['blood_group']),
            const Divider(height: 20),
            _infoRow("ISSUE DATE", data['issue_date'], "EXPIRY DATE", data['expiry_date']),
            const Divider(height: 20),
            _infoRow("EMPLOYMENT", data['employment_type'], "STATUS", "ACTIVE"),
          ]),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          width: double.infinity,
          color: const Color(0xFF1D2939),
          child:  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.verified, color: Colors.blueAccent, size: 16),
            SizedBox(width: 8),
            Text( data['frontFooterText'].toString().toUpperCase() , style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ]),
        )
      ],
    );
  }

  Widget _buildBackLayout(BuildContext context) {
    String authSignUrl = backData['auth_sign_url'] ?? "";
    String qrData = backData['security']?['qr_code_data'] ?? "No Data";

    return Column(
      children: [
        const SizedBox(height: 25),
        Text(backData['backHeaderText'].toString().toUpperCase() ?? "SECURITY & COMPLIANCE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
        const Spacer(),
        QrImageView(data: qrData, size: 140, eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: primary)),
        const Spacer(),
        Column(
          children: [
            authSignUrl.isNotEmpty
                ? CachedNetworkImage(
              imageUrl: authSignUrl,
              height: 50,
              placeholder: (context, url) => const SizedBox(height: 50),
              errorWidget: (context, url, error) => const Icon(Icons.gesture, color: Colors.grey),
            )
                : const SizedBox(height: 50, child: Icon(Icons.gesture, color: Colors.grey)),
            Container(width: 150, height: 1, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            const Text("AUTHORIZATION SIGNATURE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
        const Spacer(),
        _backInfoItem(Icons.email_outlined, "OFFICIAL EMAIL", backData['contact_info']['email']),
        _backInfoItem(Icons.streetview, "OFFICE ADDRESS 1", "${backData['location']['building']} ${backData['location']['street']}"),
        _backInfoItem(Icons.business_outlined, "OFFICE ADDRESS 2", "${backData['location']['area']} ${backData['location']['city']} ${backData['location']['region']}"),
        _backInfoItem(Icons.call_end_outlined, "EMERGENCY CONTACT", backData['contact_info']['emergency_contact_phone']),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(backData['backFooterText'].toString().toUpperCase() ?? "", textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
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
      Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF344054))),
    ]);
  }

  Widget _backInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      child: Row(children: [
        Icon(icon, size: 20, color: primary.withOpacity(0.7)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]))
      ]),
    );
  }
}