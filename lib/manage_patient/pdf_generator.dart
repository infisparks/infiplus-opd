import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../main.dart'; // Ensure Patient model is imported here

class ReportPdfGenerator {
  static Future<Uint8List> generatePdf({
    required Patient patient,
    required int opdId,
    required DateTime date,
    required Map<String, dynamic> config,
    required String symptomsText,
    required String diagnosisText,
    required String historyText,
    required String checkupsText,
    required String vitalsText,
    required List<Map<String, String>> rxList,
    required String instructionsText,
    required String investigationsText,
    required String proceduresText,
    required List<Map<String, dynamic>> fitnessPlans,
    required String notesText,
    required String followUpText,
    required String referDoctorText,
    required List<Map<String, String>> bloodResults,
  }) async {
    final pdf = pw.Document();

    // Settings
    final Map<String, bool> toggles = Map<String, bool>.from(config['toggles'] ?? {});
    final double marginTop = (config['margin_top'] ?? 50.0).toDouble();
    final double marginBottom = (config['margin_bottom'] ?? 50.0).toDouble();

    // Use Poppins for a premium, modern clinical look
    final font = await PdfGoogleFonts.poppinsRegular();
    final fontBold = await PdfGoogleFonts.poppinsBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.only(top: marginTop, bottom: marginBottom, left: 35, right: 35),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
             return pw.Column(
               children: [
                 _buildHeader(patient, opdId, date, font, fontBold),
                 pw.Divider(thickness: 1.5, height: 25, color: PdfColors.grey300),
               ]
             );
          }
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("${patient.name} - #$opdId", style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
              pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
            ]
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text("Report generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}  |  Infiplus OPD", style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey500)),
          );
        },
        build: (pw.Context context) {
          return [
              // 2. VITALS BANNER
              if (vitalsText.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 16),
                  child: pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        vitalsText.toUpperCase(),
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 8.5,
                          color: PdfColors.blue700,
                          letterSpacing: 0.5,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                ),

              // 3. CHECK-UPS & OBSERVATIONS
              if (toggles["Check-Ups"] == true && checkupsText.isNotEmpty)
                _buildSection("CHECK-UPS & OBSERVATIONS", checkupsText, font, fontBold),

              // 4. SYMPTOMS
              if (toggles["Symptoms"] == true && symptomsText.isNotEmpty)
                _buildSection("SYMPTOMS", symptomsText, font, fontBold),

              // 5. DIAGNOSIS
              if (toggles["Diagnosis"] == true && diagnosisText.isNotEmpty)
                _buildSection("DIAGNOSIS", diagnosisText, font, fontBold),

              // 6. BLOOD TEST RESULTS
              if (toggles["Blood Results"] == true && bloodResults.isNotEmpty)
                _buildSection(
                  "BLOOD TEST",
                  bloodResults.map((r) => "${r['name']}: ${r['value']} ${r['unit']}".trim()).join(", "),
                  font,
                  fontBold
                ),

              // 7. MEDICINE TABLE
              if (rxList.isNotEmpty) ...[
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3.4), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(1.5), 3: pw.FlexColumnWidth(3.8)
                  },
                  children: [
                    pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          _tableCell("Medicine", fontBold, isHeader: true, fontSize: 10),
                          _tableCell("Frequency", fontBold, isHeader: true, fontSize: 10),
                          _tableCell("Duration", fontBold, isHeader: true, fontSize: 10),
                          _tableCell("Instructions", fontBold, isHeader: true, fontSize: 10),
                        ]),
                    ...rxList.map((e) => pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              if (e['type'] != null && e['type']!.isNotEmpty)
                                  pw.TextSpan(
                                  text: "${() {
                                    final t = e['type']!.toLowerCase().trim();
                                    if (t == 'tablet') return 'Tab';
                                    if (t == 'capsule') return 'Cap';
                                    if (t == 'syrup') return 'Syr';
                                    if (t == 'injection') return 'Inj';
                                    return e['type'];
                                  }()}  ", 
                                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey600)
                                ),
                              pw.TextSpan(text: e['name'] ?? '', style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black)),
                              if (e['unit'] != null && e['unit']!.isNotEmpty)
                                pw.TextSpan(text: " ${e['unit']}", style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey600)),
                            ],
                          ),
                        ),
                      ),
                      _tableCell(e['freq']!, font, fontSize: 10.5),
                      _tableCell(e['dur']!, font, fontSize: 10.5),
                      _tableCell(e['note']!, font, fontSize: 10),
                    ]))
                  ],
                ),
                pw.SizedBox(height: 15),
              ],

              // 8. INSTRUCTIONS & ADVICE
              if ((toggles["Instructions"] ?? true) && instructionsText.isNotEmpty)
                _buildSection("INSTRUCTIONS", instructionsText, font, fontBold),

              if (toggles["Investigation Results"] == true && investigationsText.isNotEmpty)
                _buildSection("ADVICE INVESTIGATION", investigationsText, font, fontBold),

              if (toggles["Procedures"] == true && proceduresText.isNotEmpty)
                _buildSection("PROCEDURES", proceduresText, font, fontBold),

              // 9. HISTORY, FITNESS, NOTES
              if (toggles["Medical History"] == true && historyText.isNotEmpty)
                _buildSection("HISTORY", historyText, font, fontBold),

              if (toggles["Fitness Plan"] == true && fitnessPlans.isNotEmpty)
                ...fitnessPlans.map((plan) => _buildFitnessTable(plan, font, fontBold)),

              if (toggles["Clinical Notes"] == true && notesText.isNotEmpty)
                _buildSection("REMARKS", notesText, font, fontBold),

              pw.SizedBox(height: 20),

              // 10. FOOTER
              if (followUpText.isNotEmpty || referDoctorText.isNotEmpty)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(followUpText, style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColor.fromHex("#2563EB"))),
                      pw.Text(referDoctorText, style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ),
              
              if (toggles["Signature"] == true)
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 30),
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    children: [
                      pw.SizedBox(height: 30, width: 120),
                      pw.Divider(color: PdfColors.grey600, thickness: 0.5),
                      pw.Text("Authorized Signature", style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                )
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printPdf(Uint8List bytes, String filename) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: filename,
    );
  }

  static Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: filename,
    );
  }


  static pw.Widget _buildHeader(Patient patient, int opdId, DateTime date, pw.Font font, pw.Font fontBold) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(patient.name, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.black)),
              pw.SizedBox(height: 4),
              pw.Text("${patient.ageInfo} / ${patient.gender}   |   PID: ${patient.id}", style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text("Phone: ${patient.phone}", style: pw.TextStyle(font: font, fontSize: 9)),
              if (patient.address != null && patient.address!.isNotEmpty)
                pw.Text("Addr: ${patient.address}", style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: opdId.toString(),
          width: 50,
          height: 50,
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text("OPD ID: #$opdId", style: pw.TextStyle(font: fontBold, fontSize: 11)),
              ),
              pw.SizedBox(height: 4),
              pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(date)}", style: pw.TextStyle(font: fontBold, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSection(String title, String content, pw.Font font, pw.Font fontBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12.0),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130, // Increased width to accommodate larger title
            child: pw.Text(title.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.black)),
          ),
          pw.Expanded(
            child: pw.Text(content, style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.black)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableCell(String text, pw.Font font, {bool isHeader = false, double fontSize = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: fontSize),
      ),
    );
  }

  static pw.Widget _buildFitnessTable(Map<String, dynamic> plan, pw.Font font, pw.Font fontBold) {
    final entries = plan['entries'] as List?;
    if (entries == null || entries.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Text("${plan['title']} Plan:".toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColor.fromHex("#2563EB"))),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
          children: [
            ...entries.map((item) {
                return pw.TableRow(children: [
                  _tableCell(item['name'] ?? item['activity'] ?? '', fontBold, fontSize: 9),
                  _tableCell("${item['duration'] ?? item['durationMinutes'] ?? ''}", font, fontSize: 9),
                  _tableCell(item['note'] ?? '-', font, fontSize: 9),
                ]);
            })
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }
}
