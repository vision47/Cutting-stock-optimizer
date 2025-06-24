import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() => runApp(CuttingStockApp());

class CuttingStockApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cutting Stock Optimizer',
      home: CuttingHomePage(),
    );
  }
}

class CuttingHomePage extends StatefulWidget {
  @override
  _CuttingHomePageState createState() => _CuttingHomePageState();
}

class _CuttingHomePageState extends State<CuttingHomePage> {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _demand = [];

  String id = '';
  int length = 0;
  int qty = 1;
  int multiplier = 1;
  int stockLength = 6000;
  String resultText = '';
  List<dynamic> patterns = [];
  int stockUsed = 0;

  void _addEntry() {
    if (id.isEmpty || length <= 0 || qty <= 0) return;
    setState(() {
      _demand.add({'id': id, 'length': length, 'quantity': qty});
      id = '';
      length = 0;
      qty = 1;
    });
  }

  Future<void> _importExcelFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
    if (result == null) return;

    Uint8List fileBytes = result.files.first.bytes!;
    Excel excel = Excel.decodeBytes(fileBytes);

    final sheet = excel.tables[excel.tables.keys.first]!;
    setState(() {
      _demand.clear();
      for (var row in sheet.rows.skip(1)) {
        final idVal = row[0]?.value.toString();
        final len = int.tryParse(row[1]?.value.toString() ?? '');
        final q = int.tryParse(row[2]?.value.toString() ?? '');
        if (idVal != null && len != null && q != null) {
          _demand.add({"id": idVal, "length": len, "quantity": q});
        }
      }
    });
  }

  Future<void> _optimize() async {
    final apiUrl = 'https://your-backend-url.onrender.com/optimize'; // Change to your FastAPI deployment
    final requestBody = {
      'multiplier': multiplier,
      'stock_length': stockLength,
      'items': _demand,
    };

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final res = jsonDecode(response.body);
      setState(() {
        patterns = res['patterns'];
        stockUsed = res['stock_used'];
        resultText = "Optimized using $stockUsed stock pipes.";
      });
    } else {
      setState(() {
        resultText = "Error: ${response.statusCode}";
      });
    }
  }

  void _generateAndSharePdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(children: [
            pw.Text('Cutting Optimization Result', style: pw.TextStyle(fontSize: 22)),
            pw.SizedBox(height: 10),
            pw.Text('Stock Pipes Used: $stockUsed'),
            pw.SizedBox(height: 20),
            ...patterns.map((p) => pw.Text(
              "Pattern: ${p['pattern'].join(', ')} | Used: ${p['usage_count']}x | Scrap: ${p['scrap']}mm",
            )),
          ]);
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'cutting_plan.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cutting Stock Optimizer')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Text('🔧 Add Pipe Manually', style: TextStyle(fontWeight: FontWeight.bold)),
            Form(
              key: _formKey,
              child: Column(children: [
                TextFormField(
                  decoration: InputDecoration(labelText: 'ID'),
                  onChanged: (val) => id = val,
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Length (mm)'),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => length = int.tryParse(val) ?? 0,
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => qty = int.tryParse(val) ?? 1,
                ),
                ElevatedButton(onPressed: _addEntry, child: Text('➕ Add Entry')),
              ]),
            ),
            Divider(),
            ElevatedButton.icon(
              icon: Icon(Icons.upload_file),
              label: Text('📤 Import Excel File'),
              onPressed: _importExcelFile,
            ),
            Divider(),
            Text('📋 Demand List', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._demand.map((e) => Text('${e['id']}: ${e['length']}mm ×${e['quantity']}')),
            Divider(),
            TextFormField(
              decoration: InputDecoration(labelText: 'Multiplier'),
              keyboardType: TextInputType.number,
              onChanged: (val) => multiplier = int.tryParse(val) ?? 1,
            ),
            TextFormField(
              decoration: InputDecoration(labelText: 'Stock Pipe Length (mm)'),
              keyboardType: TextInputType.number,
              onChanged: (val) => stockLength = int.tryParse(val) ?? 6000,
            ),
            SizedBox(height: 10),
            ElevatedButton(onPressed: _optimize, child: Text('🚀 Run Optimization')),
            SizedBox(height: 10),
            if (resultText.isNotEmpty) Text(resultText, style: TextStyle(fontWeight: FontWeight.bold)),
            if (patterns.isNotEmpty)
              ElevatedButton.icon(
                icon: Icon(Icons.picture_as_pdf),
                label: Text('📄 Share as PDF'),
                onPressed: _generateAndSharePdf,
              ),
          ],
        ),
      ),
    );
  }
}
