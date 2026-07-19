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

  // Separate loading flags for each action
  bool _isSaving = false;
  bool _isPrinting = false;
  bool _isSharing = false;

  // Pre-loaded fonts (loaded once in initState)
  pw.Font? _fontRegular;
  pw.Font? _fontBold;

  final List<Map<String, String>> _defaultTemplates = [
    {
      'name': 'General Medical Certificate',
      'content':
          'To whom it may concern,\n\nThis is to certify that [PATIENT_NAME], aged [AGE], was examined by me today.\n\n[WRITE_SPECIFIC_DETAILS_HERE]\n\nHe/She is advised [ADVICE].'
    },
    {
      'name': 'Sick Leave Certificate',
      'content':
          'To whom it may concern,\n\nThis is to certify that [PATIENT_NAME], aged [AGE], was under my clinical care from [START_DATE] to [END_DATE].\n\nHe/She is suffering from acute illness and is advised rest for [DAYS] days. He/She is fit to resume his/her duties on [FITNESS_DATE].'
    },
    {
      'name': 'Fitness Certificate',
      'content':
          'To whom it may concern,\n\nI have examined [PATIENT_NAME] today and found him/her to be in good health and physically fit. There are no signs of any communicable diseases or physical disabilities that would prevent him/her from performing routine activities.'
    },
    {
      'name': 'Procedure Leave',
      'content':
          'This is to certify that [PATIENT_NAME] has undergone a medical procedure today. Due to the nature of the procedure, he/she is advised to avoid strenuous activity and rest for the next 2 days.'
    },
    {
      'name': 'Gym / Sports Fitness',
      'content':
          'I have examined [PATIENT_NAME] and find him/her medically fit to participate in sports and gym activities. He/She has no known cardiac or respiratory contraindications for physical exercise.'
    },
    {
      'name': 'Chronic Illness Leave',
      'content':
          'This is to certify that [PATIENT_NAME] is a known case of [DIAGNOSIS]. He/She is under regular follow-up and treatment. He/She is advised rest for [DAYS] days due to a flare-up of symptoms.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadFonts();
    _loadTemplates();
    _applyTemplate(_defaultTemplates[0]);
  }

  @override
  void dispose() {
    _contentController.dispose();
    _templateNameController.dispose();
    super.dispose();
  }

  // ── Load Unicode-safe TTF fonts ─────────────────────────────────
  Future<void> _loadFonts() async {
    final reg = await PdfGoogleFonts.nunitoSansRegular();
    final bold = await PdfGoogleFonts.nunitoSansBold();
    if (mounted) {
      setState(() {
        _fontRegular = reg;
        _fontBold = bold;
      });
    }
  }

  // ── Load custom templates from Supabase ────────────────────────
  Future<void> _loadTemplates() async {
    try {
      final response = await Supabase.instance.client
          .from('opd_medical_certificate_templates')
          .select()
          .order('created_at', ascending: false);
      if (mounted) setState(() => _templates = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint("Error loading templates: $e");
    }
  }

  // ── Apply a template to the editor ────────────────────────────
  void _applyTemplate(Map<String, dynamic> template) {
    String content = template['content']!;
    final now = DateTime.now();
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

  // ── Save as Template ───────────────────────────────────────────
  Future<void> _saveAsTemplate() async {
    if (_contentController.text.isEmpty) return;
    final name = await _showTemplateNameDialog();
    if (name == null || name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.from('opd_medical_certificate_templates').insert({
        'template_name': name,
        'content': _contentController.text,
      });
      _loadTemplates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Template Saved!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Save error: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _showTemplateNameDialog() {
    _templateNameController.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Template Name"),
        content: TextField(
          controller: _templateNameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter template name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _templateNameController.text),
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  // ── Build Unicode-safe PDF bytes ───────────────────────────────
  Future<Uint8List> _buildPdfBytes() async {
    // Ensure fonts are loaded
    final fontReg = _fontRegular ?? await PdfGoogleFonts.nunitoSansRegular();
    final fontBold = _fontBold ?? await PdfGoogleFonts.nunitoSansBold();

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 100, left: 50, right: 50, bottom: 50),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(height: 20),
              pw.Text(
                "MEDICAL CERTIFICATE",
                style: pw.TextStyle(font: fontBold, fontSize: 20, decoration: pw.TextDecoration.underline),
              ),
              pw.SizedBox(height: 40),
              pw.Text(
                _contentController.text,
                style: pw.TextStyle(font: fontReg, fontSize: 13, lineSpacing: 4),
                textAlign: pw.TextAlign.justify,
              ),
              pw.SizedBox(height: 60),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(width: 150, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 5),
                    pw.Text("Authorized Signature",
                        style: pw.TextStyle(font: fontBold, fontSize: 12)),
                    pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
                        style: pw.TextStyle(font: fontReg, fontSize: 10)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  // ── Record issuance in Supabase ────────────────────────────────
  Future<void> _recordIssuance() async {
    try {
      await Supabase.instance.client.from('opd_medical_certificates').insert({
        'patient_id': widget.patient.id,
        'certificate_type': _selectedTemplateName,
        'final_content': _contentController.text,
        'issued_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Record issuance error: $e");
    }
  }

  // ── ISSUE & PRINT ──────────────────────────────────────────────
  Future<void> _issueAndPrint() async {
    if (_contentController.text.trim().isEmpty) return;
    setState(() => _isPrinting = true);
    try {
      await _recordIssuance();
      final bytes = await _buildPdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Certificate Issued & Sent to Printer ✓"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Print error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Print Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ── ISSUE & SHARE ──────────────────────────────────────────────
  // Uses Printing.sharePdf() — works on iOS, Android, macOS without share_plus
  Future<void> _issueAndShare() async {
    if (_contentController.text.trim().isEmpty) return;
    setState(() => _isSharing = true);
    try {
      await _recordIssuance();
      final bytes = await _buildPdfBytes();
      final safeName = widget.patient.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'MedCert_$safeName.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Certificate Issued & Shared ✓"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Share error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Share Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool anyLoading = _isSaving || _isPrinting || _isSharing;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          "Medical Certificate Editor",
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // ── Save As Template ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ElevatedButton.icon(
              onPressed: (anyLoading) ? null : _saveAsTemplate,
              icon: _isSaving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_alt_rounded, size: 15),
              label: const Text("SAVE AS TEMPLATE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[700],
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Issue & Print ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ElevatedButton.icon(
              onPressed: (anyLoading) ? null : _issueAndPrint,
              icon: _isPrinting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_rounded, size: 15),
              label: const Text("ISSUE & PRINT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Issue & Share ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ElevatedButton.icon(
              onPressed: (anyLoading) ? null : _issueAndShare,
              icon: _isSharing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.share_rounded, size: 15),
              label: const Text("ISSUE & SHARE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),

      body: Row(
        children: [
          // ── LEFT: Templates Panel ──────────────────────────────
          Container(
            width: 260,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Text(
                    "TEMPLATES",
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.bold,
                      color: Colors.grey, letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      ..._defaultTemplates.map((t) => _templateTile(
                            t['name']!,
                            () => _applyTemplate(t),
                            isDefault: true,
                          )),
                      if (_templates.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            "MY CUSTOM TEMPLATES",
                            style: GoogleFonts.poppins(
                              fontSize: 10, fontWeight: FontWeight.bold,
                              color: Colors.grey, letterSpacing: 1,
                            ),
                          ),
                        ),
                        ..._templates.map((t) => _templateTile(
                              t['template_name'],
                              () => _applyTemplate(t),
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── RIGHT: A4-style Editor ─────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Center(
                child: Container(
                  width: 720,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 8),
                      )
                    ],
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.fromLTRB(56, 72, 56, 56),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Letterhead placeholder
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          "[ CLINIC LETTERHEAD AREA — Appears from printer header ]",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Title
                      Text(
                        "MEDICAL CERTIFICATE",
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          decoration: TextDecoration.underline,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Editable text area
                      TextField(
                        controller: _contentController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          height: 1.9,
                          color: const Color(0xFF334155),
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: "Start writing certificate content...",
                          hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
                        ),
                      ),
                      const SizedBox(height: 56),

                      // Signature
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
    final bool isSel = _selectedTemplateName == name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF6366F1).withOpacity(0.08) : Colors.transparent,
            border: Border.all(
              color: isSel ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isDefault ? Icons.star_border_rounded : Icons.description_outlined,
                size: 15,
                color: isSel ? const Color(0xFF6366F1) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                    color: isSel ? const Color(0xFF6366F1) : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewSignature() {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(width: 150, height: 1, color: Colors.black45),
          const SizedBox(height: 6),
          Text(
            "Authorized Signature",
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          Text(
            "Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
            style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
