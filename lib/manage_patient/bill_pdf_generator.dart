import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../main.dart';

class BillPdfGenerator {
  static Future<void> generateAndPrintBill({
    required Patient patient,
    required bool isProfessional,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.poppinsRegular();
    final fontBold = await PdfGoogleFonts.poppinsBold();

    final data = patient.fullData;
    final double totalFees = (data['total_fees'] ?? 0).toDouble();
    final double discount = (data['discount_amount'] ?? 0).toDouble();
    final double amountPaid = (data['amount_paid'] ?? 0).toDouble();
    final double balance = totalFees - discount - amountPaid;
    final List paymentEntries = data['payment_entries'] ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(data['hospital_name'] ?? "Clinical Receipt", style: pw.TextStyle(font: fontBold, fontSize: 14)),
                      pw.Text("OPD BILL RECEIPT", style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text("ID: #${patient.opdRegistrationId}", style: pw.TextStyle(font: fontBold, fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 10),

              // Patient Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("PATIENT DETAILS", style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600)),
                      pw.Text(patient.name, style: pw.TextStyle(font: fontBold, fontSize: 12)),
                      pw.Text("${patient.ageInfo} / ${patient.gender}", style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("DATE", style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey600)),
                      pw.Text(DateFormat('dd MMM yyyy').format(patient.visitDate), style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.Text(DateFormat('hh:mm a').format(patient.visitDate), style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Billing Details
              pw.Text("BILLING SUMMARY", style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 8),
              _buildBillRow("Consultation Fees", totalFees, font, fontBold),
              if (discount > 0) _buildBillRow("Discount", -discount, font, fontBold, isDiscount: true),
              pw.Divider(thickness: 0.5, color: PdfColors.grey200, indent: 50),
              _buildBillRow("Net Amount", totalFees - discount, font, fontBold, isTotal: true),
              _buildBillRow("Total Paid", amountPaid, font, fontBold),
              pw.Divider(thickness: 1, color: PdfColors.black),
              _buildBillRow("BALANCE DUE", balance, font, fontBold, isTotal: true, color: PdfColors.red700),

              if (isProfessional && paymentEntries.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text("PAYMENT HISTORY", style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey600)),
                pw.SizedBox(height: 5),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        _cell("Date", fontBold, fontSize: 8),
                        _cell("Mode", fontBold, fontSize: 8),
                        _cell("Amount", fontBold, fontSize: 8),
                      ],
                    ),
                    ...paymentEntries.map((e) {
                      final dt = DateTime.tryParse(e['time'] ?? '') ?? DateTime.now();
                      return pw.TableRow(
                        children: [
                          _cell(DateFormat('dd/MM HH:mm').format(dt), font, fontSize: 8),
                          _cell(e['paymentMode']?.toString().toUpperCase() ?? 'CASH', font, fontSize: 8),
                          _cell("₹${e['amount']}", font, fontSize: 8),
                        ],
                      );
                    }),
                  ],
                ),
              ],

              pw.Spacer(),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Thank you for your visit.", style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  pw.Column(
                    children: [
                      pw.SizedBox(height: 20),
                      pw.Text("Authorized Signature", style: pw.TextStyle(font: font, fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      format: PdfPageFormat.a5,
      dynamicLayout: false,
      name: "Bill_${patient.id}_${patient.opdRegistrationId}.pdf",
    );
  }

  static pw.Widget _buildBillRow(String label, double amount, pw.Font font, pw.Font fontBold, {bool isDiscount = false, bool isTotal = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: isTotal ? fontBold : font, fontSize: isTotal ? 11 : 10)),
          pw.Text(
            "${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}",
            style: pw.TextStyle(font: fontBold, fontSize: isTotal ? 12 : 10, color: color ?? (isDiscount ? PdfColors.green700 : PdfColors.black)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _cell(String text, pw.Font font, {double fontSize = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: fontSize)),
    );
  }
}
