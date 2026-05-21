import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const DailyReportApp());
}

// ==========================================
// 1. Data Models (โมเดลเก็บข้อมูล)
// ==========================================
class WorkerRole {
  String position;
  int count;

  WorkerRole({required this.position, required this.count});

  Map<String, dynamic> toJson() => {'position': position, 'count': count};
  factory WorkerRole.fromJson(Map<String, dynamic> json) => 
      WorkerRole(position: json['position'], count: json['count']);
}

class WorkItem {
  String description;
  List<String> images;

  WorkItem({required this.description, required this.images});

  Map<String, dynamic> toJson() => {'description': description, 'images': images};
  factory WorkItem.fromJson(Map<String, dynamic> json) => 
      WorkItem(description: json['description'], images: List<String>.from(json['images']));
}

class DailyReport {
  final String id;
  final DateTime date;
  final String projectName;
  final List<WorkerRole> workers;
  final String weather;
  final List<WorkItem> items;
  final List<String> attendanceImages; // รูปตรวจชื่อคนงาน

  DailyReport({
    required this.id,
    required this.date,
    required this.projectName,
    required this.workers,
    required this.weather,
    required this.items,
    required this.attendanceImages,
  });

  int get totalWorkers => workers.fold(0, (sum, item) => sum + item.count);

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date.toIso8601String(), 'projectName': projectName,
    'workers': workers.map((e) => e.toJson()).toList(), 
    'weather': weather, 'items': items.map((e) => e.toJson()).toList(),
    'attendanceImages': attendanceImages,
  };

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
    id: json['id'], date: DateTime.parse(json['date']), projectName: json['projectName'],
    workers: (json['workers'] as List?)?.map((e) => WorkerRole.fromJson(e)).toList() ?? [], 
    weather: json['weather'],
    items: (json['items'] as List).map((e) => WorkItem.fromJson(e)).toList(),
    attendanceImages: List<String>.from(json['attendanceImages'] ?? []),
  );
}

class DailyReportApp extends StatelessWidget {
  const DailyReportApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Report',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey), useMaterial3: true),
      home: const HomePage(),
    );
  }
}

