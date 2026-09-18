import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart'; // AppColors, Patient
import '../supabase_handler.dart';
import '../services/analytics_service.dart';
import '../services/master_data_service.dart';
import 'analytics_pdf_generator.dart';

class ClinicalAnalyticsPage extends StatefulWidget {
  final String? initialHospital;
  final Function(Patient)? onOpenPatient;

  const ClinicalAnalyticsPage({
    super.key,
    this.initialHospital,
    this.onOpenPatient,
  });

  @override
  State<ClinicalAnalyticsPage> createState() => _ClinicalAnalyticsPageState();
}

class _ClinicalAnalyticsPageState extends State<ClinicalAnalyticsPage> with SingleTickerProviderStateMixin {
  late ClinicalAnalyticsFilter _filter;
  ClinicalAnalyticsResult _result = ClinicalAnalyticsResult.empty();
  bool _isLoading = false;
  String _activePreset = "Last 7 Days";
  final TextEditingController _tableSearchController = TextEditingController();
  String _tableSearchQuery = "";
  late TabController _viewTabController;
  List<String> _hospitalList = ["All Hospitals"];

  // Filter drawer / expansion state
  bool _showAdvancedFilters = true;

  @override
  void initState() {
    super.initState();
    _viewTabController = TabController(length: 2, vsync: this);

    if (widget.initialHospital != null && widget.initialHospital!.isNotEmpty && widget.initialHospital != "All Hospitals") {
      _hospitalList = ["All Hospitals", widget.initialHospital!];
    }

    _filter = ClinicalAnalyticsFilter(
      startDate: DateTime.now().subtract(const Duration(days: 7)),
      endDate: DateTime.now(),
      hospital: widget.initialHospital ?? "All Hospitals",
    );

    _loadHospitals();
    _loadAnalytics();
  }

  static const List<String> _defaultHospitals = [
    "Cigma Clinic",
    "Rehmania Hospital",
    "Jeevdani Hospital",
    "Dausup Hospital",
  ];

  Future<void> _loadHospitals() async {
    final Set<String> names = Set.from(_defaultHospitals);

    try {
      // 1. Fetch from opd_datasets if defined
      final datasetRes = await SupabaseHandler.client
          .from('opd_datasets')
          .select('datajson')
          .eq('dataname', 'hospitals')
          .maybeSingle();

      if (datasetRes != null && datasetRes['datajson'] is List) {
        for (var h in datasetRes['datajson']) {
          final str = (h is Map ? (h['name'] ?? '') : h).toString().trim();
          if (str.isNotEmpty) names.add(str);
        }
      }

      // 2. Fetch distinct hospitals from opd_registration
      final response = await SupabaseHandler.client
          .from('opd_registration')
          .select('hospital_name')
          .neq('hospital_name', '');

      for (var row in response) {
        final h = row['hospital_name']?.toString().trim() ?? '';
        if (h.isNotEmpty) names.add(h);
      }
    } catch (e) {
      debugPrint("Error fetching hospital list: $e");
    }

    final sortedList = names.toList()..sort();
    if (mounted) {
      setState(() {
        _hospitalList = ["All Hospitals", ...sortedList];
        if (!_hospitalList.contains(_filter.hospital)) {
          _filter.hospital = "All Hospitals";
        }
      });
    }
  }

