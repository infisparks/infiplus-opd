import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'supabase_handler.dart';
import 'manage_patient/bill_pdf_generator.dart';

class PaymentPanel extends StatefulWidget {
  final Patient patient;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;

  const PaymentPanel({
    super.key,
    required this.patient,
    required this.onCancel,
    required this.onSuccess,
  });

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  final _discountController = TextEditingController();
  
  // Multi-Payment State
  List<Map<String, dynamic>> _paymentEntries = [
    {'amountController': TextEditingController(text: '0'), 'mode': 'cash'}
  ];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _discountController.text = (widget.patient.fullData['discount_amount'] ?? 0).toString();
    _setupPaymentListeners();
  }

  void _setupPaymentListeners() {
    for (var entry in _paymentEntries) {
      entry['amountController'].addListener(() => setState(() {}));
    }
  }

  void _addPaymentEntry() {
    setState(() {
      final controller = TextEditingController(text: '0');
      controller.addListener(() => setState(() {}));
      _paymentEntries.add({'amountController': controller, 'mode': 'cash'});
    });
  }

  void _removePaymentEntry(int index) {
    if (_paymentEntries.length > 1) {
      setState(() {
        _paymentEntries[index]['amountController'].dispose();
        _paymentEntries.removeAt(index);
      });
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    for (var entry in _paymentEntries) {
      entry['amountController'].dispose();
    }
    super.dispose();
  }

  Future<void> _savePayment() async {
    final double discount = double.tryParse(_discountController.text.trim()) ?? 0.0;
    
    setState(() => _isSaving = true);
    
    try {
      final data = widget.patient.fullData;
      final List existingPayments = List.from(data['payment_entries'] ?? []);
      final double existingTotalPaid = (data['amount_paid'] ?? 0).toDouble();

      double newTotalFromEntries = 0;
      List<Map<String, dynamic>> newPaymentData = [];

      for (var entry in _paymentEntries) {
        double amt = double.tryParse(entry['amountController'].text.trim()) ?? 0.0;
        if (amt > 0) {
          newTotalFromEntries += amt;
          newPaymentData.add({
            'amount': amt,
            'paymentMode': entry['mode'],
            'time': DateTime.now().toIso8601String(),
          });
        }
      }

      await SupabaseHandler.client.from('opd_registration').update({
        'discount_amount': discount,
        'amount_paid': existingTotalPaid + newTotalFromEntries,
        'payment_entries': [...existingPayments, ...newPaymentData],
      }).eq('id', widget.patient.opdRegistrationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payments Updated Successfully!"), backgroundColor: AppColors.success),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.patient.fullData;
    final double totalFees = (data['total_fees'] ?? 0).toDouble();
    final double currentDiscount = (data['discount_amount'] ?? 0).toDouble();
    final double amountPaid = (data['amount_paid'] ?? 0).toDouble();
    
    // Calculate new total from entries to show real-time balance
    double newPaymentsSum = 0;
    for (var entry in _paymentEntries) {
      newPaymentsSum += double.tryParse(entry['amountController'].text.trim()) ?? 0.0;
    }
    
    final double balance = totalFees - currentDiscount - amountPaid - newPaymentsSum;

    return Container(
      color: AppColors.bgBody,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPatientHeader(),
                  const SizedBox(height: 32),
                  
                  _sectionTitle("Billing Overview"),
                  const SizedBox(height: 16),
                  _buildBillingCards(totalFees, currentDiscount, amountPaid, balance, newPaymentsSum),
                  
                  const SizedBox(height: 32),
                  _sectionTitle("Discount & Multi-Mode Payments"),
                  const SizedBox(height: 16),
                  _buildPaymentFields(),

                  const SizedBox(height: 32),
                  _sectionTitle("Print & Export"),
                  const SizedBox(height: 16),
                  _buildPrintActions(),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Billing & Payments", 
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text("Add split payments (Cash + Online)", 
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Center(
              child: Text(widget.patient.initials, 
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.patient.name, 
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                Text("UHID: #${widget.patient.id} | Visit: ${DateFormat('dd MMM yyyy').format(widget.patient.visitDate)}", 
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withOpacity(0.9))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(title.toUpperCase(), 
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.8)),
      ],
    );
  }

  Widget _buildBillingCards(double total, double discount, double paid, double balance, double newPaid) {
    return Column(
      children: [
        Row(
          children: [
            _statCard("TOTAL FEES", "₹$total", AppColors.textPrimary, Icons.receipt_outlined),
            const SizedBox(width: 12),
            _statCard("DISCOUNT", "₹$discount", AppColors.success, Icons.local_offer_outlined),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard("TOTAL PAID", "₹${paid + newPaid}", AppColors.primary, Icons.check_circle_outline),
            const SizedBox(width: 12),
            _statCard("BALANCE", "₹$balance", balance > 0 ? AppColors.danger : AppColors.success, Icons.account_balance_wallet_outlined),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentFields() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(_discountController, "Update Discount Amount (₹)", "Enter discount", icon: Icons.discount_outlined),
          const SizedBox(height: 24),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 24),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("PAYMENT ENTRIES", 
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              TextButton.icon(
                onPressed: _addPaymentEntry,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text("Add Mode"),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_paymentEntries.length, (index) => _buildPaymentEntryRow(index)),
        ],
      ),
    );
  }

  Widget _buildPaymentEntryRow(int index) {
    final entry = _paymentEntries[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 2,
            child: _buildTextField(
              entry['amountController'], 
              "Amount (₹)", 
              "0", 
              icon: Icons.currency_rupee_rounded
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Mode", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgBody,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: entry['mode'],
                      isExpanded: true,
                      items: ['cash', 'online'].map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.toUpperCase(), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      )).toList(),
                      onChanged: (v) => setState(() => entry['mode'] = v!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_paymentEntries.length > 1) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _removePaymentEntry(index),
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrintActions() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: "Receipt",
            sub: "A5 Format",
            icon: Icons.receipt_long_rounded,
            color: AppColors.textPrimary,
            onTap: () => BillPdfGenerator.generateAndPrintBill(patient: widget.patient, isProfessional: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionButton(
            label: "Invoice",
            sub: "A5 Pro Bill",
            icon: Icons.picture_as_pdf_rounded,
            color: AppColors.primary,
            onTap: () => BillPdfGenerator.generateAndPrintBill(patient: widget.patient, isProfessional: true),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({required String label, required String sub, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.15)),
          color: color.withOpacity(0.05),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
            Text(sub, style: GoogleFonts.poppins(fontSize: 11, color: color.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onCancel,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("Cancel", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _savePayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSaving 
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) 
                : Text("Update Billing", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, {IconData? icon, TextInputType keyboardType = TextInputType.number}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 20, color: AppColors.textMuted) : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFF),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
