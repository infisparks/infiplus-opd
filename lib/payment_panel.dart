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
  final _amountController = TextEditingController(text: '0');
  String _paymentMode = 'cash';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _discountController.text = (widget.patient.fullData['discount_amount'] ?? 0).toString();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _savePayment() async {
    final double discount = double.tryParse(_discountController.text.trim()) ?? 0.0;
    final double newAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    
    setState(() => _isSaving = true);
    
    try {
      final data = widget.patient.fullData;
      final List existingPayments = List.from(data['payment_entries'] ?? []);
      final double existingTotalPaid = (data['amount_paid'] ?? 0).toDouble();

      if (newAmount > 0) {
        existingPayments.add({
          'amount': newAmount,
          'paymentMode': _paymentMode,
          'time': DateTime.now().toIso8601String(),
        });
      }

      await SupabaseHandler.client.from('opd_registration').update({
        'discount_amount': discount,
        'amount_paid': existingTotalPaid + newAmount,
        'payment_entries': existingPayments,
      }).eq('id', widget.patient.opdRegistrationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment Updated Successfully!"), backgroundColor: AppColors.success),
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
    final double balance = totalFees - currentDiscount - amountPaid;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPatientSummary(),
                  const SizedBox(height: 32),
                  _sectionTitle("Billing Summary"),
                  const SizedBox(height: 16),
                  _buildBillingCards(totalFees, currentDiscount, amountPaid, balance),
                  
                  const SizedBox(height: 32),
                  _sectionTitle("Update Discount & Add Payment"),
                  const SizedBox(height: 16),
                  _buildPaymentFields(),

                  const SizedBox(height: 40),
                  _buildPrintActions(),
                  const SizedBox(height: 100),
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
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Manage Billing", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text("Add payments and discounts", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
          const Spacer(),
          IconButton(onPressed: widget.onCancel, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }

  Widget _buildPatientSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 25, backgroundColor: AppColors.primary, child: Text(widget.patient.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.patient.name, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text("UHID: #${widget.patient.id} | Visit: ${DateFormat('dd MMM yyyy').format(widget.patient.visitDate)}", 
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
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
        Container(width: 4, height: 16, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildBillingCards(double total, double discount, double paid, double balance) {
    return Column(
      children: [
        Row(
          children: [
            _statCard("Total Fees", "₹$total", AppColors.textPrimary),
            const SizedBox(width: 12),
            _statCard("Discount", "₹$discount", AppColors.success),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard("Paid", "₹$paid", AppColors.primary),
            const SizedBox(width: 12),
            _statCard("Balance", "₹$balance", balance > 0 ? AppColors.danger : AppColors.success),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentFields() {
    return Column(
      children: [
        _textField(_discountController, "Total Discount Amount (₹)", "Enter discount", icon: Icons.discount_outlined),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.bgBody, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ADD NEW PAYMENT", style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              const SizedBox(height: 16),
              _textField(_amountController, "Amount to Pay Now (₹)", "0", icon: Icons.currency_rupee_rounded, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _buildPaymentModeSelector(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentModeSelector() {
    return Row(
      children: ['cash', 'online', 'cheque'].map((mode) {
        final isSelected = _paymentMode == mode;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _paymentMode = mode),
            child: Container(
              margin: EdgeInsets.only(right: mode == 'cheque' ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
              ),
              child: Center(
                child: Text(mode.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : AppColors.textMuted)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrintActions() {
    return Column(
      children: [
        _actionButton(
          label: "Download Standard Receipt",
          icon: Icons.receipt_long_rounded,
          color: AppColors.textPrimary,
          onTap: () => BillPdfGenerator.generateAndPrintBill(patient: widget.patient, isProfessional: false),
        ),
        const SizedBox(height: 12),
        _actionButton(
          label: "Download Professional Bill",
          icon: Icons.picture_as_pdf_rounded,
          color: AppColors.primary,
          onTap: () => BillPdfGenerator.generateAndPrintBill(patient: widget.patient, isProfessional: true),
        ),
      ],
    );
  }

  Widget _actionButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2)), color: color.withValues(alpha: 0.05)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(child: OutlinedButton(onPressed: widget.onCancel, child: const Text("Cancel"))),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _savePayment,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Update & Save"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label, String hint, {IconData? icon, TextInputType keyboardType = TextInputType.number}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 18) : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
      ],
    );
  }
}
