import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:infiplus_opd/patient_vitals_trend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'main.dart';
import 'package:infiplus_opd/services/server_data_service.dart';
import 'manage_patient/new_consult_page.dart';
import 'package:intl/intl.dart';
import 'manage_patient/medical_certificate_page.dart';
import 'package:infiplus_opd/manage_patient/canvas_management_page.dart';

// ─────────────────────────────────────────────────────────────────
//  PATIENT DETAILS PANEL
// ─────────────────────────────────────────────────────────────────
class RightPanelPatientDetails extends StatefulWidget {
  final Patient patient;
  const RightPanelPatientDetails({super.key, required this.patient});

  @override
  State<RightPanelPatientDetails> createState() => _RightPanelPatientDetailsState();
}

class _RightPanelPatientDetailsState extends State<RightPanelPatientDetails> {
  bool  _isLoading      = true;
  List<Map<String, dynamic>> _allVisits = [];
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fetchAllPatientVisits();

    // Listen for external syncs (e.g. from NewConsultPage finalization)
    ServerDataService.refreshNotifier.addListener(_safeRefresh);
  }

  void _safeRefresh() {
    if (!mounted) return;
    // Prevent "setState() called during build" errors by moving to next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchAllPatientVisits();
    });
  }

  @override
  void didUpdateWidget(covariant RightPanelPatientDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patient.id != widget.patient.id) _fetchAllPatientVisits();
  }

  @override
  void dispose() {
    ServerDataService.refreshNotifier.removeListener(_safeRefresh);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllPatientVisits() async {
    setState(() => _isLoading = true);
    try {
      // Fetch data including structured sub-tables
      final response = await Supabase.instance.client
          .from('opd_registration')
          .select('''
            *,
            opd_reg_symptoms(*),
            opd_reg_diagnosis(*),
            opd_reg_rx(*),
            opd_reg_reports(*)
          ''')
          .eq('uhid', widget.patient.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allVisits    = response is List ? List<Map<String, dynamic>>.from(response) : [];
          _currentIndex = 0;
        });
      }
    } catch (e) {
      debugPrint("Error fetching patient history: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> _extractNames(dynamic jsonList) {
    if (jsonList == null || jsonList is! List) return [];
    return jsonList.map((e) {
      if (e is Map)    return e['name']?.toString() ?? '';
      if (e is String) return e;
      return e.toString();
    }).where((s) => s.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> currentVisit = (_isLoading || _allVisits.isEmpty)
        ? <String, dynamic>{}
        : _allVisits[_currentIndex];

    if (!_isLoading && _allVisits.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        if (!_isLoading) _buildHeader(currentVisit),
        _buildActionBar(context),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3))
              : Container(
                  color: AppColors.bgBody,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── LEFT: Clinical Summary ──────────────
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildClinicalDashboard(currentVisit),
                              const SizedBox(height: 20),
                              _buildVitalsTile(),
                              const SizedBox(height: 50),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      // ── RIGHT: Document Viewer ──────────────
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            _buildDocNavControls(),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color:        const Color(0xFFCBD5E1),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 6))],
                                ),
                                padding: const EdgeInsets.all(16),
                                child: PageView.builder(
                                  controller:   _pageController,
                                  physics:      const BouncingScrollPhysics(),
                                  itemCount:    _allVisits.length,
                                  onPageChanged: (i) => setState(() => _currentIndex = i),
                                  itemBuilder:  (ctx, i) => Center(
                                    child: SingleChildScrollView(
                                      child: _buildPrescriptionPaper(_allVisits[i]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _buildHeader(Map<String, dynamic> visit) {
    String dateStr   = "No Records";
    String visitType = "New Patient";
    if (visit.isNotEmpty && visit['created_at'] != null) {
      final date = DateTime.parse(visit['created_at']).toLocal();
      dateStr   = DateFormat('MMM d, yyyy').format(date);
      visitType = visit['visit_category'] ?? "Follow Up";
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            alignment: Alignment.center,
            child: Text(
              widget.patient.initials,
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
            ),
          ),
          const SizedBox(width: 18),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patient.name,
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _pill(widget.patient.gender, AppColors.primary),
                    const SizedBox(width: 8),
                    _pill(widget.patient.ageInfo, AppColors.accent),
                    const SizedBox(width: 12),
                    Container(height: 14, width: 1, color: AppColors.border),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        Icon(Icons.fingerprint_rounded, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          widget.patient.id,
                          style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary, fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Visit card
          if (visit.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color:        AppColors.bgBody,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("LAST VISIT",
                    style: GoogleFonts.poppins(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: AppColors.textMuted, letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(dateStr,
                    style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _visitTypeBadge(visitType),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12, fontWeight: FontWeight.w600, color: color,
        ),
      ),
    );
  }

  Widget _visitTypeBadge(String type) {
    final isNew = type.toLowerCase().contains('new');
    final color = isNew ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type,
        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ── Action Bar ────────────────────────────────────────────────
  Widget _buildActionBar(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Row(
        children: [
          _primaryBtn(
            context,
            label:  "Add Prescription",
            icon:   Icons.add_rounded,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewConsultPage(
                    patient: widget.patient,
                    opdId:   widget.patient.opdRegistrationId,
                  ),
                ),
              ).then((_) => _fetchAllPatientVisits());
            },
          ),
          const SizedBox(width: 12),
          _outlineBtn("Medical Certificate", Icons.description_outlined, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MedicalCertificatePage(patient: widget.patient),
              ),
            );
          }),
          const SizedBox(width: 12),
          _outlineBtn("Canvas", Icons.brush_outlined, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CanvasManagementPage(
                  uhid: widget.patient.id,
                  opdId: widget.patient.opdRegistrationId,
                  patientName: widget.patient.name,
                ),
              ),
            );
          }),
          const Spacer(),
          _refreshBtn(),
        ],
      ),
    );
  }

  Widget _refreshBtn() {
    return Tooltip(
      message: "Refresh Records",
      child: InkWell(
        onTap: _fetchAllPatientVisits,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
        ),
      ),
    );
  }

  Widget _primaryBtn(BuildContext context, {required String label, required IconData icon, required VoidCallback onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon:  Icon(icon, size: 18),
      label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding:         const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        shadowColor:     AppColors.primary.withOpacity(0.35),
        elevation:       4,
      ),
    );
  }

  Widget _outlineBtn(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon:  Icon(icon, size: 17),
      label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side:            const BorderSide(color: AppColors.border),
        padding:         const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Clinical Dashboard ────────────────────────────────────────
  Widget _buildClinicalDashboard(Map<String, dynamic> visit) {
    if (visit.isEmpty) return const SizedBox();

    final symptoms      = _extractNames(visit['opd_reg_symptoms']);
    final investigations = (visit['opd_reg_reports'] as List?)
        ?.where((r) => r['report_type'] == 'investigation')
        .map((r) => r['item_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList() ?? [];
    
    Map<String, String> findings = {};
    if (visit['clinical_data']?['checkup_data'] != null) {
      (visit['clinical_data']['checkup_data'] as Map).forEach((k, v) {
        if (v.toString().isNotEmpty) findings[k.toString()] = v.toString();
      });
    }

    return Container(
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.dashboard_customize_rounded, color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Text("Clinical Summary",
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: AppColors.border, height: 1),
          ),

          _clinicalSection("CHIEF COMPLAINTS",  symptoms,       const Color(0xFFEF4444), Icons.sick_outlined),
          if (symptoms.isNotEmpty)      const SizedBox(height: 20),
          _clinicalSection("INVESTIGATIONS",     investigations, const Color(0xFFF59E0B), Icons.science_outlined),
          if (investigations.isNotEmpty) const SizedBox(height: 20),
          
          if (visit['clinical_notes'] != null && visit['clinical_notes'].toString().isNotEmpty) ...[
            _sectionTitle("CLINICAL NOTES", const Color(0xFF6366F1)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Text(visit['clinical_notes'].toString(), 
                 style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF4C1D95), height: 1.5)),
            ),
            const SizedBox(height: 20),
          ],

          if (findings.isNotEmpty) ...[
            _sectionTitle("EXAMINATION FINDINGS", const Color(0xFF0D9488)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Column(
                children: findings.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 15, color: const Color(0xFF0D9488)),
                      const SizedBox(width: 8),
                      Text("${e.key}:  ", style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF134E4A))),
                      Expanded(child: Text(e.value, style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF134E4A)))),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _clinicalSection(String title, List<String> items, Color accent, IconData icon) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title, accent),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: items.map((item) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:        Colors.white,
              border:       Border.all(color: accent.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              boxShadow:    [BoxShadow(color: accent.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: accent),
                const SizedBox(width: 6),
                Text(item,
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Row(
      children: [
        Container(width: 3, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
          style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.1)),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: color.withOpacity(0.15), thickness: 1)),
      ],
    );
  }

  // ── Vitals Tile ───────────────────────────────────────────────
  Widget _buildVitalsTile() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow:    [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: PatientVitalsTrend(patientUhid: widget.patient.id),
    );
  }

  // ── Doc Nav Controls ──────────────────────────────────────────
  Widget _buildDocNavControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow:    [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon:  const Icon(Icons.arrow_back_ios_rounded, size: 15),
            color: _currentIndex < _allVisits.length - 1 ? AppColors.textPrimary : AppColors.border,
            onPressed: _currentIndex < _allVisits.length - 1
                ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              "Record ${_allVisits.length - _currentIndex} of ${_allVisits.length}",
              style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w700,
                fontFeatures: [const FontFeature.tabularFigures()], color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon:  const Icon(Icons.arrow_forward_ios_rounded, size: 15),
            color: _currentIndex > 0 ? AppColors.textPrimary : AppColors.border,
            onPressed: _currentIndex > 0
                ? () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut)
                : null,
          ),
        ],
      ),
    );
  }

  // ── Prescription Paper ────────────────────────────────────────
  Widget _buildPrescriptionPaper(Map<String, dynamic> visitData) {
    final date         = DateTime.parse(visitData['created_at']);
    final opdId        = visitData['id'];
    final symptomsText = _extractNames(visitData['opd_reg_symptoms']).join(", ");
    final diagText     = _extractNames(visitData['opd_reg_diagnosis']).join(", ");
    final invText      = (visitData['opd_reg_reports'] as List?)
        ?.where((r) => r['report_type'] == 'investigation')
        .map((r) => r['item_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join(", ") ?? "";

    List<dynamic> rawRx   = visitData['opd_reg_rx'] ?? [];
    List<Map<String, String>> rxDisplay = rawRx.map<Map<String, String>>((item) {
      String freq = "0-0-0";
      if (item['timing_json'] is Map) {
        var t = item['timing_json'];
        String getVal(dynamic val) {
          if (val == null) return "0";
          if (val is bool) return val ? "1" : "0";
          final s = val.toString().trim();
          return s.isEmpty ? "0" : s;
        }
        String bb = getVal(t['bb']);
        String ab = getVal(t['ab']);
        String bl = getVal(t['bl']);
        String al = getVal(t['al']);
        String bd = getVal(t['bd']);
        String ad = getVal(t['ad']);
        
        String m = bb != "0" ? bb : ab;
        String a = bl != "0" ? bl : al;
        String n = bd != "0" ? bd : ad;
        freq = "$m-$a-$n";
      }
      return {
        "name": "${item['medicine_name']} ${item['dosage'] ?? ''}",
        "freq": freq,
        "dur":  item['duration'] ?? '',
      };
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doc header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("OPD ENCOUNTER RECORD",
                      style: GoogleFonts.poppins(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.grey.shade400)),
                    const SizedBox(height: 6),
                    Text(widget.patient.name,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 20, color: Colors.black87)),
                    Text(DateFormat('dd MMMM yyyy').format(date),
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              QrImageView(data: opdId.toString(), size: 56.0),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(thickness: 1.5, color: Colors.grey.shade100),
          ),

          if (symptomsText.isNotEmpty) _paperRow("Complaints",   symptomsText),
          if (diagText.isNotEmpty) _paperRow("Diagnosis", diagText),
          if (visitData['clinical_notes'] != null && visitData['clinical_notes'].toString().isNotEmpty)
            _paperRow("Clinical Notes", visitData['clinical_notes']),
          if (invText.isNotEmpty)  _paperRow("Investigations", invText),

          const SizedBox(height: 16),
          Text("PRESCRIPTION",
            style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.primary)),
          const SizedBox(height: 8),

          if (rxDisplay.isNotEmpty)
            Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade100, width: 1),
                bottom:           BorderSide(color: Colors.grey.shade100, width: 1),
              ),
              columnWidths: const {
                0: FixedColumnWidth(22),
                1: FlexColumnWidth(),
                2: FixedColumnWidth(70),
                3: FixedColumnWidth(55),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade50),
                  children: ["#", "Medicine", "Freq", "Days"].map((h) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      child: Text(h, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 9, color: AppColors.textSecondary)),
                    )
                  ).toList(),
                ),
                ...rxDisplay.asMap().entries.map((e) => TableRow(
                  children: [
                    _paperCell("${e.key + 1}."),
                    _paperCell(e.value['name']!, bold: true),
                    _paperCell(e.value['freq']!),
                    _paperCell(e.value['dur']!),
                  ],
                )),
              ],
            )
          else
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
              child: Text("No medications prescribed during this visit.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
            ),

          const SizedBox(height: 36),
          Align(
            alignment: Alignment.bottomRight,
            child: Column(
              children: [
                Container(height: 1, width: 110, color: Colors.black26),
                const SizedBox(height: 4),
                Text("Authorized Signature",
                  style: GoogleFonts.poppins(fontSize: 9, color: Colors.black45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperRow(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
            style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Text(content, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, height: 1.45, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _paperCell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      child: Text(text,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  // ── Medical Certificate Dialog ──────────────────────────────
  void _showMedicalCertificateDialog() {
    String selectedTemplate = "Sick Leave Certificate";
    TextEditingController certificateController = TextEditingController();
    
    void updateContent(String templateName) {
      String content = "";
      final now = DateTime.now();
      final dateStr = DateFormat('dd MMM yyyy').format(now);
      
      if (templateName == "Sick Leave Certificate") {
        content = "To whom it may concern,\n\nThis is to certify that ${widget.patient.name}, aged ${widget.patient.ageInfo}, was under my clinical care from $dateStr to ${DateFormat('dd MMM yyyy').format(now.add(const Duration(days: 3)))}.\n\nHe/She is suffering from acute illness and is advised rest for 3 days. He/She is fit to resume duties on ${DateFormat('dd MMM yyyy').format(now.add(const Duration(days: 4)))}.";
      } else if (templateName == "Fitness Certificate") {
        content = "To whom it may concern,\n\nI have examined ${widget.patient.name} today ($dateStr) and found him/her to be in good health and physically fit. There are no signs of any communicable diseases or physical disabilities that would prevent him/her from performing routine activities.";
      } else {
        content = "This is to certify that ${widget.patient.name} has undergone a medical procedure today ($dateStr). Due to the nature of the procedure, he/she is advised to avoid strenuous activity and rest for the next 2 days.";
      }
      certificateController.text = content;
    }

    updateContent(selectedTemplate);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Text("Medical Certificate", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("SELECT TEMPLATE", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                const SizedBox(height: 8),
                Row(
                  children: ["Sick Leave Certificate", "Fitness Certificate", "Procedure Leave"].map((t) {
                    bool isSel = selectedTemplate == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() => selectedTemplate = t);
                            updateContent(t);
                          }
                        },
                        selectedColor: AppColors.primary.withOpacity(0.2),
                        labelStyle: TextStyle(color: isSel ? AppColors.primary : Colors.black87),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text("EDIT CERTIFICATE CONTENT", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: certificateController,
                    maxLines: 10,
                    style: GoogleFonts.poppins(fontSize: 14, height: 1.6, color: Colors.black87),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await Supabase.instance.client.from('opd_medical_certificates').insert({
                    'patient_id': widget.patient.id,
                    'certificate_type': selectedTemplate,
                    'final_content': certificateController.text,
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Certificate Saved & Issued Successfully!")));
                } catch (e) {
                  debugPrint("Error saving certificate: $e");
                }
              },
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text("ISSUE & PRINT"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
            child: const Icon(Icons.medical_information_outlined, size: 60, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          Text("No Visit Records",
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text("Start a consultation to create the first record.",
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewConsultPage(
                    patient: widget.patient,
                    opdId:   widget.patient.opdRegistrationId,
                  ),
                ),
              ).then((_) => _fetchAllPatientVisits());
            },
            icon:  const Icon(Icons.add_rounded, size: 18),
            label: Text("Start Consultation", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}