// ==========================================
// 2. หน้าแรก (แสดงประวัติ และสร้าง PDF)
// ==========================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<DailyReport> _reportList = [];
  bool _isLoading = true;

  @override
  void initState() { 
    super.initState(); 
    _loadData(); 
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('saved_reports_v4');
    if (data != null) {
      setState(() { _reportList = (jsonDecode(data) as List).map((e) => DailyReport.fromJson(e)).toList(); });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_reports_v4', jsonEncode(_reportList));
  }

  Future<pw.ImageProvider?> _resolvePdfImage(String path) async {
    try {
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        return pw.MemoryImage(response.bodyBytes);
      } else {
        return pw.MemoryImage(File(path).readAsBytesSync());
      }
    } catch (e) { return null; }
  }

  Future<void> _generatePdf(DailyReport report) async {
    final thaiFont = await PdfGoogleFonts.sarabunRegular();
    final thaiFontBold = await PdfGoogleFonts.sarabunBold();
    final pdf = pw.Document();

    // โหลดโลโก้กรมชลประทาน
    pw.ImageProvider? ridLogo;
    try {
      final logoResponse = await http.get(Uri.parse(
          'https://upload.wikimedia.org/wikipedia/th/thumb/b/b3/Royal_Irrigation_Department_Logo.svg/256px-Royal_Irrigation_Department_Logo.svg.png'));
      if (logoResponse.statusCode == 200) {
        ridLogo = pw.MemoryImage(logoResponse.bodyBytes);
      }
    } catch (e) {
      debugPrint('โหลดโลโก้ไม่สำเร็จ: $e');
    }

    // เตรียมรูปภาพกำลังคน
    List<pw.ImageProvider> resolvedAttendanceImages = [];
    for (var imgPath in report.attendanceImages) {
      final img = await _resolvePdfImage(imgPath);
      if (img != null) resolvedAttendanceImages.add(img);
    }

    // เตรียมรูปภาพประกอบความคืบหน้างาน
    List<List<pw.ImageProvider>> itemImages = [];
    for (var item in report.items) {
      List<pw.ImageProvider> resolved = [];
      for (var imgPath in item.images) {
        final img = await _resolvePdfImage(imgPath);
        if (img != null) resolved.add(img);
      }
      itemImages.add(resolved);
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (ridLogo != null) ...[
            pw.Center(child: pw.Image(ridLogo, width: 60, height: 60)),
            pw.SizedBox(height: 10),
          ],
          pw.Center(child: pw.Text('รายงานผลการปฏิบัติงานประจำวัน', style: pw.TextStyle(font: thaiFontBold, fontSize: 20))),
          pw.Center(child: pw.Text('กรมชลประทาน', style: pw.TextStyle(font: thaiFontBold, fontSize: 16))),
          pw.SizedBox(height: 15),
        ],
      ),
      build: (pw.Context context) => [
        // ข้อมูลทั่วไปโครงการ
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('โครงการ: ${report.projectName}', style: pw.TextStyle(font: thaiFontBold, fontSize: 14)),
                  pw.Text('วันที่: ${report.date.day}/${report.date.month}/${report.date.year + 543}', style: pw.TextStyle(font: thaiFont, fontSize: 14)),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Text('สภาพอากาศ: ${report.weather}', style: pw.TextStyle(font: thaiFont, fontSize: 14)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        // ข้อมูลกำลังคน
        pw.Text('กำลังคน (รวม ${report.totalWorkers} คน):', style: pw.TextStyle(font: thaiFontBold, fontSize: 14)),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, top: 5, bottom: 10),
          child: pw.Wrap(
            spacing: 20, runSpacing: 5,
            children: report.workers.map((w) => 
              pw.Text('\u2022 ${w.position}: ${w.count} คน', style: pw.TextStyle(font: thaiFont, fontSize: 13))
            ).toList(),
          ),
        ),
        
        // รูปถ่ายยืนยันปฏิบัติงานคนงาน
        if (resolvedAttendanceImages.isNotEmpty) ...[
          pw.Wrap(
            spacing: 10, runSpacing: 10,
            children: resolvedAttendanceImages.map((img) => pw.Container(
              width: 250, height: 180, 
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Image(img, fit: pw.BoxFit.contain),
            )).toList(),
          ),
          pw.SizedBox(height: 5),
          pw.Center(child: pw.Text('ภาพถ่ายหลักฐานการยืนยันปฏิบัติงานหน้างานจริง', style: pw.TextStyle(font: thaiFont, fontSize: 11, color: PdfColors.grey600))),
        ],
        pw.SizedBox(height: 24),

        // รายละเอียดงาน
        pw.Text('รายละเอียดความคืบหน้างาน:', style: pw.TextStyle(font: thaiFontBold, fontSize: 14)),
        pw.SizedBox(height: 10),
        
        ...List.generate(report.items.length, (index) {
          final item = report.items[index];
          final images = itemImages[index];
          
          // ใช้คุณสมบัติของ Table ในการล็อกให้หัวข้อและรูปภาพประกอบอยู่หน้าเดียวกันเสมอ (ห้ามหั่นแยกหน้า)
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Table(
              children: [
                pw.TableRow(
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('${index + 1}. ${item.description}', style: pw.TextStyle(font: thaiFontBold, fontSize: 13)),
                        pw.SizedBox(height: 10),
                        if (images.isNotEmpty)
                          pw.Wrap(
                            spacing: 10, runSpacing: 10,
                            children: images.map((img) => pw.Container(
                              width: 250, height: 180, // ขนาดใหญ่แถวละ 2 รูปภาพ
                              alignment: pw.Alignment.center,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: PdfColors.grey300),
                                color: PdfColors.grey50,
                              ),
                              child: pw.Image(img, fit: pw.BoxFit.contain),
                            )).toList(),
                          )
                        else
                          pw.Text('  - ไม่มีรูปภาพประกอบ -', style: pw.TextStyle(font: thaiFont, fontSize: 12, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        // ลายเซ็นต์ท้ายกระดาษ (ใช้ Table เพื่อไม่ให้แยกหน้าเหมือนกัน)
        pw.Table(
          children: [
            pw.TableRow(
              children: [
                pw.Column(
                  children: [
                    pw.SizedBox(height: 40),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text('...................................................', style: pw.TextStyle(font: thaiFont)),
                          pw.SizedBox(height: 5),
                          pw.Container(
                            width: 150,
                            alignment: pw.Alignment.center,
                            child: pw.Text('ผู้รายงาน / หัวหน้างาน', style: pw.TextStyle(font: thaiFont)),
                          )
                        ]
                      )
                    )
                  ]
                )
              ]
            )
          ]
        )
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Report_${report.projectName}.pdf');
  }

  Future<void> _navigateToEdit(DailyReport report, int index) async {
    final updatedReport = await Navigator.push<DailyReport>(
      context, 
      MaterialPageRoute(builder: (c) => ReportFormPage(existingReport: report))
    );
    
    if (updatedReport != null) {
      setState(() => _reportList[index] = updatedReport);
      _saveData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อัปเดตข้อมูลเรียบร้อยแล้ว'), backgroundColor: Colors.blue));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('รายงานประจำวัน (หน้างาน)'), backgroundColor: Theme.of(context).colorScheme.primaryContainer),
      body: Column(
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24), color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                const Icon(Icons.engineering, size: 70, color: Colors.orange),
                const SizedBox(height: 12),
                const Text('ประวัติการรายงานความคืบหน้า', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    final report = await Navigator.push<DailyReport>(context, MaterialPageRoute(builder: (c) => const ReportFormPage()));
                    if (report != null) { 
                      setState(() => _reportList.insert(0, report)); 
                      _saveData(); 
                    }
                  },
                  icon: const Icon(Icons.add_chart), label: const Text('สร้างรายงานใหม่', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
                ),
              ],
            ),
          ),
          Expanded(
            child: _reportList.isEmpty
                ? const Center(child: Text('ยังไม่มีข้อมูลรายงานในระบบ', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _reportList.length,
                    itemBuilder: (c, i) {
                      final r = _reportList[i];
                      return Dismissible(
                        key: Key(r.id), direction: DismissDirection.endToStart,
                        background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), color: Colors.redAccent, child: const Icon(Icons.delete, color: Colors.white)),
                        onDismissed: (direction) {
                          setState(() => _reportList.removeAt(i));
                          _saveData();
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.assignment, color: Colors.blueGrey)),
                            title: Text(r.projectName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('วันที่: ${r.date.day}/${r.date.month}/${r.date.year + 543}\nคนงาน: ${r.totalWorkers} คน | ${r.items.length} รายการ'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit, color: Colors.blueAccent), onPressed: () => _navigateToEdit(r, i), tooltip: 'แก้ไขรายงาน'),
                                IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent), onPressed: () => _generatePdf(r), tooltip: 'ออกรายงาน PDF'),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. หน้าฟอร์ม (กรอกข้อมูลและแนบรูป)
