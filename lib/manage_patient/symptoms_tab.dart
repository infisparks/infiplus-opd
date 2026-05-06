import 'dart:async'; // For Timer (Debounce)
import 'dart:convert'; // For JSON encoding/decoding
import 'package:flutter/material.dart';

import '../supabase_handler.dart';
import '../services/master_data_service.dart'; // NEW
import '../main.dart'; // Imports Patient model
import '../services/server_data_service.dart'; // Direct Server Data
import 'package:intl/intl.dart';

import 'full_screen_search.dart';

// --- DATA MODELS (UNCHANGED) ---

class CustomOptionGroup {
  String title;
  List<String> options;
  CustomOptionGroup({required this.title, required this.options});

  Map<String, dynamic> toJson() => {'title': title, 'options': options};

  factory CustomOptionGroup.fromJson(Map<String, dynamic> json) {
    return CustomOptionGroup(
      title: json['title'] ?? '',
      options: List<String>.from(json['options'] ?? []),
    );
  }
}

class SymptomDetail {
  String name;
  String note;
  String? duration;
  String? severity;
  List<CustomOptionGroup> customGroups;
  Set<String> selectedCustomOptions;

  SymptomDetail({
    required this.name,
    this.note = '',
    this.duration,
    this.severity,
    List<CustomOptionGroup>? customGroups,
    Set<String>? selectedCustomOptions,
  })  : this.customGroups = customGroups ?? [],
        this.selectedCustomOptions = selectedCustomOptions ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'note': note,
    'duration': duration,
    'severity': severity,
    'custom_groups': customGroups.map((g) => g.toJson()).toList(),
    'selected_options': selectedCustomOptions.toList(),
  };

  factory SymptomDetail.fromJson(Map<String, dynamic> json) {
    return SymptomDetail(
      name: json['name'] ?? 'Unknown',
      note: json['note'] ?? '',
      duration: json['duration'],
      severity: json['severity'],
      customGroups: (json['custom_groups'] as List?)
          ?.map((e) => CustomOptionGroup.fromJson(e))
          .toList(),
      selectedCustomOptions: (json['selected_options'] as List?)
          ?.map((e) => e.toString())
          .toSet(),
    );
  }
}

// ---------------------------------------


// ---------------------------------------

class SymptomsTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const SymptomsTab({super.key, required this.patient, required this.opdId});

  @override
  State<SymptomsTab> createState() => _SymptomsTabState();
}

