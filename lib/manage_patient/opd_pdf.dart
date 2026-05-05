import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import '../../main.dart'; // Ensure Patient model is imported here

// --- THEME COLORS FOR PDF ---
class PdfTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color textMain = Color(0xFF1E293B);
}

class OpdPdfComponent extends StatelessWidget {
  // CONFIGURATION
  final Patient patient;
  final int opdId;
  final DateTime date;
  final double marginTop;
  final double marginBottom;
  final Map<String, bool> printSettings;

  // DATA CONTENT
  final List<Map<String, String>> rxList;
  final String symptomsText;
  final String checkupsText;
  final String dbVitalsString;
  final String historyText;
  final String diagnosisText;
  final String investigationsText;
  final String proceduresText;
  final String instructionsText;
  final String fitnessText;
  final String notesText;

  // FOOTER DATA
  final String selectedFollowUp;
  final String followUpNote;
  final String? referDoctorName;

  const OpdPdfComponent({
    super.key,
    required this.patient,
    required this.opdId,
    required this.date,
    required this.marginTop,
    required this.marginBottom,
    required this.printSettings,
    required this.rxList,
    required this.symptomsText,
    required this.checkupsText,
    required this.dbVitalsString,
    required this.historyText,
    required this.diagnosisText,
    required this.investigationsText,
    required this.proceduresText,
    required this.instructionsText,
    required this.fitnessText,
    required this.notesText,
    required this.selectedFollowUp,
    required this.followUpNote,
    this.referDoctorName,
  });

  @override
  Widget build(BuildContext context) {
    // A4 Dimensions in logic pixels (approximate for screen preview)
    const double a4Width = 794;
    const double a4Height = 1123;

    return Container(
      width: a4Width,
      constraints: const BoxConstraints(minHeight: a4Height),
      decoration: BoxDecoration(
        color: Colors.white,
        
      ),
      child: Column(
        children: [
          SizedBox(height: marginTop),

          // CONTENT AREA
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER ---
                _buildCompactHeader(),
                const Divider(thickness: 1.5, height: 25, color: Colors.black12),

                // 1. Symptoms
                if (printSettings["Symptoms"] == true && symptomsText.isNotEmpty)
                  _buildProSection("Complaints", symptomsText),

                // 2. Medical History
                if (printSettings["Medical History"] == true && historyText.isNotEmpty)
                  _buildProSection("History", historyText),

                // 3. Checkups
                if (printSettings["Check-Ups"] == true && (dbVitalsString.isNotEmpty || checkupsText.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("CHECK-UPS", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.black87)),
                        if (dbVitalsString.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(dbVitalsString, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        if (checkupsText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(checkupsText, style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ),

                // 4. Diagnosis
                if (printSettings["Diagnosis"] == true && diagnosisText.isNotEmpty)
                  _buildProSection("Diagnosis", diagnosisText),

                const SizedBox(height: 12),

                // 5. Rx Table
                if (rxList.isNotEmpty) ...[
                  Table(
                    border: TableBorder.all(color: Colors.grey[300]!, width: 0.5),
                    columnWidths: const {
                      0: FlexColumnWidth(0.4),
                      1: FlexColumnWidth(4),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(1.2),
                      4: FlexColumnWidth(3)
                    },
                    children: [
                      TableRow(
                          decoration: BoxDecoration(color: Colors.grey[100]),
                          children: const [
                            _TableCell(text: "#", isHeader: true),
                            _TableCell(text: "Medicine", isHeader: true),
                            _TableCell(text: "Freq", isHeader: true),
                            _TableCell(text: "Dur", isHeader: true),
                            _TableCell(text: "Instr", isHeader: true),
                          ]),
                      ...rxList.asMap().entries.map((e) => TableRow(children: [
                        _TableCell(text: "${e.key + 1}"),
                        _TableCell(text: e.value['name']!, isBold: true),
                        _TableCell(text: e.value['freq']!, isBold: true),
                        _TableCell(text: e.value['dur']!),
                        _TableCell(text: e.value['note']!, fontSize: 10),
                      ]))
                    ],
                  ),
                  const SizedBox(height: 15),
                ],

                // 6. Footer Sections
                if (printSettings["Investigation Results"] == true && investigationsText.isNotEmpty)
                  _buildProSection("Investigations", investigationsText),

                if (printSettings["Procedures"] == true && proceduresText.isNotEmpty)
                  _buildProSection("Procedures", proceduresText),

                if ((printSettings["Instructions"] ?? true) && instructionsText.isNotEmpty)
                  _buildProSection("Advice", instructionsText),

                if (printSettings["Fitness Plan"] == true && fitnessText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border.all(color: Colors.grey[300]!)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Diet & Fitness:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          Text(fitnessText, style: const TextStyle(fontSize: 10))
                        ]),
                  ),

                if (printSettings["Clinical Notes"] == true && notesText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Remarks:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        Text(notesText, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Footer Box
                if (selectedFollowUp.isNotEmpty || referDoctorName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (selectedFollowUp.isNotEmpty)
                          RichText(
                              text: TextSpan(
                                  style: const TextStyle(color: Colors.black, fontSize: 12),
                                  children: [
                                    const TextSpan(text: "Next Review: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextSpan(text: "After $selectedFollowUp ", style: const TextStyle(fontWeight: FontWeight.bold, color: PdfTheme.primary)),
                                    if (followUpNote.isNotEmpty)
                                      TextSpan(text: "($followUpNote)", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 11)),
                                  ])),
                        if (referDoctorName != null)
                          RichText(
                              text: TextSpan(
                                  style: const TextStyle(color: Colors.black, fontSize: 12),
                                  children: [
                                    const TextSpan(text: "Referred To: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextSpan(text: "Dr. $referDoctorName"),
                                  ])),
                      ],
                    ),
                  ),

                if (printSettings["Signature"] == true)
                  Container(
                    margin: const EdgeInsets.only(top: 40),
                    alignment: Alignment.centerRight,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: 30, width: 120),
                        Divider(color: Colors.black45, indent: 10, endIndent: 10, thickness: 0.5),
                        Text("Authorized Signature", style: TextStyle(fontSize: 10, color: Colors.black54)),
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

  Widget _buildCompactHeader() {
    final formattedDate = DateFormat('dd/MM/yyyy').format(date);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patient.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: Colors.black87, fontFamily: 'Roboto', height: 1.4),
                    children: [
                      TextSpan(text: "${patient.ageInfo} / ${patient.gender}   |   "),
                      TextSpan(text: "PID: ${patient.id}"),
                    ]),
              ),
              const SizedBox(height: 2),
              Text("Phone: ${patient.phone}", style: const TextStyle(fontSize: 12, color: Colors.black87)),
              if (patient.address != null && patient.address!.isNotEmpty)
                Text("Addr: ${patient.address}", style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        QrImageView(
          data: opdId.toString(),
          version: QrVersions.auto,
          size: 50.0,
          padding: EdgeInsets.zero,
          gapless: false,
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                child: Text("OPD ID: #$opdId", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ),
              const SizedBox(height: 4),
              Text("Date: $formattedDate", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              if (referDoctorName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("Ref: Dr. $referDoctorName", style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: Colors.black54))),
        Expanded(child: Text(content, style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3)))
      ]),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool isBold;
  final double fontSize;
  const _TableCell({required this.text, this.isHeader = false, this.isBold = false, this.fontSize = 11});
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(6),
        child: Text(text, style: TextStyle(fontWeight: (isHeader || isBold) ? FontWeight.bold : FontWeight.normal, fontSize: fontSize)));
  }
}