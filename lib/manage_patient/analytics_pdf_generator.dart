import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/analytics_service.dart';

class AnalyticsPdfGenerator {
  static Future<Uint8List> generatePdf({
    required ClinicalAnalyticsResult analytics,
    required ClinicalAnalyticsFilter filter,
  }) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.poppinsRegular();
    final fontBold = await PdfGoogleFonts.poppinsBold();
    final fontSemiBold = await PdfGoogleFonts.poppinsSemiBold();

    final primaryColor = PdfColor.fromHex("#4F46E5"); // Indigo-600
    final secondaryColor = PdfColor.fromHex("#6366F1"); // Indigo-500
    final darkText = PdfColor.fromHex("#0F172A");
    final mutedText = PdfColor.fromHex("#64748B");
    final bgLight = PdfColor.fromHex("#F8FAFC");
    final borderColor = PdfColor.fromHex("#E2E8F0");

    final dateRangeStr = "${DateFormat('dd MMM yyyy').format(filter.startDate)} - ${DateFormat('dd MMM yyyy').format(filter.endDate)}";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "CLINICAL DATA ANALYTICS & INTELLIGENCE REPORT",
                          style: pw.TextStyle(font: fontBold, fontSize: 13, color: primaryColor, letterSpacing: 0.5),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "Hospital: ${filter.hospital}  |  Period: $dateRangeStr",
                          style: pw.TextStyle(font: fontRegular, fontSize: 9, color: mutedText),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: secondaryColor,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        "InfiPlus HMS",
                        style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.white),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 1, color: borderColor),
                pw.SizedBox(height: 8),
              ],
            );
          }
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Clinical Analytics · $dateRangeStr", style: pw.TextStyle(font: fontRegular, fontSize: 7, color: mutedText)),
              pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: pw.TextStyle(font: fontRegular, fontSize: 7, color: mutedText)),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              "Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} | Confidential Medical Intelligence Report",
              style: pw.TextStyle(font: fontRegular, fontSize: 7, color: mutedText),
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // ── 1. KPI SUMMARY CARDS ─────────────────────────────
            pw.Row(
              children: [
                _buildKpiCard("TOTAL VISITS", "${analytics.totalVisits}", primaryColor, fontBold, fontRegular, bgLight, borderColor),
                pw.SizedBox(width: 8),
                _buildKpiCard("UNIQUE PATIENTS", "${analytics.uniquePatients}", PdfColor.fromHex("#0EA5E9"), fontBold, fontRegular, bgLight, borderColor),
                pw.SizedBox(width: 8),
                _buildKpiCard("MALE / FEMALE", "${analytics.maleCount} / ${analytics.femaleCount}", PdfColor.fromHex("#F59E0B"), fontBold, fontRegular, bgLight, borderColor),
              ],
            ),
            pw.SizedBox(height: 14),

            // ── 2. ACTIVE FILTERS SUMMARY (IF ANY) ────────────────
            if (filter.hasActiveFilters)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                margin: const pw.EdgeInsets.only(bottom: 14),
                decoration: pw.BoxDecoration(
                  color: bgLight,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderColor, width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("APPLIED CLINICAL CRITERIA:", style: pw.TextStyle(font: fontBold, fontSize: 8, color: darkText)),
                    pw.SizedBox(height: 3),
                    pw.Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (filter.medicines.isNotEmpty) pw.Text("Medicines: ${filter.medicines.join(', ')}", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText)),
                        if (filter.diagnoses.isNotEmpty) pw.Text("Diagnoses: ${filter.diagnoses.join(', ')}", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText)),
                        if (filter.symptoms.isNotEmpty) pw.Text("Symptoms: ${filter.symptoms.join(', ')}", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText)),
                        if (filter.investigations.isNotEmpty) pw.Text("Tests: ${filter.investigations.join(', ')}", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText)),
                        if (filter.advices.isNotEmpty) pw.Text("Advice: ${filter.advices.join(', ')}", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText)),
                      ],
                    ),
                  ],
                ),
              ),

            // ── 3. TOP CLINICAL DISTRIBUTIONS ────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Top Diagnoses
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderColor, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("TOP DIAGNOSES", style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: darkText)),
                        pw.SizedBox(height: 6),
                        if (analytics.topDiagnoses.isEmpty)
                          pw.Text("No diagnosis recorded", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText))
                        else
                          ...analytics.topDiagnoses.take(5).map((d) => _buildRankRow(d['name']?.toString() ?? '', d['count']?.toString() ?? '0', fontRegular, fontBold, primaryColor)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),

                // Top Prescribed Medicines
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderColor, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("TOP PRESCRIBED MEDICINES", style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: darkText)),
                        pw.SizedBox(height: 6),
                        if (analytics.topMedicines.isEmpty)
                          pw.Text("No prescriptions recorded", style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mutedText))
                        else
                          ...analytics.topMedicines.take(5).map((m) => _buildRankRow(m['name']?.toString() ?? '', m['count']?.toString() ?? '0', fontRegular, fontBold, secondaryColor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // ── 4. MATCHED PATIENT VISITS TABLE ──────────────────
            pw.Text("PATIENT VISIT RECORDS (${analytics.records.length})", style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: darkText)),
            pw.SizedBox(height: 6),

            if (analytics.records.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                alignment: pw.Alignment.center,
                child: pw.Text("No patient records matching this criteria", style: pw.TextStyle(font: fontRegular, fontSize: 9, color: mutedText)),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(color: borderColor, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.2), // Date
                  1: pw.FlexColumnWidth(1.2), // UHID
                  2: pw.FlexColumnWidth(2.0), // Name / Demographics
                  3: pw.FlexColumnWidth(1.8), // Diagnosis
                  4: pw.FlexColumnWidth(2.2), // Prescriptions
                  5: pw.FlexColumnWidth(1.4), // Advice / Test
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: bgLight),
                    children: [
                      _th("Visit Date", fontBold),
                      _th("UHID", fontBold),
                      _th("Patient Details", fontBold),
                      _th("Diagnosis", fontBold),
                      _th("Medicines", fontBold),
                      _th("Tests & Advice", fontBold),
                    ],
                  ),
                  // Data Rows
                  ...analytics.records.map((r) {
                    final dateStr = DateFormat('dd/MM/yy').format(r.createdAt);
                    final diagStr = r.diagnoses.isNotEmpty ? r.diagnoses.join(', ') : '—';
                    final medStr = r.medicines.isNotEmpty
                        ? r.medicines.map((m) => m['name']?.toString() ?? '').where((n) => n.isNotEmpty).join(', ')
                        : '—';
                    final testsAndAdvice = [...r.investigations, ...r.advices].join(', ');

                    return pw.TableRow(
                      children: [
                        _td(dateStr, fontRegular, fontSize: 7.5),
                        _td(r.uhid, fontSemiBold, fontSize: 7.5),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(r.patientName, style: pw.TextStyle(font: fontBold, fontSize: 8)),
                              pw.Text("${r.ageInfo} / ${r.gender}", style: pw.TextStyle(font: fontRegular, fontSize: 7, color: mutedText)),
                            ],
                          ),
                        ),
                        _td(diagStr, fontRegular, fontSize: 7.5),
                        _td(medStr, fontRegular, fontSize: 7.5),
                        _td(testsAndAdvice.isNotEmpty ? testsAndAdvice : '—', fontRegular, fontSize: 7),
                      ],
                    );
                  }),
                ],
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildKpiCard(
    String label,
    String value,
    PdfColor color,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor bg,
    PdfColor border,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: border, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: PdfColor.fromHex("#64748B"))),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildRankRow(
    String name,
    String count,
    pw.Font fontRegular,
    pw.Font fontBold,
    PdfColor barColor,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              name,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: pw.BoxDecoration(
              color: barColor,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              count,
              style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _th(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColor.fromHex("#0F172A"))),
    );
  }

  static pw.Widget _td(String text, pw.Font font, {double fontSize = 8}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: fontSize, color: PdfColor.fromHex("#334155"))),
    );
  }

  static Future<void> exportPdfReport({
    required ClinicalAnalyticsResult analytics,
    required ClinicalAnalyticsFilter filter,
  }) async {
    final bytes = await generatePdf(analytics: analytics, filter: filter);
    final fileName = "Clinical_Analytics_${DateFormat('yyyyMMdd').format(filter.startDate)}_${DateFormat('yyyyMMdd').format(filter.endDate)}.pdf";

    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }
}
