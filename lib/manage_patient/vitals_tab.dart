import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart'; // AppColors + Patient
import '../supabase_handler.dart';
import '../patient_vitals_trend.dart';

class VitalsTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const VitalsTab({super.key, required this.patient, required this.opdId});

  @override
  State<VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends State<VitalsTab> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: PatientVitalsTrend(patientUhid: widget.patient.id, currentOpdId: widget.opdId),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text(sub, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildVitalInput(String label, TextEditingController controller, String hint, String unit, IconData icon) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              suffixText: unit,
              prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
              suffixStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
              filled: true,
              fillColor: const Color(0xFFF8FAFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}