class _SymptomsTabState extends State<SymptomsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // State Variables
  int _selectedTabIndex = 0; // 0: Symptoms, 1: Findings, 2: All
  String _symptomSearchQuery = "";
  String? _selectedSymptomForDetail;
  final Map<String, SymptomDetail> _selectedSymptomDetails = {};
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _customValueController = TextEditingController();
  final TextEditingController _symptomSearchController = TextEditingController();

  // Data State
  bool _isLoadingMaster = true;
  List<String> _rawSymptoms = [];
  List<String> _rawFindings = [];

  final List<String> _durationOptions = ['1d', '2d', '3d', '4d', '1w', '2w', '1m', '3m', '6m', '1y'];
  final List<String> _severityOptions = ['Mild', 'Moderate', 'Severe'];

  // History State
  int _leftTabIndex = 0; // 0 = Current, 1 = History
  List<Map<String, dynamic>> _patientHistory = [];
  bool _isLoadingHistory = false;

  // Debouncer for Auto-Sync
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadAllData();

    // Listen for external syncs/reassignments (e.g. from HistoryTab)
    ServerDataService.refreshNotifier.addListener(_refreshFromLocal);
  }

  @override
  void dispose() {
    ServerDataService.refreshNotifier.removeListener(_refreshFromLocal);
    _noteController.dispose();
    _customValueController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _refreshFromLocal() async {
    if (!mounted) return;
    final serverData = await ServerDataService.fetchData(widget.opdId, 'symptoms');
    if (serverData != null) {
      _safePopulate(serverData);
      setState(() {});
    }
  }

  Future<void> _loadAllData() async {
    await _loadMasterData();
    await _loadPatientData();
    _fetchPatientHistory(); // Load History
  }

  // --- 1. MEMORY-OPTIMIZED MASTER DATA LOADING ---
  Future<void> _loadMasterData() async {
    final master = MasterDataService();
    setState(() {
      _rawSymptoms = master.symptoms;
      _rawFindings = master.findings;
      _isLoadingMaster = false;
    });

    // Background Refresh (Silent)
    master.syncWithCloud().then((_) {
      if (mounted) {
        setState(() {
          _rawSymptoms = master.symptoms;
          _rawFindings = master.findings;
        });
      }
    });
  }

  // --- 2. LOAD PATIENT DATA (ROBUST FIX) ---
  Future<void> _loadPatientData() async {
    // 1. Fetch directly from Server
    final serverData = await ServerDataService.fetchData(widget.opdId, 'symptoms');
    if (mounted) {
      setState(() {
        _safePopulate(serverData);
      });
    }
  }

  // Safely parses data whether it's a List or a JSON String
  void _safePopulate(dynamic data) {
    if (data == null) return;

    List<dynamic> listToProcess = [];

    try {
      if (data is List) {
        listToProcess = data;
      } else if (data is String) {
        // Handle case where Hive stored it as a string
        listToProcess = jsonDecode(data);
      } else if (data is Map) {
        // Handle rare case where it might be wrapped
        return;
      }

      if (listToProcess.isNotEmpty) {
        _populateData(listToProcess);
      }
    } catch (e) {
      debugPrint("Error parsing symptoms data: $e");
    }
  }

  void _populateData(List<dynamic> jsonList) {
    _selectedSymptomDetails.clear();
    for (var item in jsonList) {
      try {
        final detail = SymptomDetail.fromJson(item);
        _selectedSymptomDetails[detail.name] = detail;
      } catch (e) {
        debugPrint("Skipping invalid symptom item: $e");
      }
    }

    // Refresh the text controller if we are currently viewing a symptom
    if (_selectedSymptomForDetail != null) {
      _noteController.text = _selectedSymptomDetails[_selectedSymptomForDetail]?.note ?? '';
    }
  }

  // --- 3. AUTO SAVE LOGIC ---
  void _autoSave() {
    List<Map<String, dynamic>> jsonList = _selectedSymptomDetails.values
        .map((e) => e.toJson())
        .toList();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ServerDataService.saveData(widget.opdId, 'symptoms', jsonList, silent: true);
    });
  }

  // --- 4. HISTORY FETCHING (OPTIMIZED) ---
  Future<void> _fetchPatientHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      // Fetch distinct OPD visits for this patient that have symptoms
      final response = await SupabaseHandler.client
          .from('opd_reg_symptoms')
          .select('opd_id, created_at, opd_registration!inner(uhid)')
          .eq('opd_registration.uhid', widget.patient.id)
          .neq('opd_id', widget.opdId)
          .order('created_at', ascending: false);

      if (mounted) {
        // Group by OPD ID to show visit-wise history
        Map<int, Map<String, dynamic>> grouped = {};
        for (var row in response as List) {
          int oid = row['opd_id'];
          if (!grouped.containsKey(oid)) {
            grouped[oid] = {
              'id': oid,
              'created_at': row['created_at'],
              'symptoms_list_json': []
            };
          }
        }

        // Fetch the actual symptoms for these OPDs
        if (grouped.isNotEmpty) {
          final sResponse = await SupabaseHandler.client
              .from('opd_reg_symptoms')
              .select()
              .inFilter('opd_id', grouped.keys.toList());

          for (var s in sResponse as List) {
            int oid = s['opd_id'];
            (grouped[oid]!['symptoms_list_json'] as List).add({
              'name': s['name'],
              'note': s['note'],
              'duration': s['duration'],
              'severity': s['severity'],
              'custom_groups': s['custom_groups'],
              'selected_options': s['selected_options'],
            });
          }
        }

        setState(() {
          _patientHistory = grouped.values.toList();
        });
      }
    } catch (e) {
      debugPrint("Symptom History Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }


  void _reassignFromHistory(List<dynamic> oldSymptoms) {
    if (oldSymptoms.isEmpty) return;

    String? firstAdded;
    setState(() {
      _selectedSymptomDetails.clear(); // Overwrite current selection
      for (var item in oldSymptoms) {
        try {
          final detail = SymptomDetail.fromJson(Map<String, dynamic>.from(item));
          _selectedSymptomDetails[detail.name] = detail;
          firstAdded ??= detail.name;
        } catch (e) {
          debugPrint("Error copying symptom: $e");
        }
      }
      _leftTabIndex = 0; // Switch back to current (Capture)
      
      // Auto-focus the first added symptom for immediate feedback
      if (firstAdded != null) {
        _switchToDetailView(firstAdded!);
      }
    });

    _autoSave();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Reassigned ${oldSymptoms.length} from history"), behavior: SnackBarBehavior.floating),
    );
  }

  // --- LOGIC HELPER ---
  bool _isSymptom(String name) => _rawSymptoms.contains(name);

  void _selectSymptom(String label) {
    setState(() {
      if (!_selectedSymptomDetails.containsKey(label)) {
        _selectedSymptomDetails[label] = SymptomDetail(name: label);
      }
      _switchToDetailView(label);
    });
    _autoSave();
  }

  void _removeSymptom(String label) {
    setState(() {
      _selectedSymptomDetails.remove(label);
      if (_selectedSymptomForDetail == label) {
        _selectedSymptomForDetail = null;
        _noteController.clear();
      }
    });
    _autoSave();
  }

  void _switchToDetailView(String label) {
    _selectedSymptomForDetail = label;
    final detail = _selectedSymptomDetails[label];
    _noteController.text = detail?.note ?? '';
    
    // Sync custom value controller
    if (detail != null && detail.duration != null) {
      bool isPreset = _durationOptions.contains(detail.duration);
      if (!isPreset) {
        final match = RegExp(r'^(\d+)([dwmy])$').firstMatch(detail.duration!);
        if (match != null) {
          _customValueController.text = match.group(1) ?? "";
        } else {
          _customValueController.text = "";
        }
      } else {
        _customValueController.text = "";
      }
    } else {
      _customValueController.text = "";
    }
  }

  List<String> get _currentLeftList {
    List<String> source;
    if (_selectedTabIndex == 0) source = _rawSymptoms;
    else if (_selectedTabIndex == 1) source = _rawFindings;
    else source = [..._rawSymptoms, ..._rawFindings];

    if (_symptomSearchQuery.isNotEmpty) {
      source = source.where((element) =>
          element.toLowerCase().contains(_symptomSearchQuery.toLowerCase())
      ).toList();
    }
    return source.where((element) => !_selectedSymptomDetails.containsKey(element)).toList();
  }

  // --- MAIN BUILD ---
  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingMaster) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.bgBody,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            // --- LEFT PANEL (List) ---
            Expanded(
              flex: 4,
              child: Container(
                color: AppColors.surface, // Clean white column
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildCombinedHeaderTabs(),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: _leftTabIndex == 0 
                        ? _buildCurrentSymptomsColumn() 
                        : _buildHistoryColumn(),
                    ),
                  ],
                ),
              ),
            ),
            // Vertical Divider
            Container(width: 1, color: AppColors.border),

            // --- RIGHT PANEL (Details) ---
            Expanded(
              flex: 6, // Slightly wider for better editing experience
              child: Container(
                color: const Color(0xFFFAFAFA), // Very subtle gray for contrast against white inputs
                child: _selectedSymptomForDetail != null
                    ? _buildDetailPanel()
                    : _buildEmptyState(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                ),
            child: Icon(Icons.touch_app_rounded, size: 48, color: Colors.blueGrey.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 24),
          Text("No Symptom Selected",
              style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.7), fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text("Select a symptom from the left list to\nconfigure severity and clinical notes.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildSelectedChip(SymptomDetail detail) {
    bool isViewing = detail.name == _selectedSymptomForDetail;
    bool isSym = _isSymptom(detail.name);

    // Modern flat colors
    Color bg = isViewing
        ? (isSym ? AppColors.accent : AppColors.warning)
        : Colors.white;
    Color border = isViewing
        ? Colors.transparent
        : (isSym ? AppColors.accent.withValues(alpha: 0.3) : AppColors.warning.withValues(alpha: 0.3));
    Color text = isViewing
        ? Colors.white
        : AppColors.textPrimary;

    List<String> parts = [];
    if (isSym && detail.duration != null && detail.duration!.isNotEmpty) parts.add(detail.duration!);
    if (detail.severity != null) parts.add(detail.severity!);
    String subtitle = parts.join(" • ");

    return Container(
      child: InkWell(
        onTap: () => setState(() => _switchToDetailView(detail.name)),
        onLongPress: () => _showDeleteConfirmation(detail.name, false),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
            boxShadow: isViewing ? [
              BoxShadow(color: bg.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4))
            ] : [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, 1))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail.name, style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 13)),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(subtitle, style: TextStyle(color: text.withValues(alpha: 0.8), fontSize: 10)),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _removeSymptom(detail.name),
                child: Icon(Icons.close, color: text.withValues(alpha: 0.7), size: 16),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String label) {
    bool isSym = _isSymptom(label);
    return InkWell(
      onTap: () => _selectSymptom(label),
      onLongPress: () => _showDeleteConfirmation(label, true),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
            ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSym ? AppColors.textPrimary : AppColors.textSecondary)),
      ),
    );
  }

  void _showDeleteConfirmation(String name, bool fromMaster) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fromMaster ? "Remove from List?" : "Remove Symptom?"),
        content: Text(fromMaster 
          ? "Do you want to hide '$name' from the suggestion list?" 
          : "Do you want to remove '$name' from this prescription?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () {
              if (fromMaster) {
                setState(() {
                  _rawSymptoms.remove(name);
                  _rawFindings.remove(name);
                  MasterDataService().symptoms = _rawSymptoms;
                  MasterDataService().findings = _rawFindings;
                });
              } else {
                _removeSymptom(name);
              }
              Navigator.pop(context);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    SymptomDetail detail = _selectedSymptomDetails[_selectedSymptomForDetail!]!;
    bool isSym = _isSymptom(detail.name);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(32, 24, 24, 24),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border))
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: (isSym ? AppColors.accent : AppColors.warning).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)
                ),
                child: Icon(isSym ? Icons.favorite_rounded : Icons.search_rounded,
                    color: (isSym ? AppColors.accent : AppColors.warning), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isSym ? "CONFIGURING SYMPTOM" : "CONFIGURING FINDING",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text(detail.name, style: const TextStyle(fontSize: 22, color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton(
                  onPressed: () => _removeSymptom(detail.name),
                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red[300])
              ),
            ],
          ),
        ),

        // Scrollable Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Note Input
                const Text("Clinical Notes", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      ),
                  child: TextField(
                    controller: _noteController,
                    onChanged: (val) {
                      detail.note = val;
                      _autoSave();
                    },
                    maxLines: 3, minLines: 2,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Add specific observations...",
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Severity
                _buildSectionHeader("SEVERITY LEVEL", Icons.speed),
                const SizedBox(height: 12),
                _buildModernSeveritySelector(detail),
                const SizedBox(height: 32),

                // Duration
                if (isSym) ...[
                  _buildSectionHeader("DURATION OF SYMPTOM", Icons.timer_outlined),
                  const SizedBox(height: 12),
                  _buildModernDurationGrid(detail),
                  const SizedBox(height: 32),
                ],

                // Custom Options
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader("ADDITIONAL PARAMETERS", Icons.tune),
                    TextButton.icon(
                      onPressed: () async {
                        final result = await showDialog<CustomOptionGroup>(
                          context: context,
                          builder: (context) => const ProfessionalAddOptionDialog(),
                        );
                        if(result != null) {
                          setState(() => detail.customGroups.add(result));
                          _autoSave();
                        }
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("New Group"),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 12),

                if(detail.customGroups.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text("No custom parameters added.", style: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic, fontSize: 13))),
                  ),

                ...detail.customGroups.map((group) => _buildCustomGroup(group, detail)),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.0)),
      ],
    );
  }

  Widget _buildCustomGroup(CustomOptionGroup group, SymptomDetail detail) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(group.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: group.options.map((opt) {
              bool isSelected = detail.selectedCustomOptions.contains(opt);
              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) detail.selectedCustomOptions.remove(opt);
                    else detail.selectedCustomOptions.add(opt);
                  });
                  _autoSave();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? AppColors.primary : Colors.grey[300]!),
                      boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 5, offset: const Offset(0, 2))] : []
                  ),
                  child: Text(opt, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppColors.textPrimary, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDurationGrid(SymptomDetail detail) {
    bool isPreset = _durationOptions.contains(detail.duration);
    bool isCustom = detail.duration != null && detail.duration!.isNotEmpty && !isPreset;

    return Wrap(
      spacing: 8, runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._durationOptions.map((d) {
          bool isSelected = detail.duration == d;
          return InkWell(
            onTap: () {
              setState(() => detail.duration = d);
              _customValueController.clear();
              _autoSave();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 48, height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.textPrimary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? AppColors.textPrimary : Colors.grey[300]!),
                boxShadow: isSelected
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0,2))]
                    : [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 2, offset: const Offset(0,1))],
              ),
              child: Text(d, style: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 13)),
            ),
          );
        }),
        
        // --- INTEGRATED CUSTOM OPTION ---
        _buildCustomDurationIntegrated(detail, isCustom),
      ],
    );
  }

  Widget _buildCustomDurationIntegrated(SymptomDetail detail, bool isCustom) {
    String unit = "d"; // Default
    if (isCustom && detail.duration != null) {
      final match = RegExp(r'^(\d+)([dwmy])$').firstMatch(detail.duration!);
      if (match != null) unit = match.group(2) ?? "d";
    }

    return Container(
      width: 130, height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isCustom ? AppColors.primary.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCustom ? AppColors.primary : Colors.grey[300]!, width: isCustom ? 1.5 : 1),
        boxShadow: isCustom ? [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 4)] : []
      ),
      child: Row(
        children: [
          // Value Input
          Expanded(
            flex: 2,
            child: TextField(
              controller: _customValueController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isCustom ? AppColors.primary : AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: "...",
                hintStyle: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.normal),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                if (v.isNotEmpty) {
                  detail.duration = "$v$unit";
                  if (!isCustom) setState(() {}); // Trigger highlight
                  _autoSave();
                } else {
                  detail.duration = null;
                  setState(() {});
                  _autoSave();
                }
              },
            ),
          ),
          // Vertical Divider
          Container(width: 1, height: 20, color: Colors.grey[300]),
          // Unit Dropdown
          Expanded(
            flex: 3,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: unit,
                isDense: true,
                isExpanded: true,
                iconSize: 16,
                padding: const EdgeInsets.only(left: 6),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isCustom ? AppColors.primary : AppColors.textSecondary),
                items: [
                  {'val': 'd', 'lbl': 'Day'},
                  {'val': 'w', 'lbl': 'Week'},
                  {'val': 'm', 'lbl': 'Month'},
                  {'val': 'y', 'lbl': 'Year'},
                ].map((item) => DropdownMenuItem(value: item['val'] as String, child: Text(item['lbl'] as String))).toList(),
                onChanged: (newUnit) {
                  if (newUnit != null) {
                    String val = _customValueController.text;
                    if (val.isEmpty) val = "1";
                    setState(() {
                       detail.duration = "$val$newUnit";
                       if (_customValueController.text.isEmpty) _customValueController.text = "1";
                    });
                    _autoSave();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildModernSeveritySelector(SymptomDetail detail) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12)
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: _severityOptions.map((severity) {
          bool isSelected = detail.severity == severity;
          Color activeColor = (severity == 'Mild') ? Colors.green[600]! : (severity == 'Moderate') ? Colors.orange[600]! : Colors.red[600]!;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => detail.severity = severity);
                _autoSave();
              },
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0,2))] : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if(isSelected) ...[
                      Icon(Icons.circle, size: 8, color: activeColor),
                      const SizedBox(width: 6)
                    ],
                    Text(severity, style: TextStyle(
                        color: isSelected ? AppColors.textPrimary : Colors.grey[500],
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12
                    )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCombinedHeaderTabs() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 36,
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.all(2),
            child: Row(
              children: [
                Expanded(child: _buildPanelTabItem("Capture", 0)),
                Expanded(child: _buildPanelTabItem("History", 1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanelTabItem(String text, int index) {
    bool isSelected = _leftTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _leftTabIndex = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : [],
        ),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildModernTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
      child: Row(children: [_buildTabItem("Symptoms", 0), _buildTabItem("Findings", 1), _buildTabItem("All", 2)]),
    );
  }

  Widget _buildTabItem(String text, int index) {
    bool isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : []
          ),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildCurrentSymptomsColumn() {
    return Column(
      children: [
        _buildModernSearchBar(),
        const SizedBox(height: 8),
        _buildModernTabs(),
        const SizedBox(height: 8),
        // Active Selection Mini-Basket (Filtered by Tab)
        if (_selectedSymptomDetails.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: _selectedSymptomDetails.values.where((detail) {
                bool isSym = _isSymptom(detail.name);
                if (_selectedTabIndex == 0) return isSym;
                if (_selectedTabIndex == 1) return !isSym;
                return true; // All
              }).map((detail) => _buildSelectedChip(detail)).toList(),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
        Expanded(
          child: _currentLeftList.isEmpty && _symptomSearchQuery.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text("No results for '$_symptomSearchQuery'", style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text("Create & Select"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            final val = _symptomSearchQuery.trim();
                            if (val.isNotEmpty) {
                              // If on Findings tab, add to findings. Otherwise, add to symptoms.
                              if (_selectedTabIndex == 1) {
                                if (!_rawFindings.contains(val)) {
                                  _rawFindings.add(val);
                                  MasterDataService().saveDataset('findings', _rawFindings);
                                }
                              } else {
                                if (!_rawSymptoms.contains(val)) {
                                  _rawSymptoms.add(val);
                                  MasterDataService().saveDataset('symptoms', _rawSymptoms);
                                }
                              }
                              _selectSymptom(val);
                              setState(() {
                                _symptomSearchQuery = '';
                                _symptomSearchController.clear();
                              });
                            }
                          },
                        )
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: _currentLeftList.map((s) => _buildSuggestionChip(s)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryColumn() {
    if (_isLoadingHistory) return const Center(child: CircularProgressIndicator());
    if (_patientHistory.isEmpty) return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 8),
        Text("No Past History", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    ));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _patientHistory.length,
      itemBuilder: (context, index) {
        final visit = _patientHistory[index];
        final List<dynamic> oldSyms = visit['symptoms_list_json'] ?? [];
        final date = DateTime.parse(visit['created_at']);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    _buildHistoryCopyBtn(() => _reassignFromHistory(oldSyms)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: oldSyms.map((s) {
                    final isMap = s is Map;
                    final name = isMap ? (s['name'] ?? 'Unknown Item') : s.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(name, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryDetailText(dynamic s) {
    if (s is! Map) return const SizedBox.shrink();
    List<String> parts = [];
    if (s['severity'] != null && s['severity'].toString().isNotEmpty) parts.add(s['severity'].toString());
    if (s['duration'] != null && s['duration'].toString().isNotEmpty) parts.add(s['duration'].toString());
    if (s['note'] != null && s['note'].toString().isNotEmpty) parts.add(s['note'].toString());

    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 2),
      child: Text(parts.join(", "), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
    );
  }

  Widget _buildHistoryCopyBtn(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(16)),
        child: const Row(children: [Icon(Icons.copy_all, size: 10, color: AppColors.primary), SizedBox(width: 4), Text("Copy", style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  Widget _buildModernSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: InkWell(
        onTap: () {
          String title = "Search Symptoms";
          if (_selectedTabIndex == 1) title = "Search Findings";
          if (_selectedTabIndex == 2) title = "Search Symptoms & Findings";

          List<String> items = _rawSymptoms;
          if (_selectedTabIndex == 1) items = _rawFindings;
          if (_selectedTabIndex == 2) items = [..._rawSymptoms, ..._rawFindings];

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => FullScreenSearchPage(
                title: title,
                hintText: "Type to search...",
                allItems: items,
                onItemSelected: (selected) {
                  // Logic to add to the correct list if it's a new item
                  if (_selectedTabIndex == 1) {
                    if (!_rawFindings.contains(selected)) {
                      _rawFindings.add(selected);
                      MasterDataService().saveDataset('findings', _rawFindings);
                    }
                  } else {
                    // Default to symptoms if in tab 0 or 2
                    if (!_rawSymptoms.contains(selected) && !_rawFindings.contains(selected)) {
                      _rawSymptoms.add(selected);
                      MasterDataService().saveDataset('symptoms', _rawSymptoms);
                    }
                  }
                  _selectSymptom(selected);
                },
                onItemRemoved: (selected) {
                  setState(() {
                    _selectedSymptomDetails.remove(selected);
                    if (_selectedSymptomForDetail == selected) {
                      _selectedSymptomForDetail = null;
                      _noteController.clear();
                    }
                  });
                  _autoSave();
                },
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                _selectedTabIndex == 1 ? "Tap to search findings..." : "Tap to search symptoms...",
                style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- DIALOG CLASS (UNCHANGED LOGIC, UPDATED UI) ---
class ProfessionalAddOptionDialog extends StatefulWidget {
  const ProfessionalAddOptionDialog({super.key});

  @override
  State<ProfessionalAddOptionDialog> createState() => _ProfessionalAddOptionDialogState();
}

class _ProfessionalAddOptionDialogState extends State<ProfessionalAddOptionDialog> {
  final TextEditingController _titleController = TextEditingController();
  List<TextEditingController> _optionControllers = [];

  @override
  void initState() {
    super.initState();
    _optionControllers.add(TextEditingController());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      elevation: 0,
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.settings_input_component, color: AppColors.primary, size: 22)),
                const SizedBox(width: 16),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Configure Options", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), Text("Add custom parameters to this symptom", style: TextStyle(fontSize: 12, color: AppColors.textSecondary))]),
              ],
            ),
            const SizedBox(height: 32),

            const Text("GROUP TITLE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            _buildModernTextField(controller: _titleController, hint: "e.g. Pain Location, Side Effects"),
            const SizedBox(height: 24),

            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("OPTIONS LIST", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.0)), InkWell(onTap: () => setState(() => _optionControllers.add(TextEditingController())), child: const Text("+ Add Item", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)))]),
            const SizedBox(height: 12),

            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(_optionControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Row(children: [Text("${index + 1}.", style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 12), Expanded(child: _buildModernTextField(controller: _optionControllers[index], hint: "Option Name", isCompact: true)),
                        const SizedBox(width: 8), InkWell(onTap: () => setState(() => _optionControllers.removeAt(index)), child: Icon(Icons.remove_circle_outline, color: Colors.red[200], size: 20))]),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel"))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: () {
                  List<String> validOptions = _optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                  if (_titleController.text.isNotEmpty && validOptions.isNotEmpty) {
                    Navigator.pop(context, CustomOptionGroup(title: _titleController.text, options: validOptions));
                  }
                }, style: ElevatedButton.styleFrom(backgroundColor: AppColors.textPrimary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("Save Configuration", style: TextStyle(fontWeight: FontWeight.bold)))),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({required TextEditingController controller, required String hint, bool isCompact = false}) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
      child: TextField(controller: controller, style: const TextStyle(fontSize: 13), decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey[400]), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: isCompact ? 12 : 16))),
    );
  }
}