// ==========================================
class ReportFormPage extends StatefulWidget {
  final DailyReport? existingReport;
  const ReportFormPage({super.key, this.existingReport});
  
  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _projectController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _weather = 'แดดจัด / ปกติ';
  final List<String> _weatherOptions = ['แดดจัด / ปกติ', 'มีเมฆมาก', 'ฝนตกปรอยๆ', 'ฝนตกหนัก (หยุดงาน)', 'พายุเข้า'];
  
  List<WorkerRole> _workers = [WorkerRole(position: 'โฟร์แมน/หัวหน้างาน', count: 1), WorkerRole(position: 'กรรมกร', count: 0)];
  List<WorkItem> _items = [WorkItem(description: '', images: [])];
  List<String> _attendanceImages = []; 

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.existingReport != null) {
      final r = widget.existingReport!;
      _projectController.text = r.projectName;
      _selectedDate = r.date;
      _weather = r.weather;
      _workers = r.workers.map((w) => WorkerRole(position: w.position, count: w.count)).toList();
      _items = r.items.map((i) => WorkItem(description: i.description, images: List<String>.from(i.images))).toList();
      _attendanceImages = List<String>.from(r.attendanceImages); 
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingReport != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'แก้ไขรายงาน' : 'กรอกรายงานแบบละเอียด'), backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            InkWell(
              onTap: () => _selectDate(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('วันที่รายงาน: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year + 543}', style: const TextStyle(fontSize: 16)),
                    const Icon(Icons.calendar_month, color: Colors.blueGrey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _projectController,
              decoration: const InputDecoration(labelText: 'ชื่อโครงการ / พื้นที่ปฏิบัติงาน', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
              validator: (v) => v == null || v.isEmpty ? 'กรุณาระบุชื่อโครงการ' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _weather,
              decoration: const InputDecoration(labelText: 'สภาพอากาศหน้างาน', border: OutlineInputBorder(), prefixIcon: Icon(Icons.cloud)),
              items: _weatherOptions.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
              onChanged: (val) => setState(() => _weather = val!),
            ),
            const SizedBox(height: 30),
            
            const Text('กำลังคน / ตำแหน่ง:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            ...List.generate(_workers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: _workers[index].position,
                        decoration: const InputDecoration(labelText: 'ตำแหน่ง (เช่น ช่างปูน)', border: OutlineInputBorder()),
                        onChanged: (val) => _workers[index].position = val,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        initialValue: _workers[index].count.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'จำนวน', border: OutlineInputBorder()),
                        onChanged: (val) => _workers[index].count = int.tryParse(val) ?? 0,
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setState(() => _workers.removeAt(index)))
                  ],
                ),
              );
            }),
            TextButton.icon(onPressed: () => setState(() => _workers.add(WorkerRole(position: '', count: 0))), icon: const Icon(Icons.person_add), label: const Text('เพิ่มตำแหน่งใหม่')),
            
            const SizedBox(height: 10),
            const Text('ภาพถ่ายเช็คชื่อ / ตรวจสอบกำลังคนมาทำงานจริง:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                ..._attendanceImages.map((path) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5), 
                      child: kIsWeb ? Image.network(path, width: 90, height: 90, fit: BoxFit.cover) : Image.file(File(path), width: 90, height: 90, fit: BoxFit.cover)
                    ),
                    Positioned(right: -5, top: -5, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red, size: 20), onPressed: () => setState(() => _attendanceImages.remove(path)))),
                  ],
                )),
                InkWell(
                  onTap: () async {
                    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                    if (picked != null) setState(() => _attendanceImages.add(picked.path));
                  },
                  child: Container(width: 90, height: 90, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.grey.shade400)), child: const Icon(Icons.add_a_photo, color: Colors.blueGrey)),
                )
              ],
            ),
            const SizedBox(height: 30),

            const Text('รายการความคืบหน้างาน:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            ...List.generate(_items.length, (index) {
              return Card(
                color: Colors.blueGrey.shade50,
                margin: const EdgeInsets.symmetric(vertical: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('รายการที่ ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (_items.length > 1)
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => setState(() => _items.removeAt(index)))
                        ],
                      ),
                      TextFormField(
                        initialValue: _items[index].description,
                        decoration: const InputDecoration(hintText: 'รายละเอียดงาน เช่น เทปูนฐานราก', filled: true, fillColor: Colors.white),
                        onChanged: (val) => _items[index].description = val,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          ..._items[index].images.map((path) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5), 
                                child: kIsWeb ? Image.network(path, width: 100, height: 100, fit: BoxFit.cover) : Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover)
                              ),
                              Positioned(right: -5, top: -5, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setState(() => _items[index].images.remove(path)))),
                            ],
                          )),
                          InkWell(
                            onTap: () async {
                              final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                              if (picked != null) setState(() => _items[index].images.add(picked.path));
                            },
                            child: Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(5)), child: const Icon(Icons.add_a_photo)),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            }),
            
            TextButton.icon(onPressed: () => setState(() => _items.add(WorkItem(description: '', images: []))), icon: const Icon(Icons.add_circle), label: const Text('เพิ่มรายการงาน (ข้อถัดไป)')),
            const SizedBox(height: 30),
            
            SizedBox(
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isEditing ? Colors.blue.shade600 : Colors.green.shade600, foregroundColor: Colors.white),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final report = DailyReport(
                      id: widget.existingReport?.id ?? DateTime.now().millisecondsSinceEpoch.toString(), 
                      date: _selectedDate,
                      projectName: _projectController.text, workers: _workers,
                      weather: _weather, items: _items,
                      attendanceImages: _attendanceImages, 
                    );
                    Navigator.pop(context, report);
                  }
                },
                child: Text(isEditing ? 'อัปเดตรายงาน' : 'บันทึกรายงานทั้งหมด', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}