  @override
  void dispose() {
    _viewTabController.dispose();
    _tableSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final res = await AnalyticsService.fetchAnalytics(_filter);
      if (mounted) {
        setState(() {
          _result = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading analytics: $e"), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _applyDatePreset(String preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    switch (preset) {
      case "Today":
        start = DateTime(now.year, now.month, now.day);
        break;
      case "Yesterday":
        start = DateTime(now.year, now.month, now.day - 1);
        end = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
        break;
      case "Last 7 Days":
        start = now.subtract(const Duration(days: 7));
        break;
      case "Last 30 Days":
        start = now.subtract(const Duration(days: 30));
        break;
      case "This Month":
        start = DateTime(now.year, now.month, 1);
        break;
      default:
        start = now.subtract(const Duration(days: 7));
    }

    setState(() {
      _activePreset = preset;
      _filter.startDate = start;
      _filter.endDate = end;
    });

    _loadAnalytics();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _filter.startDate, end: _filter.endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _activePreset = "Custom";
        _filter.startDate = picked.start;
        _filter.endDate = picked.end;
      });
      _loadAnalytics();
    }
  }

  void _resetFilters() {
    setState(() {
      _activePreset = "Last 7 Days";
      _filter = ClinicalAnalyticsFilter(
        startDate: DateTime.now().subtract(const Duration(days: 7)),
        endDate: DateTime.now(),
        hospital: widget.initialHospital ?? "All Hospitals",
      );
      _tableSearchController.clear();
      _tableSearchQuery = "";
    });
    _loadAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Filter Controls Header ───────────────────────────
          _buildFilterPanel(isDesktop),

          // ── Tab Bar (Overview / Patient Table) ───────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                TabBar(
                  controller: _viewTabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(
                      child: Row(
                        children: [
                          const Icon(Icons.analytics_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Text("Intelligence & Visualizations"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text("Matched Patients (${_result.records.length})"),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // ── Tab Views ─────────────────────────────────────────
          Expanded(
            child: _isLoading && _result.records.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _viewTabController,
                    children: [
                      _buildOverviewDashboard(isDesktop),
                      _buildPatientRecordsView(isDesktop),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  APP BAR
  // ─────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insights_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Clinical Data Analytics & Intelligence",
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                "Deep query insights across medicines, diagnoses, symptoms & tests",
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Export Excel Button
        Tooltip(
          message: "Export to Excel (CSV)",
          child: ElevatedButton.icon(
            onPressed: _result.records.isEmpty
                ? null
                : () async {
                    try {
                      final fileName = "Clinical_Analytics_${DateFormat('yyyyMMdd').format(_filter.startDate)}";
                      await AnalyticsService.exportCsv(records: _result.records, fileName: fileName);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Excel (CSV) export ready!"), backgroundColor: AppColors.success),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Export error: $e"), backgroundColor: AppColors.danger),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text("Export Excel"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Export PDF Button
        Tooltip(
          message: "Export Analytics PDF Report",
          child: ElevatedButton.icon(
            onPressed: _result.records.isEmpty
                ? null
                : () async {
                    try {
                      await AnalyticsPdfGenerator.exportPdfReport(analytics: _result, filter: _filter);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("PDF Export error: $e"), backgroundColor: AppColors.danger),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text("Export PDF"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  FILTER PANEL
  // ─────────────────────────────────────────────────────────────
  Widget _buildFilterPanel(bool isDesktop) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Date presets, Date range picker, Hospital selector & Action buttons
          Row(
            children: [
              // Date Presets Pills
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _presetChip("Today"),
                      _presetChip("Yesterday"),
                      _presetChip("Last 7 Days"),
                      _presetChip("Last 30 Days"),
                      _presetChip("This Month"),
                      const SizedBox(width: 8),
                      // Custom date button
                      InkWell(
                        onTap: _pickCustomDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _activePreset == "Custom" ? AppColors.accentLight : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _activePreset == "Custom" ? AppColors.primary : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_rounded, size: 14, color: _activePreset == "Custom" ? AppColors.primary : AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                "${DateFormat('dd MMM').format(_filter.startDate)} - ${DateFormat('dd MMM').format(_filter.endDate)}",
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _activePreset == "Custom" ? AppColors.primary : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Hospital Selector
              _buildHospitalDropdown(),

              const SizedBox(width: 8),

              // Toggle Advanced Multi-filters Button
              OutlinedButton.icon(
                onPressed: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
                icon: Icon(
                  _showAdvancedFilters ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                label: Text(
                  _showAdvancedFilters ? "Hide Filters" : "Filter Criteria (${_filterCriteriaCount()})",
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(width: 8),

              // Search / Run Button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadAnalytics,
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text("Search"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),

              if (_filter.hasActiveFilters) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _resetFilters,
                  tooltip: "Reset All Filters",
                  icon: const Icon(Icons.restart_alt_rounded, color: AppColors.danger, size: 20),
                ),
              ],
            ],
          ),

          // Row 2: Expandable Multi-Select Autocomplete Fields (Medicines, Diagnoses, Symptoms, Tests, Advices)
          if (_showAdvancedFilters) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _buildMultiSelectTagRow(isDesktop),
          ],
        ],
      ),
    );
  }

  int _filterCriteriaCount() {
    return _filter.medicines.length +
        _filter.diagnoses.length +
        _filter.symptoms.length +
        _filter.investigations.length +
        _filter.advices.length;
  }

  Widget _presetChip(String label) {
    final isSelected = _activePreset == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => _applyDatePreset(label),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHospitalDropdown() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _hospitalList.contains(_filter.hospital) ? _filter.hospital : "All Hospitals",
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.primary),
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
          items: _hospitalList.map((h) {
            return DropdownMenuItem<String>(
              value: h,
              child: Text(h, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _filter.hospital = val);
              _loadAnalytics();
            }
          },
        ),
      ),
    );
  }

  Widget _buildMultiSelectTagRow(bool isDesktop) {
    final master = MasterDataService();

    final medicineSuggestions = master.medicines.map((m) => m['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    final diagnosisSuggestions = master.diagnoses;
    final symptomSuggestions = master.symptoms;
    final investigationSuggestions = master.investigations;
    final instructionSuggestions = master.instructions;

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTagAutocompleteField("Medicines (Rx)", Icons.medication_outlined, _filter.medicines, medicineSuggestions, "Search medicine…")),
          const SizedBox(width: 10),
          Expanded(child: _buildTagAutocompleteField("Diagnoses", Icons.healing_outlined, _filter.diagnoses, diagnosisSuggestions, "Search diagnosis…")),
          const SizedBox(width: 10),
          Expanded(child: _buildTagAutocompleteField("Symptoms", Icons.sick_outlined, _filter.symptoms, symptomSuggestions, "Search symptom…")),
          const SizedBox(width: 10),
          Expanded(child: _buildTagAutocompleteField("Blood Tests / Inv.", Icons.science_outlined, _filter.investigations, investigationSuggestions, "Search test…")),
          const SizedBox(width: 10),
          Expanded(child: _buildTagAutocompleteField("Advice / Procedure", Icons.checklist_rtl_rounded, _filter.advices, instructionSuggestions, "Search advice…")),
        ],
      );
    }

    return Column(
      children: [
        _buildTagAutocompleteField("Medicines (Rx)", Icons.medication_outlined, _filter.medicines, medicineSuggestions, "Search medicine…"),
        const SizedBox(height: 8),
        _buildTagAutocompleteField("Diagnoses", Icons.healing_outlined, _filter.diagnoses, diagnosisSuggestions, "Search diagnosis…"),
        const SizedBox(height: 8),
        _buildTagAutocompleteField("Symptoms", Icons.sick_outlined, _filter.symptoms, symptomSuggestions, "Search symptom…"),
        const SizedBox(height: 8),
        _buildTagAutocompleteField("Blood Tests / Inv.", Icons.science_outlined, _filter.investigations, investigationSuggestions, "Search test…"),
        const SizedBox(height: 8),
        _buildTagAutocompleteField("Advice / Procedure", Icons.checklist_rtl_rounded, _filter.advices, instructionSuggestions, "Search advice…"),
      ],
    );
  }

  Widget _buildTagAutocompleteField(
    String label,
    IconData icon,
    List<String> selectedItems,
    List<String> suggestions,
    String hint,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              if (selectedItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                  child: Text("${selectedItems.length}", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Autocomplete Input
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              final q = textEditingValue.text.toLowerCase();
              final matches = suggestions.where((s) => s.toLowerCase().contains(q) && !selectedItems.contains(s)).take(8);
              // Also allow custom typing if not in master list
              if (matches.isEmpty && textEditingValue.text.trim().isNotEmpty) {
                return [textEditingValue.text.trim()];
              }
              return matches;
            },
            onSelected: (String selection) {
              if (!selectedItems.contains(selection)) {
                setState(() => selectedItems.add(selection));
                _loadAnalytics();
              }
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: GoogleFonts.poppins(fontSize: 12),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                onSubmitted: (val) {
                  final trimmed = val.trim();
                  if (trimmed.isNotEmpty && !selectedItems.contains(trimmed)) {
                    setState(() => selectedItems.add(trimmed));
                    controller.clear();
                    _loadAnalytics();
                  }
                },
              );
            },
          ),
          // Selected Chips
          if (selectedItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: selectedItems.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          setState(() => selectedItems.remove(item));
                          _loadAnalytics();
                        },
                        child: const Icon(Icons.close_rounded, size: 12, color: AppColors.primary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  OVERVIEW & VISUALIZATIONS DASHBOARD
  // ─────────────────────────────────────────────────────────────
  Widget _buildOverviewDashboard(bool isDesktop) {
    if (_result.records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
              child: const Icon(Icons.query_stats_rounded, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text("No Clinical Records Match Filters", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text("Try adjusting the date range, hospital, or medicine/diagnosis search criteria.",
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Reset Filters"),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI CARDS ROW ────────────────────────────────────
          _buildKpiCardsRow(isDesktop),

          const SizedBox(height: 20),

          // ── CHARTS ROW 1: Daily Trend + Demographics ─────────
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildDailyTrendCard()),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: _buildDemographicsCard()),
              ],
            )
          else ...[
            _buildDailyTrendCard(),
            const SizedBox(height: 16),
            _buildDemographicsCard(),
          ],

          const SizedBox(height: 20),

          // ── CHARTS ROW 2: Top Diagnoses & Top Medicines ──────
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildRankCard("Top Diagnoses", Icons.healing_rounded, _result.topDiagnoses, AppColors.primary)),
                const SizedBox(width: 20),
                Expanded(child: _buildRankCard("Top Prescribed Medicines", Icons.medication_rounded, _result.topMedicines, const Color(0xFF0EA5E9))),
              ],
            )
          else ...[
            _buildRankCard("Top Diagnoses", Icons.healing_rounded, _result.topDiagnoses, AppColors.primary),
            const SizedBox(height: 16),
            _buildRankCard("Top Prescribed Medicines", Icons.medication_rounded, _result.topMedicines, const Color(0xFF0EA5E9)),
          ],

          const SizedBox(height: 20),

          // ── CHARTS ROW 3: Top Symptoms & Investigations ─────
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildRankCard("Top Symptoms", Icons.sick_rounded, _result.topSymptoms, const Color(0xFFF59E0B))),
                const SizedBox(width: 20),
                Expanded(child: _buildRankCard("Top Investigations / Tests", Icons.science_rounded, _result.topInvestigations, const Color(0xFF10B981))),
              ],
            )
          else ...[
            _buildRankCard("Top Symptoms", Icons.sick_rounded, _result.topSymptoms, const Color(0xFFF59E0B)),
            const SizedBox(height: 16),
            _buildRankCard("Top Investigations / Tests", Icons.science_rounded, _result.topInvestigations, const Color(0xFF10B981)),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  KPI CARDS
  // ─────────────────────────────────────────────────────────────
  Widget _buildKpiCardsRow(bool isDesktop) {
    final topDiag = _result.topDiagnoses.isNotEmpty ? _result.topDiagnoses.first['name'] : 'None';
    final topMed = _result.topMedicines.isNotEmpty ? _result.topMedicines.first['name'] : 'None';

    final cards = [
      _kpiCard("Total Patient Visits", "${_result.totalVisits}", Icons.people_alt_rounded, AppColors.primary, "Across selected range"),
      _kpiCard("Unique Patients", "${_result.uniquePatients}", Icons.badge_outlined, const Color(0xFF0EA5E9), "Distinct UHID records"),
      _kpiCard("Top Diagnosis", topDiag, Icons.healing_rounded, const Color(0xFFF59E0B), "Most frequent condition"),
      _kpiCard("Top Prescribed Rx", topMed, Icons.medication_rounded, const Color(0xFF8B5CF6), "Most dispensed medicine"),
    ];

    if (isDesktop) {
      return Row(
        children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
      );
    }

    return Column(
      children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList(),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  DAILY TIMELINE BAR CHART
  // ─────────────────────────────────────────────────────────────
  Widget _buildDailyTrendCard() {
    final trends = _result.dailyTrends;
    int maxCount = 1;
    for (var t in trends) {
      final c = t['count'] is int ? t['count'] as int : int.tryParse(t['count'].toString()) ?? 0;
      if (c > maxCount) maxCount = c;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Daily Patient Volume Trend", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text("Visit distribution across selected timeframe", style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(8)),
                child: Text("${trends.length} Data Points", style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (trends.isEmpty)
            Container(
              height: 160,
              alignment: Alignment.center,
              child: Text("No daily trend data", style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
            )
          else
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: trends.map((t) {
                  final count = t['count'] is int ? t['count'] as int : int.tryParse(t['count'].toString()) ?? 0;
                  final dateStr = t['visit_day']?.toString() ?? '';
                  String label = dateStr;
                  try {
                    final d = DateTime.parse(dateStr);
                    label = DateFormat('dd MMM').format(d);
                  } catch (_) {}

                  final double ratio = maxCount > 0 ? (count / maxCount) : 0.0;
                  final double barHeight = max(12.0, ratio * 130);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text("$count", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          const SizedBox(height: 4),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [AppColors.primaryDark, AppColors.primary],
                              ),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  DEMOGRAPHICS CARD (GENDER & AGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildDemographicsCard() {
    final total = max(1, _result.totalVisits);
    final maleRatio = (_result.maleCount / total) * 100;
    final femaleRatio = (_result.femaleCount / total) * 100;
    final otherRatio = (_result.otherCount / total) * 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Demographics & Gender", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text("Patient gender distribution", style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 20),

          // Stacked Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  if (_result.maleCount > 0)
                    Expanded(
                      flex: _result.maleCount,
                      child: Container(color: const Color(0xFF3B82F6)),
                    ),
                  if (_result.femaleCount > 0)
                    Expanded(
                      flex: _result.femaleCount,
                      child: Container(color: const Color(0xFFEC4899)),
                    ),
                  if (_result.otherCount > 0)
                    Expanded(
                      flex: _result.otherCount,
                      child: Container(color: const Color(0xFF94A3B8)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Legend Details
          _genderRow("Male", _result.maleCount, maleRatio, const Color(0xFF3B82F6)),
          const SizedBox(height: 10),
          _genderRow("Female", _result.femaleCount, femaleRatio, const Color(0xFFEC4899)),
          const SizedBox(height: 10),
          _genderRow("Other / Unspecified", _result.otherCount, otherRatio, const Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  Widget _genderRow(String label, int count, double percent, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const Spacer(),
        Text("$count (${percent.toStringAsFixed(1)}%)", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  RANKING BARS CARD (DIAGNOSIS, MEDICINES, SYMPTOMS, TESTS)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRankCard(String title, IconData icon, List<Map<String, dynamic>> items, Color barColor) {
    int maxCount = 1;
    for (var it in items) {
      final c = it['count'] is int ? it['count'] as int : int.tryParse(it['count'].toString()) ?? 0;
      if (c > maxCount) maxCount = c;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: barColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: barColor),
              ),
              const SizedBox(width: 10),
              Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text("No records in this category", style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
              ),
            )
          else
            ...items.take(6).map((it) {
              final name = it['name']?.toString() ?? '';
              final count = it['count'] is int ? it['count'] as int : int.tryParse(it['count'].toString()) ?? 0;
              final double ratio = maxCount > 0 ? (count / maxCount) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                        Text("$count visits", style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: barColor)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 6,
                        width: double.infinity,
                        color: const Color(0xFFF1F5F9),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: max(0.04, ratio),
                          child: Container(color: barColor),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  PATIENT RECORDS TABLE VIEW
  // ─────────────────────────────────────────────────────────────
  Widget _buildPatientRecordsView(bool isDesktop) {
    final filtered = _result.records.where((r) {
      if (_tableSearchQuery.isEmpty) return true;
      final q = _tableSearchQuery.toLowerCase();
      return r.patientName.toLowerCase().contains(q) ||
          r.uhid.toLowerCase().contains(q) ||
          r.phone.contains(q) ||
          r.diagnoses.any((d) => d.toLowerCase().contains(q)) ||
          r.medicines.any((m) => (m['name']?.toString().toLowerCase() ?? '').contains(q));
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Table search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _tableSearchController,
              onChanged: (v) => setState(() => _tableSearchQuery = v.trim()),
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: "Quick search in results by patient name, UHID, medicine, or diagnosis…",
                hintStyle: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _tableSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _tableSearchController.clear();
                          setState(() => _tableSearchQuery = "");
                        },
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Table Content
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text("No records match table search", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final r = filtered[index];
                          return _buildPatientRow(r);
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientRow(AnalyticsPatientRecord r) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.accentLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              r.patientName.isNotEmpty ? r.patientName[0].toUpperCase() : "P",
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),

          // Name, Age, UHID, Hospital
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.patientName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _tag(r.uhid, const Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    _tag("${r.ageInfo} / ${r.gender}", AppColors.primary),
                  ],
                ),
                if (r.hospitalName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(r.hospitalName, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),

          // Date & Status
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd MMM yyyy').format(r.createdAt), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(DateFormat('hh:mm a').format(r.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                if (r.isFinalized)
                  _statusTag("Finalized", AppColors.success)
                else
                  _statusTag("Active", AppColors.primary),
              ],
            ),
          ),

          // Diagnoses & Symptoms
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.diagnoses.isNotEmpty) ...[
                  Text("Diagnoses:", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: r.diagnoses.map((d) => _tag(d, const Color(0xFFD97706))).toList(),
                  ),
                ],
                if (r.symptoms.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text("Symptoms:", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: r.symptoms.take(3).map((s) => _tag(s, const Color(0xFF6B7280))).toList(),
                  ),
                ],
              ],
            ),
          ),

          // Medicines
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.medicines.isNotEmpty) ...[
                  Text("Medicines:", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: r.medicines.take(4).map((m) {
                      final n = m['name']?.toString() ?? '';
                      final d = m['dosage']?.toString() ?? '';
                      return _tag("$n ${d.isNotEmpty ? '($d)' : ''}".trim(), AppColors.primary);
                    }).toList(),
                  ),
                ] else
                  Text("—", style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _statusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text.toUpperCase(), style: GoogleFonts.poppins(fontSize: 8.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
    );
  }
}
