import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart'; // Patient model + AppColors
import '../supabase_handler.dart';
import '../services/server_data_service.dart';

class EditPatientDialog extends StatefulWidget {
  final Patient patient;

  const EditPatientDialog({
    super.key,
    required this.patient,
  });

  @override
  State<EditPatientDialog> createState() => _EditPatientDialogState();
}

class _EditPatientDialogState extends State<EditPatientDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late String _selectedGender;
  late String _selectedAgeUnit;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.patient.name);
    
    // Extract age number and unit
    final rawDetail = widget.patient.fullData['patient_detail'] ?? {};
    final ageVal = rawDetail['age']?.toString() ?? _extractAgeNumber(widget.patient.ageInfo);
    final ageUnitVal = rawDetail['age_unit']?.toString() ?? _extractAgeUnit(widget.patient.ageInfo);

    _ageController = TextEditingController(text: ageVal);
    _selectedAgeUnit = _normalizeAgeUnit(ageUnitVal);
    _selectedGender = _normalizeGender(widget.patient.gender);
  }

  String _extractAgeNumber(String ageInfo) {
    final match = RegExp(r'\d+').firstMatch(ageInfo);
    return match != null ? match.group(0)! : '0';
  }

  String _extractAgeUnit(String ageInfo) {
    final lower = ageInfo.toLowerCase();
    if (lower.contains('m')) return 'M';
    if (lower.contains('d')) return 'D';
    return 'Y';
  }

  String _normalizeAgeUnit(String unit) {
    final u = unit.trim().toUpperCase();
    if (u.startsWith('M')) return 'M';
    if (u.startsWith('D')) return 'D';
    return 'Y';
  }

  String _normalizeGender(String gender) {
    final g = gender.trim().toLowerCase();
    if (g.startsWith('m')) return 'Male';
    if (g.startsWith('f')) return 'Female';
    return 'Other';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final newName = _nameController.text.trim().toUpperCase();
    final newAge = int.tryParse(_ageController.text.trim()) ?? 0;
    final newGender = _selectedGender.toLowerCase();
    final newAgeUnit = _selectedAgeUnit;

    setState(() => _isSaving = true);

    try {
      if (widget.patient.id.isNotEmpty) {
        await SupabaseHandler.client
            .from('patient_detail')
            .update({
              'name': newName,
              'age': newAge,
              'age_unit': newAgeUnit,
              'gender': newGender,
            })
            .eq('uhid', widget.patient.id);
      }

      // Calculate new initials
      String newInitials = "P";
      List<String> parts = newName.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (parts.length > 1) {
        newInitials = "${parts[0][0]}${parts[1][0]}".toUpperCase();
      } else if (parts.isNotEmpty) {
        newInitials = parts[0][0].toUpperCase();
      }

      // Update fullData copy
      final updatedFullData = Map<String, dynamic>.from(widget.patient.fullData);
      final patientDetail = Map<String, dynamic>.from(updatedFullData['patient_detail'] ?? {});
      patientDetail['name'] = newName;
      patientDetail['age'] = newAge;
      patientDetail['age_unit'] = newAgeUnit;
      patientDetail['gender'] = newGender;
      updatedFullData['patient_detail'] = patientDetail;

      final updatedPatient = widget.patient.copyWith(
        name: newName,
        ageInfo: "$newAge $newAgeUnit",
        gender: _selectedGender,
        initials: newInitials,
        fullData: updatedFullData,
      );

      // Trigger global refresh
      ServerDataService.refreshNotifier.value++;

      if (mounted) {
        Navigator.pop(context, updatedPatient);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update patient: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Landscape Keyboard Safety:
    // Fits neatly even on landscape tablet when the software keyboard covers 50% of the screen.
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ───────────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accentLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Edit Patient Details",
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (widget.patient.id.isNotEmpty)
                                Text(
                                  "UHID: ${widget.patient.id}",
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: AppColors.textSecondary,
                          splashRadius: 18,
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.border),

                    // ── Patient Name Field ───────────────────────────────
                    Text(
                      "PATIENT NAME *",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: "Enter full name",
                        hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.primary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return "Patient name is required";
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // ── Age & Unit + Gender in Responsive Row ────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Age & Unit
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "AGE & UNIT *",
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  // Age Number Input
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _ageController,
                                      keyboardType: TextInputType.number,
                                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: "Age",
                                        hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
                                        prefixIcon: const Icon(Icons.cake_outlined, size: 18, color: AppColors.primary),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: AppColors.border),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: AppColors.border),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return "Required";
                                        if (int.tryParse(v.trim()) == null) return "Invalid";
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Age Unit (Y / M / D)
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      height: 44,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedAgeUnit,
                                          isExpanded: true,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary,
                                          ),
                                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSecondary),
                                          items: const [
                                            DropdownMenuItem(value: 'Y', child: Text("Years (Y)")),
                                            DropdownMenuItem(value: 'M', child: Text("Months (M)")),
                                            DropdownMenuItem(value: 'D', child: Text("Days (D)")),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) setState(() => _selectedAgeUnit = val);
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Gender Selection
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "GENDER *",
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _genderChip("Male", Icons.male_rounded),
                                  const SizedBox(width: 6),
                                  _genderChip("Female", Icons.female_rounded),
                                  const SizedBox(width: 6),
                                  _genderChip("Other", Icons.transgender_rounded),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // ── Actions ──────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text("Cancel", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isSaving ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_rounded, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Save Changes",
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderChip(String label, IconData icon) {
    final isSelected = _selectedGender == label;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedGender = label),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label == "Other" ? "Oth" : label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
