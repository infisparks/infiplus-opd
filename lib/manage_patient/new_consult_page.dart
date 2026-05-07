import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart'; // Patient Model + AppColors
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vitals_tab.dart';
import 'symptoms_tab.dart';
import 'treatment_tab.dart';
import 'instructions_tab.dart';
import 'preview_tab.dart';
import 'patient_documents_page.dart';
import 'diagnosis_tab.dart';
import 'blood_test_tab.dart';
import 'history_tab.dart';
import 'notes_dialog.dart';
import '../services/server_data_service.dart';

class NewConsultPage extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const NewConsultPage({
    super.key,
    required this.patient,
    required this.opdId,
  });

  @override
  State<NewConsultPage> createState() => _NewConsultPageState();
}

class _NewConsultPageState extends State<NewConsultPage> {
  // Tab order: 0 History | 1 Test | 2 Vitals | 3 Symptoms | 4 Diagnosis | 5 Rx | 6 Report | 7 Print
  int _currentTabIndex = 5; // Default to Rx
  late PageController _pageController;
  final GlobalKey<PreviewTabState> _previewKey = GlobalKey<PreviewTabState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTabIndex);
    
    // FETCH FRESH DATA FROM SERVER (Wait for frame to avoid build loops)
    WidgetsBinding.instance.addPostFrameCallback((_) {
       ServerDataService.refreshNotifier.value++;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    // DOUBLE CLICK PRINT TAB LOGIC:
    // If user is already on Print Tab (7) and clicks it again, finalize and share.
    if (index == 7 && _currentTabIndex == 7) {
      _previewKey.currentState?.submitDataToSupabase();
      return;
    }

    setState(() => _currentTabIndex = index);
    _pageController.jumpToPage(index);

    // If switching to Print Tab, trigger a fresh fetch after a brief delay
    // to allow any pending debounced auto-saves from previous tabs to complete.
    if (index == 7) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) ServerDataService.refreshNotifier.value++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBody,

      // ── AppBar ────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation:       0,
        toolbarHeight: 60,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color:     AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.patient.name, 
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text("${widget.patient.gender} · ${widget.patient.ageInfo}", 
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(width: 20),
            _topNavItem(Icons.auto_stories_rounded, "HISTORY", 0),
            const SizedBox(width: 8),
            _topNavItem(Icons.biotech_rounded,      "TEST",    1),
            const SizedBox(width: 12),
            if (widget.patient.isFinalized)
              _statusPill("FINAL", AppColors.success)
            else if (widget.patient.visitStatus.toLowerCase() == 'checked out')
              _statusPill("CH-OUT", Colors.orange)
            else
              _statusPill("WAIT", AppColors.danger),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => NotesDialog(opdId: widget.opdId),
            ),
            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Clinical Notes",
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PatientDocumentsPage(
                    uhid: widget.patient.id,
                    opdId: widget.opdId,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.folder_shared, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Patient Documents",
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => ServerDataService.refreshNotifier.value++, 
            icon: const Icon(Icons.refresh_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Refresh Data",
          ),
          const SizedBox(width: 16),
        ],
      ),

      // ── Body ──────────────────────────────────────────────────
      body: PageView(
        controller: _pageController,
        physics:    const NeverScrollableScrollPhysics(),
        children: [
          HistoryTab(patient: widget.patient, currentOpdId: widget.opdId),   // 0
          BloodTestTab(patient: widget.patient, opdId: widget.opdId),       // 1
          VitalsTab(patient: widget.patient, opdId: widget.opdId),          // 2
          SymptomsTab(patient: widget.patient, opdId: widget.opdId),        // 3
          DiagnosisTab(patient: widget.patient, opdId: widget.opdId),       // 4
          TreatmentTab(patient: widget.patient, opdId: widget.opdId),       // 5
          InstructionsTab(patient: widget.patient, opdId: widget.opdId),    // 6
          PreviewTab(patient: widget.patient, opdId: widget.opdId, key: _previewKey),         // 7
        ],
      ),

      // ── Bottom Dock ───────────────────────────────────────────────
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0 
          ? null 
          : _buildBottomDock(),
    );
  }

  Widget _topNavItem(IconData icon, String label, int index) {
    bool isSelected = _currentTabIndex == index;
    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Container(
        height: 85,
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          
        ),
        child: Row(
          children: [
            // Close button
            _dockClose(),

            // Patient Context
            _dockPatientContext(),

            // Navigation items
            Expanded(child: _dockItem(Icons.monitor_heart_outlined,    "Vitals",     2)),
            Expanded(child: _dockItem(Icons.favorite_rounded,          "Symptoms",   3)),
            Expanded(child: _dockItem(Icons.assignment_ind_outlined,   "Diagnosis",  4)),
            Expanded(child: _dockItem(Icons.medication_outlined,       "Rx",         5)),
            Expanded(child: _dockItem(Icons.assignment_outlined,       "Report",     6)),
            Expanded(child: _dockItem(Icons.print_outlined,            "Print",      7)),
          ],
        ),
      ),
    );
  }

  Widget _dockClose() {
    return InkWell(
      onTap:         () => Navigator.pop(context),
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
      child: Container(
        width:  68, height: 85,
        decoration: BoxDecoration(
          color:        AppColors.danger.withOpacity(0.07),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.power_settings_new_rounded, color: AppColors.danger, size: 24),
            const SizedBox(height: 4),
            Text("Exit",
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
          ],
        ),
      ),
    );
  }

  Widget _dockPatientContext() {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.border))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.patient.id, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
          Text("${widget.patient.ageInfo} · ${widget.patient.gender}", style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _dockItem(IconData icon, String label, int index) {
    bool isSelected = _currentTabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        () => _onTabTapped(index),
        borderRadius: BorderRadius.circular(15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size:  26, color: isSelected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? AppColors.primary : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
    );
  }
}