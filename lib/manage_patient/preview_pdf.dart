import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart'; // Ensure this import path matches your project structure

class PdfTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color textMain = Color(0xFF1E293B);
}

class PreviewPdfComponent extends StatelessWidget {
  // PURE DATA INPUTS
  final Patient patient;
  final int opdId;
  final DateTime date;

  final Map<String, dynamic> config; // Report settings & Margins

  // Data Maps
  final String symptomsText;
  final String diagnosisText;
  final String historyText;
  final String checkupsText;
  final String vitalsText;

  final List<Map<String, String>> rxList; // Processed Rx List
  final String instructionsText;
  final String investigationsText;
  final String proceduresText;

  // UPDATED: Structured Fitness Data instead of simple String
  final List<Map<String, dynamic>> fitnessPlans;

  final String notesText;
  final String followUpText;
  final String referDoctorText;
  final List<Map<String, String>> bloodResults;

  const PreviewPdfComponent({
    super.key,
    required this.patient,
    required this.opdId,
    required this.date,
    required this.config,
    required this.symptomsText,
    required this.diagnosisText,
    required this.historyText,
    required this.checkupsText,
    required this.vitalsText,
    required this.rxList,
    required this.instructionsText,
    required this.investigationsText,
    required this.proceduresText,
    required this.fitnessPlans,
    required this.notesText,
    required this.followUpText,
    required this.referDoctorText,
    required this.bloodResults,
  });

