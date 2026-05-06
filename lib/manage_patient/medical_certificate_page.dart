import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../main.dart';

class MedicalCertificatePage extends StatefulWidget {
  final Patient patient;
  const MedicalCertificatePage({super.key, required this.patient});

  @override
  State<MedicalCertificatePage> createState() => _MedicalCertificatePageState();
}

class _MedicalCertificatePageState extends State<MedicalCertificatePage> {
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _templateNameController = TextEditingController();
  String _selectedTemplateName = "";
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = false;

  final List<Map<String, String>> _defaultTemplates = [
    {
      'name': 'General Medical Certificate',
      'content': 'To whom it may concern,\n\nThis is to certify that [PATIENT_NAME], aged [AGE], was examined by me today. \n\n[WRITE_SPECIFIC_DETAILS_HERE]\n\nHe/She is advised [ADVICE].'
    },
    {
      'name': 'Sick Leave Certificate',
      'content': 'To whom it may concern,\n\nThis is to certify that [PATIENT_NAME], aged [AGE], was under my clinical care from [START_DATE] to [END_DATE]. \n\nHe/She is suffering from acute illness and is advised rest for [DAYS] days. He/She is fit to resume his/her duties on [FITNESS_DATE].'
    },
    {
      'name': 'Fitness Certificate',
      'content': 'To whom it may concern,\n\nI have examined [PATIENT_NAME] today and found him/her to be in good health and physically fit. There are no signs of any communicable diseases or physical disabilities that would prevent him/her from performing routine activities.'
    },
    {
      'name': 'Procedure Leave',
      'content': 'This is to certify that [PATIENT_NAME] has undergone a medical procedure today. Due to the nature of the procedure, he/she is advised to avoid strenuous activity and rest for the next 2 days.'
    },
    {
      'name': 'Gym / Sports Fitness',
      'content': 'I have examined [PATIENT_NAME] and find him/her medically fit to participate in sports and gym activities. He/She has no known cardiac or respiratory contraindications for physical exercise.'
    },
    {
      'name': 'Chronic Illness Leave',
      'content': 'This is to certify that [PATIENT_NAME] is a known case of [DIAGNOSIS]. He/She is under regular follow-up and treatment. He/She is advised rest for [DAYS] days due to a flare-up of symptoms.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _applyTemplate(_defaultTemplates[0]);
  }

  Future<void> _loadTemplates() async {
    try {
      final response = await Supabase.instance.client
          .from('opd_medical_certificate_templates')
          .select()
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _templates = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Error loading templates: $e");
    }
  }

  void _applyTemplate(Map<String, dynamic> template) {
    String content = template['content']!;
    final now = DateTime.now();
    
    // Simple replacement logic
    content = content.replaceAll('[PATIENT_NAME]', widget.patient.name);
    content = content.replaceAll('[AGE]', widget.patient.ageInfo);
    content = content.replaceAll('[START_DATE]', DateFormat('dd MMM yyyy').format(now));
    content = content.replaceAll('[END_DATE]', DateFormat('dd MMM yyyy').format(now.add(const Duration(days: 3))));
    content = content.replaceAll('[DAYS]', '3');
    content = content.replaceAll('[FITNESS_DATE]', DateFormat('dd MMM yyyy').format(now.add(const Duration(days: 4))));
    
    setState(() {
      _selectedTemplateName = template['template_name'] ?? template['name'] ?? "";
      _contentController.text = content;
    });
  }

  Future<void> _saveAsTemplate() async {
    if (_contentController.text.isEmpty) return;
    
    final name = await _showTemplateNameDialog();
    if (name == null || name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('opd_medical_certificate_templates').insert({
        'template_name': name,
        'content': _contentController.text,
      });
      _loadTemplates();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Template Saved Successfully!")));
    } catch (e) {
      debugPrint("Save error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showTemplateNameDialog() {
    _templateNameController.clear();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Template Name"),
        content: TextField(controller: _templateNameController, decoration: const InputDecoration(hintText: "Enter template name")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, _templateNameController.text), child: const Text("SAVE")),
        ],
      ),
    );
  }

  Future<void> _generateAndPrintPDF() async {
    setState(() => _isLoading = true);
    try {
      // 1. Save record to history
      await Supabase.instance.client.from('opd_medical_certificates').insert({
        'patient_id': widget.patient.id,
        'certificate_type': _selectedTemplateName,
        'final_content': _contentController.text,
      });

      // 2. Generate PDF
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(top: 120, left: 50, right: 50, bottom: 50), // Top margin for letterhead
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(height: 40),
                pw.Text("MEDICAL CERTIFICATE", 
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
                pw.SizedBox(height: 60),
                pw.Text(_contentController.text, 
                  style: const pw.TextStyle(fontSize: 14, lineSpacing: 4),
                  textAlign: pw.TextAlign.justify),
                pw.Spacer(),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("Authorized Signature", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // 3. Open Print Dialog
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());

    } catch (e) {
      debugPrint("Print error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text("Medical Certificate Editor", style: GoogleFonts.poppins(color: const Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 17)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B), size: 18), onPressed: () => Navigator.pop(context)),
        actions: [
          _appBarAction(label: "SAVE AS TEMPLATE", icon: Icons.save_alt_rounded, color: Colors.grey[700]!, onTap: _saveAsTemplate),
          const SizedBox(width: 12),
          _appBarAction(label: "ISSUE & PRINT", icon: Icons.print_rounded, color: const Color(0xFF6366F1), onTap: _generateAndPrintPDF),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // ── LEFT: Templates ──────────────────────────────────────
          Container(
            width: 320,
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TEMPLATES", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      ..._defaultTemplates.map((t) => _templateTile(t['name']!, () => _applyTemplate(t), isDefault: true)),
                      if (_templates.isNotEmpty) ...[
                        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                        Text("MY CUSTOM TEMPLATES", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        ..._templates.map((t) => _templateTile(t['template_name'], () => _applyTemplate(t))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── RIGHT: Preview (No Header, A4 Style) ──────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Container(
                  width: 750,
                  constraints: const BoxConstraints(minHeight: 1000),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 40, offset: const Offset(0, 10))],
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.fromLTRB(60, 140, 60, 60), // Large top margin for Letterhead
                  child: Column(
                    children: [
                      Text("MEDICAL CERTIFICATE", 
                        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, decoration: TextDecoration.underline)),
                      const SizedBox(height: 60),
                      TextField(
                        controller: _contentController,
                        maxLines: null,
                        style: GoogleFonts.poppins(fontSize: 16, height: 1.8, color: const Color(0xFF334155)),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: "Start writing certificate content..."),
                      ),
                      const Spacer(),
                      const SizedBox(height: 80),
                      _buildPreviewSignature(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateTile(String name, VoidCallback onTap, {bool isDefault = false}) {
    bool isSel = _selectedTemplateName == name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF6366F1).withOpacity(0.08) : Colors.transparent,
            border: Border.all(color: isSel ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(isDefault ? Icons.star_border_rounded : Icons.description_outlined, size: 16, color: isSel ? const Color(0xFF6366F1) : Colors.grey),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: GoogleFonts.poppins(fontSize: 12, fontWeight: isSel ? FontWeight.bold : FontWeight.w500, color: isSel ? const Color(0xFF6366F1) : const Color(0xFF334155)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBarAction({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
  }

  Widget _buildPreviewSignature() {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(width: 150, height: 1, color: Colors.black45),
          const SizedBox(height: 6),
          Text("Authorized Signature", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          Text("Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}", style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
