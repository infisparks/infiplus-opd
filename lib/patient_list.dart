import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'main.dart'; // Patient class + AppColors
import 'supabase_handler.dart';


// ─────────────────────────────────────────────────────────────────
//  FILTER ENUM
// ─────────────────────────────────────────────────────────────────
enum DateFilter { today, yesterday, all }

// ─────────────────────────────────────────────────────────────────
//  PATIENT LIST PANEL
// ─────────────────────────────────────────────────────────────────
class LeftPanelPatientList extends StatefulWidget {
  final List<Patient> patients;
  final int selectedIndex;
  final Function(int) onPatientSelected;
  final Future<void> Function({String? searchQuery}) onRefresh;
  final VoidCallback onNewRegistration;
  final Function(Patient) onEditPatient;
  final Function(Patient) onAddPayment;

  const LeftPanelPatientList({
    super.key,
    required this.patients,
    required this.selectedIndex,
    required this.onPatientSelected,
    required this.onRefresh,
    required this.onNewRegistration,
    required this.onEditPatient,
    required this.onAddPayment,
  });

  @override
  State<LeftPanelPatientList> createState() => _LeftPanelPatientListState();
}

class _LeftPanelPatientListState extends State<LeftPanelPatientList>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  List<Patient> _visiblePatients    = [];
  DateFilter    _currentFilter      = DateFilter.today;
  String        _selectedHospital   = "All Hospitals";
  bool          _hasSearchedAllMode = false;
  bool          _isRefreshing       = false;

  @override
  void initState() {
    super.initState();
    _applyFilters();
  }

  @override
  void didUpdateWidget(covariant LeftPanelPatientList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patients != widget.patients) {
      debugPrint("Patient List Data Changed - Refreshing UI");
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filter Logic ───────────────────────────────────────────────
  void _applyFilters() {
    final query   = _searchController.text.trim().toLowerCase();
    final now     = DateTime.now();
    final today   = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    List<Patient> result = [];

    if (_currentFilter == DateFilter.all) {
      // Lowered limit to 2 characters to be more flexible
      result = query.length < 2
          ? []
          : widget.patients.where((p) {
              final matchesHospital = _selectedHospital == "All Hospitals" || p.hospitalName == _selectedHospital;
              if (!matchesHospital) return false;
              
              final matchesName  = p.name.toLowerCase().contains(query);
              final matchesPhone = p.phone.contains(query);
              final matchesId    = p.id.toLowerCase().contains(query);
              
              return matchesName || matchesPhone || matchesId;
            }).toList();
    } else {
      result = widget.patients.where((p) {
        final matchesHospital = _selectedHospital == "All Hospitals" || p.hospitalName == _selectedHospital;
        if (!matchesHospital) return false;

        final pDay = DateTime(p.visitDate.year, p.visitDate.month, p.visitDate.day);
        final dateOk = _currentFilter == DateFilter.today
            ? pDay.isAtSameMomentAs(today)
            : pDay.isAtSameMomentAs(yesterday);
        if (!dateOk) return false;
        if (query.isEmpty) return true;
        return p.name.toLowerCase().contains(query) ||
               p.phone.contains(query) ||
               p.id.toLowerCase().contains(query);
      }).toList();
    }

    int getSortWeight(Patient p) {
      if (p.isFinalized) return 2;
      if (p.visitStatus.toLowerCase() == 'checked out') return 1;
      return 0; // Waiting
    }

    result.sort((a, b) {
      int wA = getSortWeight(a);
      int wB = getSortWeight(b);
      if (wA != wB) return wA.compareTo(wB);
      return b.visitDate.compareTo(a.visitDate);
    });

    setState(() => _visiblePatients = result);
  }

  void _onTabChanged(DateFilter newFilter) {
    setState(() {
      _currentFilter      = newFilter;
      _hasSearchedAllMode = false;
      _visiblePatients    = [];
    });
    _searchController.clear();
    if (newFilter != DateFilter.all) _applyFilters();
  }

  void _onSearchTriggered() async {
    final query = _searchController.text.trim();
    if (_currentFilter == DateFilter.all && query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter at least 2 characters to search.")),
      );
      return;
    }
    
    if (_currentFilter == DateFilter.all) {
      setState(() => _isRefreshing = true);
      await widget.onRefresh(searchQuery: query);
      if (mounted) setState(() => _isRefreshing = false);
    }
    
    setState(() => _hasSearchedAllMode = true);
    _applyFilters();
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // ── Hospital Filter ──────────────────────────────────
          _buildHospitalFilter(),

          // ── Filter Tabs ──────────────────────────────────────
          _buildFilterTabs(),

          // ── Search ───────────────────────────────────────────
          _buildSearchBar(),

          // ── List ─────────────────────────────────────────────
          Expanded(
            child: Container(
              color: const Color(0xFFF8FAFF),
              child: _buildListContent(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hospital Filter ──────────────────────────────────────────
  Widget _buildHospitalFilter() {
    final hospitals = widget.patients.map((p) => p.hospitalName).where((h) => h.isNotEmpty).toSet().toList();
    hospitals.sort();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_hospital_rounded, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedHospital,
                isExpanded: true, // Takes full width for better tap target
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                items: [
                  const DropdownMenuItem(value: "All Hospitals", child: Text("All Hospitals")),
                  ...hospitals.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedHospital = val);
                    _applyFilters();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter Tabs ───────────────────────────────────────────────
  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _tabItem("Today",     DateFilter.today),
                  _tabItem("Yesterday", DateFilter.yesterday),
                  _tabItem("All",       DateFilter.all),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: "Refresh Queue",
            child: InkWell(
              onTap: _isRefreshing ? null : () async {
                setState(() => _isRefreshing = true);
                final q = _currentFilter == DateFilter.all ? _searchController.text.trim() : null;
                await widget.onRefresh(searchQuery: q);
                if (mounted) setState(() => _isRefreshing = false);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _isRefreshing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: "New Registration",
            child: InkWell(
              onTap: widget.onNewRegistration,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _tabItem(String label, DateFilter filter) {
    final isSelected = _currentFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ── Search Bar ────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: _searchController,
          onSubmitted: (_) => _onSearchTriggered(),
          onChanged:   (v) { if (_currentFilter != DateFilter.all) _applyFilters(); },
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText:      _currentFilter == DateFilter.all ? "Search name / ID / phone (min 2 chars)…" : "Filter list…",
            hintStyle:     GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted),
            prefixIcon:    const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            border:        InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            isDense: true,
            suffixIcon: SizedBox(
              width: 82,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_visiblePatients.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "${_visiblePatients.length}",
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _onSearchTriggered,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── List Content ──────────────────────────────────────────────
  Widget _buildListContent() {
    if (_currentFilter == DateFilter.all && !_hasSearchedAllMode) {
      return _emptyState(Icons.manage_search_outlined, "Search All Records",
          "Enter name or UHID to find\nolder patient files.");
    }
    if (_visiblePatients.isEmpty) {
      return _emptyState(Icons.filter_list_off_outlined, "No Patients Found",
          "Try adjusting the filter\nor your search query.");
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: _visiblePatients.length,
        itemBuilder: (context, index) {
          final patient       = _visiblePatients[index];
          final originalIndex = widget.patients.indexOf(patient);
          final isSelected    = originalIndex == widget.selectedIndex;

          return _patientCard(patient, originalIndex, isSelected);
        },
      ),
    );
  }

  Future<void> _toggleStatus(Patient p, {required bool finalize}) async {
    try {
      final Map<String, dynamic> updateData = finalize ? {
        'is_finalized': true,
        'visit_status': 'Finalized',
        'finalized_at': DateTime.now().toIso8601String(),
      } : {
        'is_finalized': false,
        'visit_status': 'Checked Out',
      };

      await SupabaseHandler.client.from('opd_registration').update(updateData).eq('id', p.opdRegistrationId);

      // Refresh list to update state across everything cleanly
      await widget.onRefresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(finalize ? "Patient Finalized Successfully!" : "Patient Checked Out Successfully!"),
            backgroundColor: finalize ? AppColors.success : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error updating status: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _softDeletePatient(Patient p) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Registration", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Are you sure you want to delete ${p.name}'s registration? This action can be undone by admin.",
          style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseHandler.client.from('opd_registration').update({
        'is_Deleted': true,
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': SupabaseHandler.client.auth.currentUser?.email ?? 'System',
      }).eq('id', p.opdRegistrationId);

      await widget.onRefresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registration deleted successfully"), backgroundColor: AppColors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error deleting: $e"), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _showActionSheet(Patient p) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.name, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded, color: AppColors.primary),
              title: const Text("Edit Registration Details"),
              onTap: () {
                Navigator.pop(context);
                widget.onEditPatient(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined, color: AppColors.primary),
              title: const Text("Add Payment / Discount"),
              onTap: () {
                Navigator.pop(context);
                widget.onAddPayment(p);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: const Text("Delete Registration"),
              onTap: () async {
                Navigator.pop(context);
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Delete Registration"),
                    content: const Text("Are you sure you want to delete this registration? This action cannot be undone."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true), 
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  _softDeletePatient(p);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientCard(Patient patient, int originalIndex, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Dismissible(
          key: Key("patient_${patient.opdRegistrationId}_${patient.visitDate.toIso8601String()}"),
          direction: DismissDirection.horizontal,
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await _toggleStatus(patient, finalize: true);
            } else if (direction == DismissDirection.endToStart) {
              await _toggleStatus(patient, finalize: false);
            }
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            color: AppColors.success,
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Text("FINALIZE", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
              ],
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.orange,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text("CHECK OUT", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                const SizedBox(width: 8),
                const Icon(Icons.outbound_rounded, color: Colors.white, size: 24),
              ],
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color:        isSelected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primaryDark : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: isSelected ? 12 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color:        Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap:        () => widget.onPatientSelected(originalIndex),
                onLongPress:  () => _showActionSheet(patient),
                borderRadius: BorderRadius.circular(14),
                hoverColor:   AppColors.primary.withValues(alpha: 0.04),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // ── Avatar ──────────────────────────────────
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.2)
                              : AppColors.accentLight,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          patient.initials,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isSelected ? Colors.white : AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // ── Info ─────────────────────────────────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _miniTag(patient.gender, isSelected),
                                const SizedBox(width: 5),
                                _miniTag(patient.ageInfo, isSelected),
                                const SizedBox(width: 6),
                                if (patient.isFinalized)
                                  _statusBadge("FINAL", AppColors.success, isSelected)
                                else if (patient.visitStatus.toLowerCase() == 'checked out')
                                  _statusBadge("CH-OUT", Colors.orange, isSelected)
                                else
                                  _statusBadge("WAIT", AppColors.danger, isSelected),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ── Date/Time ────────────────────────────────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            DateFormat('MMM d').format(patient.visitDate),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('hh:mm a').format(patient.visitDate),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: isSelected ? Colors.white70 : AppColors.textMuted,
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
      ),
    );
  }

  Widget _miniTag(String text, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withOpacity(0.15)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _statusBadge(String label, Color color, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.25) : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isSelected ? Colors.white38 : color.withOpacity(0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: isSelected ? Colors.white : color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String sub) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(title,
            style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(sub,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}