  @override
  Widget build(BuildContext context) {
    // A4 Dimensions Logic
    const double a4Width = 794;
    const double a4Height = 1123;

    // Extract Settings
    final Map<String, bool> toggles = Map<String, bool>.from(config['toggles'] ?? {});
    final double marginTop = (config['margin_top'] ?? 50.0).toDouble();
    final double marginBottom = (config['margin_bottom'] ?? 50.0).toDouble();

    return Container(
      width: a4Width,
      constraints: const BoxConstraints(minHeight: a4Height),
      decoration: BoxDecoration(
        color: Colors.white,
        
      ),
      child: Column(
        children: [
          SizedBox(height: marginTop),

          // CONTENT
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const Divider(thickness: 1.5, height: 25, color: Colors.black12),

                // 1. VITALS BAR (Prominent Top Level)
                if (vitalsText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black12, width: 0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.monitor_heart_rounded, size: 14, color: PdfTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vitalsText.toUpperCase(), 
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 8.5, color: PdfTheme.primary, letterSpacing: 0.5),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // 2. CHECK-UPS (Independent Toggle)
                if (toggles["Check-Ups"] == true && checkupsText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("CHECK-UPS & OBSERVATIONS", style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 9, color: Colors.black)),
                        Padding(padding: const EdgeInsets.only(top: 2), child: Text(checkupsText, style: GoogleFonts.poppins(fontSize: 9))),
                      ],
                    ),
                  ),

                // 2. SYMPTOMS
                if (toggles["Symptoms"] == true && symptomsText.isNotEmpty)
                  _buildSection("SYMPTOMS", symptomsText),

                // 3. DIAGNOSIS
                if (toggles["Diagnosis"] == true && diagnosisText.isNotEmpty)
                  _buildSection("DIAGNOSIS", diagnosisText),

                // 4. BLOOD TEST RESULTS
                if (toggles["Blood Results"] == true && bloodResults.isNotEmpty)
                  _buildSection(
                    "BLOOD TEST", 
                    bloodResults.map((r) => "${r['name']}: ${r['value']} ${r['unit']}".trim()).join(", ")
                  ),

                // 4. MEDICINE TABLE
                if (rxList.isNotEmpty) ...[
                  Table(
                    border: TableBorder.all(color: Colors.grey[300]!, width: 0.5),
                    columnWidths: const {
                      0: FlexColumnWidth(3.4), 1: FlexColumnWidth(1.3), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(3.8)
                    },
                    children: [
                      TableRow(
                          decoration: BoxDecoration(color: Colors.grey[200]),
                          children: const [
                            _TableCell(text: "Medicine", isHeader: true, fontSize: 8),
                            _TableCell(text: "Frequency", isHeader: true, fontSize: 8),
                            _TableCell(text: "Duration", isHeader: true, fontSize: 8),
                            _TableCell(text: "Instructions", isHeader: true, fontSize: 8),
                          ]),
                      ...rxList.map((e) => TableRow(children: [
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (e['type'] != null && e['type']!.isNotEmpty)
                                  TextSpan(text: "${e['type']}  ", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 7, color: Colors.grey[500])),
                                TextSpan(text: e['name'] ?? '', style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 8.5, color: Colors.black)),
                                if (e['unit'] != null && e['unit']!.isNotEmpty)
                                  TextSpan(text: " ${e['unit']}", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 7, color: Colors.grey[500])),
                              ],
                            ),
                          ),
                        ),
                        _TableCell(text: e['freq']!, isBold: false, fontSize: 8.5),
                        _TableCell(text: e['dur']!, isBold: false, fontSize: 8.5),
                        _TableCell(text: e['note']!, fontSize: 8),
                      ]))
                    ],
                  ),
                  const SizedBox(height: 15),
                ],

                // 5. INSTRUCTIONS
                if ((toggles["Instructions"] ?? true) && instructionsText.isNotEmpty)
                  _buildSection("INSTRUCTIONS", instructionsText),

                // 6. ADVICE INVESTIGATION
                if (toggles["Investigation Results"] == true && investigationsText.isNotEmpty)
                  _buildSection("ADVICE INVESTIGATION", investigationsText),

                // 7. PROCEDURES
                if (toggles["Procedures"] == true && proceduresText.isNotEmpty)
                  _buildSection("PROCEDURES", proceduresText),

                // REST: History, Fitness, Notes
                if (toggles["Medical History"] == true && historyText.isNotEmpty)
                  _buildSection("HISTORY", historyText),

                if (toggles["Fitness Plan"] == true && fitnessPlans.isNotEmpty)
                  ...fitnessPlans.map((plan) => _buildFitnessTable(plan)),

                if (toggles["Clinical Notes"] == true && notesText.isNotEmpty)
                  _buildSection("REMARKS", notesText),

                const SizedBox(height: 20),

                // Footer
                if (followUpText.isNotEmpty || referDoctorText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(followUpText, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 10.5, color: PdfTheme.primary)),
                        Text(referDoctorText, style: GoogleFonts.poppins(fontSize: 10.5, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),

                if (toggles["Signature"] == true)
                  Container(
                    margin: const EdgeInsets.only(top: 40),
                    alignment: Alignment.centerRight,
                    child: const Column(
                      children: [
                        SizedBox(height: 30, width: 120),
                        Divider(color: Colors.black45, indent: 10, endIndent: 10, thickness: 0.5),
                        Text("Authorized Signature", style: TextStyle(fontSize: 8.5, color: Colors.black54)),
                      ],
                    ),
                  )
              ],
            ),
          ),
          SizedBox(height: marginBottom),
        ],
      ),
    );
  }

  // --- Professional Fitness Table Builder ---
  Widget _buildFitnessTable(Map<String, dynamic> plan) {
    bool isDiet = plan['type'].toString().contains('diet');
    String title = plan['title'] ?? "Wellness Plan";
    List<dynamic> entries = plan['entries'] ?? [];

    if(entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.black26, width: 1))
              ),
              child: Row(
                children: [
                  Icon(isDiet ? Icons.restaurant_menu : Icons.directions_run, size: 14, color: Colors.black),
                  const SizedBox(width: 8),
                  // UPDATED STYLE: Black and Bold
                  Text(title.toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 9, color: Colors.black)),
                ],
              )
          ),
          const SizedBox(height: 8),

          // Data Table
          Table(
            border: TableBorder.all(color: Colors.grey[300]!, width: 0.5),
            columnWidths: isDiet
                ? const { 0: FlexColumnWidth(1.2), 1: FlexColumnWidth(3) } // Diet Widths
                : const { 0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(2) }, // Exercise Widths
            children: [
              // Header Row
              TableRow(
                  decoration: BoxDecoration(color: Colors.grey[50]),
                  children: isDiet
                      ? const [
                    _TableCell(text: "TIME SLOT", isHeader: true, fontSize: 10),
                    _TableCell(text: "RECOMMENDED MENU", isHeader: true, fontSize: 10),
                  ]
                      : const [
                    _TableCell(text: "ACTIVITY", isHeader: true, fontSize: 8.5),
                    _TableCell(text: "DURATION", isHeader: true, fontSize: 8.5),
                    _TableCell(text: "NOTES", isHeader: true, fontSize: 8.5),
                  ]
              ),
              // Data Rows
              ...entries.whereType<Map>().map((item) {
                if(isDiet) {
                  return TableRow(children: [
                    _TableCell(text: item['timeSlot'] ?? '', isBold: true, fontSize: 10),
                    _TableCell(text: item['description'] ?? '', fontSize: 10),
                  ]);
                } else {
                  return TableRow(children: [
                    _TableCell(text: item['activity'] ?? '', isBold: true, fontSize: 8.5),
                    _TableCell(text: "${item['durationMinutes']} mins", fontSize: 8.5),
                    _TableCell(text: item['note'] ?? '-', fontSize: 8.5),
                  ]);
                }
              })
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patient.name, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
              Text("${patient.ageInfo} / ${patient.gender}   |   PID: ${patient.id}", style: GoogleFonts.poppins(fontSize: 9)),
              Text("Phone: ${patient.phone}", style: GoogleFonts.poppins(fontSize: 9)),
            ],
          ),
        ),
        QrImageView(data: opdId.toString(), size: 50.0),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("OPD ID: #$opdId", style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 11)),
              Text("Date: ${DateFormat('dd/MM/yyyy').format(date)}", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 120, // Increased width to fit longer titles on one line
            // UPDATED STYLE: Black and Bold
            child: Text(title.toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 8, color: Colors.black))
        ),
        Expanded(child: Text(content, style: GoogleFonts.poppins(fontSize: 9, color: Colors.black87, height: 1.3)))
      ]),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool isBold;
  final double fontSize;
  final Color? color;
  const _TableCell({required this.text, this.isHeader = false, this.isBold = false, this.fontSize = 11, this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(6),
        child: Text(text,
            style: GoogleFonts.poppins(
                fontWeight: (isHeader || isBold) ? FontWeight.w900 : FontWeight.normal,
                fontSize: fontSize,
                color: color ?? Colors.black87
            )
        )
    );
  }
}