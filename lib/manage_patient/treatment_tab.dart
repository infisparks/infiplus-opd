import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../supabase_handler.dart';
import '../services/master_data_service.dart'; // NEW
import '../main.dart';
import '../services/server_data_service.dart';
import 'full_screen_search.dart';

// --- THEME ---
class TxTheme {
  static const Color primary = Color(0xFF6366F1); // Indigo / Purple
  static const Color background = Color(0xFFF5F6F8);
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF111827);
  static const Color textSub = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
}

// --- MODELS ---
class TimingSchedule {
  String beforeBreakfast;
  String afterBreakfast;
  String beforeLunch;
  String afterLunch;
  String beforeDinner;
  String afterDinner;

  TimingSchedule({
    this.beforeBreakfast = "0",
    this.afterBreakfast = "0",
    this.beforeLunch = "0",
    this.afterLunch = "0",
    this.beforeDinner = "0",
    this.afterDinner = "0",
  });

  Map<String, dynamic> toJson() => {
    'bb': beforeBreakfast, 'ab': afterBreakfast,
    'bl': beforeLunch, 'al': afterLunch,
    'bd': beforeDinner, 'ad': afterDinner,
  };

  factory TimingSchedule.fromJson(Map<String, dynamic> json) {
    String parseVal(dynamic val) {
      if (val is bool) {
        return val ? "1" : "0";
      }
      if (val == null) return "0";
      return val.toString();
    }

    return TimingSchedule(
      beforeBreakfast: parseVal(json['bb']),
      afterBreakfast: parseVal(json['ab']),
      beforeLunch: parseVal(json['bl']),
      afterLunch: parseVal(json['al']),
      beforeDinner: parseVal(json['bd']),
      afterDinner: parseVal(json['ad']),
    );
  }
}

class PrescriptionEntry {
  String id;
  String name;
  String type;
  String unit;
  String dosage;
  TimingSchedule timing;
  String duration;
  String note;

  PrescriptionEntry({
    required this.id,
    required this.name,
    required this.type,
    this.unit = "",
    String? dosage,
    TimingSchedule? timing,
    this.duration = "1d",
    this.note = "",
  }) :
        this.dosage = dosage ?? "1",
        this.timing = timing ?? TimingSchedule();

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'type': type, 'unit': unit,
    'dosage': dosage, 'duration': duration, 'note': note,
    'timing': timing.toJson(),
  };

  factory PrescriptionEntry.fromJson(Map<String, dynamic> json) {
    return PrescriptionEntry(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      unit: json['unit'] ?? '',
      dosage: json['dosage'],
      duration: json['duration'] ?? '1d',
      note: json['note'] ?? '',
      timing: json['timing'] != null ? TimingSchedule.fromJson(json['timing']) : null,
    );
  }
}

// --- MAIN WIDGET ---
class TreatmentTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const TreatmentTab({super.key, required this.patient, required this.opdId});

  @override
  State<TreatmentTab> createState() => _TreatmentTabState();
}

class _TreatmentTabState extends State<TreatmentTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _leftTabIndex = 0; // 0 = Current, 1 = History

  // Data State
  List<PrescriptionEntry> _currentPrescription = [];
  PrescriptionEntry? _selectedMedicine;
  List<Map<String, String>> _medicineMasterList = [];
  List<String> _suggestedMeds = [];
  bool _isOnline = true;

  // History State
  List<Map<String, dynamic>> _patientHistory = [];
  bool _isLoadingHistory = false;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _customDosageController = TextEditingController();
  final TextEditingController _customDurationController = TextEditingController();
  String _customDurationUnit = 'd';
  Timer? _debounce;

  // Constants
  final List<String> _doseOptions = ["1/4", "1/2", "1", "1½", "2", "3"];
  final List<String> _durationOptions = ["3d", "5d", "7d", "10d", "15d", "1m", "2m", "3m"];

  @override
  void initState() {
    super.initState();
    _smartLoadData();
    _fetchPatientHistory(); // Load history on init
    _fetchRxSuggestions(); // AI INIT
    
    // Listen for external syncs/reassignments (e.g. from HistoryTab)
    ServerDataService.refreshNotifier.addListener(_refreshFromLocal);
  }

  @override
  void dispose() {
    ServerDataService.refreshNotifier.removeListener(_refreshFromLocal);
    _searchController.dispose();
    _noteController.dispose();
    _customDosageController.dispose();
    _customDurationController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _refreshFromLocal() async {
    if (!mounted) return;
    final serverData = await ServerDataService.fetchData(widget.opdId, 'treatment_data');
    if (serverData != null) {
      setState(() {
        _populatePrescription(serverData);
      });
    }
  }

  // --- 1. DATA LOADING (Cloud + Local) ---
  Future<void> _smartLoadData() async {
    await _loadMasterData();

    // Check Internet
    var connectivityResult = await (Connectivity().checkConnectivity());
    bool hasInternet = !connectivityResult.contains(ConnectivityResult.none);

    if (hasInternet) {
      if (mounted) setState(() => _isOnline = true);
    } else {
      if (mounted) setState(() => _isOnline = false);
    }

    // Load Data from Server (Source of Truth for Editing)
    final serverData = await ServerDataService.fetchData(widget.opdId, 'treatment_data');
    if (serverData != null) {
      _populatePrescription(serverData);
    }
  }

  Future<void> _loadMasterData() async {
    final master = MasterDataService();
    setState(() {
      _medicineMasterList = master.medicines;
    });

    // Background Refresh (Silent)
    master.syncWithCloud().then((_) {
      if (mounted) {
        setState(() {
          _medicineMasterList = master.medicines;
        });
      }
    });
  }

  // --- 2. HISTORY FETCHING (OPTIMIZED) ---
  Future<void> _fetchPatientHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final response = await SupabaseHandler.client
          .from('opd_reg_rx')
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
              'rx_list_json': []
            };
          }
        }

        // Fetch the actual RX items for these OPDs
        if (grouped.isNotEmpty) {
          final rxResponse = await SupabaseHandler.client
              .from('opd_reg_rx')
              .select()
              .inFilter('opd_id', grouped.keys.toList());

          for (var rx in rxResponse as List) {
            int oid = rx['opd_id'];
            (grouped[oid]!['rx_list_json'] as List).add({
              'id': rx['id'].toString(),
              'name': rx['medicine_name'],
              'type': rx['medicine_type'],
              'unit': rx['unit'],
              'dosage': rx['dosage'],
              'duration': rx['duration'],
              'timing': rx['timing_json'],
              'note': rx['note'],
            });
          }
        }

        setState(() {
          _patientHistory = grouped.values.toList();
        });
      }
    } catch (e) {
      debugPrint("Rx History Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }


  void _reassignFromHistory(List<dynamic> oldRxList) {
    if (oldRxList.isEmpty) return;

    PrescriptionEntry? firstAdded;
    setState(() {
      _currentPrescription.clear(); // Clear current for clean overwrite
      for (var i = 0; i < oldRxList.length; i++) {
        try {
          final item = oldRxList[i];
          if (item is! Map) continue; // Skip invalid items

          PrescriptionEntry oldMed = PrescriptionEntry.fromJson(Map<String, dynamic>.from(item));
          if (oldMed.name.isEmpty) continue; // Skip empty names
          
          // Clone with unique ID
          PrescriptionEntry newMed = PrescriptionEntry(
            id: "${DateTime.now().millisecondsSinceEpoch}_${i}_${oldMed.name.hashCode}",
            name: oldMed.name,
            type: oldMed.type,
            dosage: oldMed.dosage,
            duration: oldMed.duration,
            note: oldMed.note,
            timing: oldMed.timing,
          );
          
          _currentPrescription.add(newMed);
          firstAdded ??= newMed;
        } catch (e) {
          debugPrint("Error copying medicine: $e");
        }
      }
      _leftTabIndex = 0; // Switch back to 'Current Rx' tab
      
      // Auto-select the first medication to show in editor
      if (firstAdded != null) {
        _selectMedicine(firstAdded!);
      }
    });

    _autoSave();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Reassigned ${oldRxList.length} medicines"), behavior: SnackBarBehavior.floating),
    );
  }


  // --- 3. STATE MANAGEMENT ---
  void _populatePrescription(dynamic data) {
    if (data == null) return;
    
    // Remember which medicine was being edited (by name)
    String? selectedMedName = _selectedMedicine?.name;

    List<dynamic> listToProcess = [];
    if (data is String) {
      try { listToProcess = jsonDecode(data); } catch (e) { debugPrint("JSON Decode Error: $e"); }
    } else if (data is List) {
      listToProcess = data;
    }

    try {
      setState(() {
        _currentPrescription = listToProcess.map((e) => PrescriptionEntry.fromJson(e)).toList();
        
        // Re-link selection to the new instance in the refreshed list
        if (selectedMedName != null) {
          try {
            final match = _currentPrescription.firstWhere((m) => m.name == selectedMedName);
            _selectMedicine(match); // Re-syncs controllers and selection
          } catch (e) {
            // If the previously selected medicine is gone, clear selection
            _selectedMedicine = null;
          }
        }
      });
    } catch(e) {
      debugPrint("Error parsing prescription objects: $e");
    }
  }

  void _autoSave() {
    final jsonList = _currentPrescription.map((e) => e.toJson()).toList();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ServerDataService.saveData(widget.opdId, 'treatment_data', jsonList, silent: true);
      if (_selectedMedicine != null) {
        MasterDataService().saveMedicine(
          _selectedMedicine!.name,
          _selectedMedicine!.type,
          _selectedMedicine!.unit,
          defaultNote: _selectedMedicine!.note,
        );
      }
    });
  }

  void _addMedicine(String name, String type) {
    setState(() {
      // Find extra data from master list if it exists
      String finalType = type;
      String finalUnit = "";
      String finalNote = "";
      
      final masterItem = _medicineMasterList.firstWhere(
        (m) => m['name'] == name, 
        orElse: () => {}
      );
      
      if (masterItem.isNotEmpty) {
        finalType = masterItem['type'] ?? type;
        finalUnit = masterItem['unit'] ?? "";
        finalNote = masterItem['default_note'] ?? "";
      }

      final newMed = PrescriptionEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          type: finalType,
          unit: finalUnit,
          note: finalNote
      );

      // Auto-set common dosages based on type if unit is empty
      if (finalUnit.isEmpty) {
        if (finalType == "SYRUP" || finalType == "SUSP" || finalType == "DROP") {
          newMed.unit = "ml";
          newMed.dosage = "10";
        } else if (finalType == "TAB" || finalType == "CAP") {
          newMed.unit = finalType.toLowerCase();
          newMed.dosage = "1";
        }
      }

      _currentPrescription.add(newMed);
      _selectMedicine(newMed);
      _searchController.clear();
    });
    _autoSave();
  }

  void _selectMedicine(PrescriptionEntry med) {
    setState(() {
      _selectedMedicine = med;
      _noteController.text = med.note;
      
      // Sync Custom Inputs
      if (!_doseOptions.contains(med.dosage)) {
        _customDosageController.text = med.dosage;
      } else {
        _customDosageController.clear();
      }

      // Sync Duration
      String dVal = med.duration.replaceAll(RegExp(r'[dmy]'), '');
      String dUnit = med.duration.replaceAll(RegExp(r'[^dmy]'), '');
      _customDurationController.text = dVal;
      _customDurationUnit = dUnit.isEmpty ? 'd' : dUnit;
    });
    _fetchRxSuggestions(); // Update suggestions
  }

  Future<void> _fetchRxSuggestions() async {
    try {
      final symData = await ServerDataService.fetchData(widget.opdId, 'symptoms') ?? [];
      final diagData = await ServerDataService.fetchData(widget.opdId, 'diagnosis_data') ?? [];

      List<Map<String, String>> sources = [];
      if (symData is List) {
        for (var s in symData) sources.add({'type': 'symptom', 'val': s['name']});
      }
      if (diagData is List) {
        for (var d in diagData) sources.add({'type': 'diagnosis', 'val': d['name']});
      }

      if (sources.isEmpty) {
        _loadDefaultCommonMeds();
        return;
      }

      final response = await SupabaseHandler.client.rpc('get_opd_suggestions', params: {
        'p_sources': sources,
        'p_target_type': 'medicine'
      });

      if (mounted && response != null && (response as List).isNotEmpty) {
        setState(() {
          _suggestedMeds = (response as List).map((e) => e['target_value'].toString()).toList();
        });
      } else {
        _loadDefaultCommonMeds();
      }
    } catch(e) {
      debugPrint("Rx AI Suggestion Error: $e");
      _loadDefaultCommonMeds();
    }
  }

  void _loadDefaultCommonMeds() {
    if (_medicineMasterList.isNotEmpty && mounted) {
      setState(() {
        _suggestedMeds = _medicineMasterList
            .take(15)
            .map((e) => e['name'] ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
      });
    }
  }

  void _removeMedicine(PrescriptionEntry med) {
    setState(() {
      _currentPrescription.remove(med);
      if (_selectedMedicine == med) {
        _selectedMedicine = null;
      }
    });
    _autoSave();
  }

  // --- 4. UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Refresh suggestions whenever the tab is viewed to stay in sync with symptoms and diagnosis
    _fetchRxSuggestions();
    return Scaffold(
      backgroundColor: TxTheme.background,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            // LEFT PANEL (LIST / HISTORY)
            Expanded(
              flex: 4,
              child: Container(
                color: TxTheme.surface,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildModernTabs(),
                    const Divider(height: 1, color: TxTheme.border),
                    Expanded(
                      child: _leftTabIndex == 0 ? _buildMedicinesList() : _buildHistoryList(),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, color: TxTheme.border),
            // RIGHT PANEL (EDITOR)
            Expanded(
              flex: 6,
              child: _selectedMedicine != null ? _buildEditorCockpit() : _buildEmptyState(),
            ),
          ],
        ),
      ),
    );
  }

  // --- HISTORY UI ---
  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_patientHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text("No past prescriptions found", style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _patientHistory.length,
      separatorBuilder: (c, i) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final visit = _patientHistory[index];
        final DateTime date = DateTime.parse(visit['created_at']);
        final List<dynamic> meds = visit['rx_list_json'] ?? [];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TxTheme.border),
            
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: TxTheme.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_note, size: 16, color: TxTheme.primary),
                        const SizedBox(width: 8),
                        Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TxTheme.textMain)),
                      ],
                    ),
                    InkWell(
                      onTap: () => _reassignFromHistory(meds),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TxTheme.primary.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
                        child: const Row(
                          children: [
                            Icon(Icons.copy_all, size: 14, color: TxTheme.primary),
                            SizedBox(width: 4),
                            Text("Copy All", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TxTheme.primary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // List
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: meds.map<Widget>((m) {
                    if (m is! Map) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text("• $m", style: const TextStyle(fontSize: 12, color: TxTheme.textSub)),
                      );
                    }
                    
                    final medName = m['name'] ?? 'Unknown';
                    final duration = m['duration'] ?? '';

                    // Frequency Preview
                    String freq = "0-0-0";
                    if(m['timing'] != null) {
                      final t = m['timing'];
                      String getVal(dynamic b, dynamic a) {
                        String parseSingle(dynamic val) {
                          if (val == null) return "0";
                          if (val is bool) return val ? "1" : "0";
                          final s = val.toString().trim();
                          return s.isEmpty ? "0" : s;
                        }
                        final bVal = parseSingle(b);
                        final aVal = parseSingle(a);
                        if (bVal != "0") return bVal;
                        return aVal;
                      }
                      String m1 = getVal(t['bb'], t['ab']);
                      String m2 = getVal(t['bl'], t['al']);
                      String m3 = getVal(t['bd'], t['ad']);
                      freq = "$m1-$m2-$m3";
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("• $medName", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TxTheme.textMain)),
                                Text("$freq | $duration", style: const TextStyle(fontSize: 10, color: TxTheme.textSub)),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              try {
                                final entry = PrescriptionEntry.fromJson(Map<String, dynamic>.from(m));
                                PrescriptionEntry newMed = PrescriptionEntry(
                                  id: "${DateTime.now().millisecondsSinceEpoch}_${medName.hashCode}",
                                  name: entry.name,
                                  type: entry.type,
                                  dosage: entry.dosage,
                                  duration: entry.duration,
                                  note: entry.note,
                                  timing: entry.timing,
                                );
                                setState(() {
                                  _currentPrescription.add(newMed);
                                  _leftTabIndex = 0;
                                  _selectMedicine(newMed);
                                });
                                _autoSave();
                              } catch(e) {
                                debugPrint("Surgical Copy Error: $e");
                              }
                            },
                            child: const Icon(Icons.add_circle_outline, size: 20, color: TxTheme.primary),
                          ),
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

  // --- GENERAL UI COMPONENTS ---

  Widget _buildModernTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(child: _buildTabBtn("Current Rx", 0, Icons.medication_outlined)),
            Expanded(child: _buildTabBtn("History", 1, Icons.history_rounded)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBtn(String label, int index, IconData icon) {
    bool isSel = _leftTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _leftTabIndex = index),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSel ? [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 6, offset: const Offset(0, 1))] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: isSel ? TxTheme.primary : TxTheme.textSub),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              fontSize: 11,
              color: isSel ? TxTheme.primary : TxTheme.textSub,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicinesList() {
    final bool hasMeds = _currentPrescription.isNotEmpty;

    return Column(
      children: [
        // ── SEARCH BAR (Match Symptoms Tab) ────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => FullScreenSearchPage(
                    title: "Search Medicines",
                    hintText: "Type medicine name...",
                    allItems: _medicineMasterList.map((e) => e['name'] ?? '').where((n) => n.isNotEmpty).toList(),
                    onItemSelected: (selected) {
                      if (!_medicineMasterList.any((m) => m['name'] == selected)) {
                        _medicineMasterList.add({'name': selected, 'type': 'TAB', 'unit': ''});
                        // PERMANENT SAVE TO CLOUD
                        MasterDataService().saveMedicine(selected, 'TAB', '');
                      }
                      _addMedicine(selected, "TAB");
                    },
                    onItemRemoved: (selected) {
                      setState(() {
                        _currentPrescription.removeWhere((m) => m.name == selected);
                        if (_selectedMedicine?.name == selected) {
                          _selectedMedicine = null;
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
                  border: Border.all(color: TxTheme.border),
                  ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: TxTheme.primary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Tap to search medicines...", style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ),
                  if (hasMeds)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: TxTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text("${_currentPrescription.length} Rx",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TxTheme.primary)),
                    ),
                ],
              ),
            ),
          ),
        ),

        // ── ACTIVE MEDICATIONS & SUGGESTIONS ───────────────────────────
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasMeds) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4, height: 16,
                          decoration: BoxDecoration(color: TxTheme.primary, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 8),
                        Text("ACTIVE RX (${_currentPrescription.length})",
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: TxTheme.textMain, letterSpacing: 0.5)),
                        const Spacer(),
                        InkWell(
                          onTap: _showBulkDurationDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: TxTheme.primary.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: TxTheme.primary.withAlpha(30)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.auto_fix_high_rounded, size: 14, color: TxTheme.primary),
                                SizedBox(width: 4),
                                Text("Set All Duration", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: TxTheme.primary)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text("tap to edit", style: GoogleFonts.poppins(fontSize: 11, color: TxTheme.textSub.withOpacity(0.6))),
                      ],
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _currentPrescription.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final med = _currentPrescription[i];
                      final isSel = _selectedMedicine == med;
                      
                      // Frequency Preview
                      String freq = "0-0-0";
                      if(med.timing != null) {
                        final t = med.timing!;
                        String getVal(String b, String a) {
                          if (b != "0") return b;
                          return a;
                        }
                        String m1 = getVal(t.beforeBreakfast, t.afterBreakfast);
                        String m2 = getVal(t.beforeLunch, t.afterLunch);
                        String m3 = getVal(t.beforeDinner, t.afterDinner);
                        freq = "$m1-$m2-$m3";
                      }

                      return Dismissible(
                        key: Key(med.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(color: Colors.red[400], borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) => _removeMedicine(med),
                        child: GestureDetector(
                          onTap: () => _selectMedicine(med),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSel ? TxTheme.primary : Colors.white,
                              border: Border.all(color: isSel ? TxTheme.primary : const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: isSel ? [BoxShadow(color: TxTheme.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSel ? Colors.white.withOpacity(0.2) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(med.type,
                                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600,
                                      color: isSel ? Colors.white : TxTheme.primary)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(med.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500,
                                          color: isSel ? Colors.white : TxTheme.textMain)),
                                      if (med.duration.isNotEmpty || freq != "0-0-0")
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text("$freq | ${med.duration} | ${med.dosage} ${med.unit}", style: GoogleFonts.poppins(fontSize: 12, color: isSel ? Colors.white70 : TxTheme.textSub)),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isSel)
                                  const Icon(Icons.edit_rounded, size: 18, color: Colors.white)
                                else
                                  const Icon(Icons.edit_rounded, size: 18, color: Colors.grey),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap: () => _removeMedicine(med),
                                  child: Icon(Icons.delete_outline_rounded, size: 20, color: isSel ? Colors.white70 : Colors.red[300]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.medication_outlined, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text("No active medicines", style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── AI SUGGESTIONS (Bottom) ───────────────────
                if (_suggestedMeds.isNotEmpty || _medicineMasterList.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_suggestedMeds.isNotEmpty) ...[
                          Row(children: [
                            const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.purple),
                            const SizedBox(width: 6),
                            Text("AI SUGGESTED", style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.purple, letterSpacing: 0.5)),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _suggestedMeds.take(8).map((name) => InkWell(
                              onTap: () => _addMedicine(name, "TAB"),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.05),
                                  border: Border.all(color: Colors.purple.withOpacity(0.2)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF6B21A8))),
                              ),
                            )).toList(),
                          ),
                        ] else ...[
                          Row(children: [
                            const Icon(Icons.star_rounded, size: 14, color: TxTheme.textSub),
                            const SizedBox(width: 6),
                            Text("FREQUENTLY PRESCRIBED", style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: TxTheme.textSub, letterSpacing: 0.5)),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _medicineMasterList.take(8).map((item) => GestureDetector(
                              onTap: () => _addMedicine(item['name']!, item['type'] ?? 'TAB'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: TxTheme.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(item['name']!, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: TxTheme.textMain)),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: TxTheme.primary.withAlpha(8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.medication_rounded, size: 34, color: TxTheme.primary.withAlpha(80)),
          ),
          const SizedBox(height: 16),
          Text("Select a medicine",
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: TxTheme.textSub)),
          const SizedBox(height: 6),
          Text("Search or tap a suggestion on the left",
            style: TextStyle(fontSize: 11, color: TxTheme.textSub.withAlpha(150))),
          const SizedBox(height: 24),
          Icon(Icons.arrow_back_rounded, size: 18, color: TxTheme.textSub.withAlpha(100)),
        ],
      ),
    );
  }

  Widget _buildEditorCockpit() {
    final med = _selectedMedicine!;
    List<String> currentDoseOptions;
    if (med.type == "SYRUP" || med.type == "SUSP" || med.type == "DROP" || med.unit == "ml") {
      currentDoseOptions = ["5", "10", "15", "20", "30", "40", "50", "60", "70"];
    } else if (med.type == "INJ" || med.unit == "inj" || med.unit == "amp") {
      currentDoseOptions = ["1", "2", "3", "4", "5", "10"];
    } else {
      currentDoseOptions = _doseOptions;
    }

    return Column(
      children: [
        // ── Header ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: TxTheme.primary.withAlpha(12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medication_rounded, color: TxTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              // Name + dropdowns
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(med.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 18, color: TxTheme.textMain)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Type
                        // Type Selector (Tab Format)
                        Expanded(
                          child: Container(
                            height: 38,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: ["TAB","CAP","SYRUP","SUSP","DROP","INJ","CREAM","OINT"].map((type) {
                                bool isSelected = med.type.toUpperCase() == type;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        med.type = type;
                                        // Auto-update units/dosages based on type
                                        if (type == "SYRUP" || type == "SUSP" || type == "DROP") {
                                          med.unit = "ml";
                                          if (!["5", "10", "15", "20", "30", "40", "50", "60", "70"].contains(med.dosage)) {
                                            med.dosage = "10";
                                          }
                                        } else if (type == "TAB") {
                                          med.unit = "tab";
                                          if (!["1/4", "1/2", "1", "1½", "2", "3"].contains(med.dosage)) {
                                            med.dosage = "1";
                                          }
                                        } else if (type == "CAP") {
                                          med.unit = "cap";
                                          if (!["1/4", "1/2", "1", "1½", "2", "3"].contains(med.dosage)) {
                                            med.dosage = "1";
                                          }
                                        } else if (type == "INJ") {
                                          med.unit = "inj";
                                          if (!["1", "2", "3", "4", "5", "10"].contains(med.dosage)) {
                                            med.dosage = "1";
                                          }
                                        }
                                      });
                                      _autoSave();
                                      // REMEMBER TYPE PREFERENCE
                                      MasterDataService().saveMedicine(med.name, type, med.unit);
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isSelected ? TxTheme.primary : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isSelected ? TxTheme.primary : Colors.transparent),
                                      ),
                                      child: Text(type, style: GoogleFonts.poppins(
                                        fontSize: 11, 
                                        fontWeight: FontWeight.w700, 
                                        color: isSelected ? Colors.white : TxTheme.textSub
                                      )),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Unit
                        _buildHeaderDropdown(
                          value: med.unit.isNotEmpty ? med.unit : null,
                          items: ["mg","ml","mcg","tab","cap","tsp","drop","IU","inj","amp", if (med.unit.isNotEmpty && !["mg","ml","mcg","tab","cap","tsp","drop","IU","inj","amp"].contains(med.unit)) med.unit, "Other..."],
                          hint: "UNIT",
                          bgColor: TxTheme.primary.withAlpha(10),
                          textColor: TxTheme.primary,
                          onChanged: (v) { 
                            if (v == "Other...") {
                              _showCustomUnitDialog(context, (customUnit) {
                                setState(() => med.unit = customUnit);
                                _autoSave();
                                MasterDataService().saveMedicine(med.name, med.type, customUnit);
                              });
                            } else if (v != null) {
                              setState(() => med.unit = v); 
                              _autoSave();
                              MasterDataService().saveMedicine(med.name, med.type, v);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Delete
              GestureDetector(
                onTap: () => _removeMedicine(med),
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withAlpha(30)),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                ),
              ),
            ],
          ),
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildSectionTitle("DOSAGE PER INTAKE (${med.unit.toUpperCase()})", Icons.pie_chart_outline_rounded),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...currentDoseOptions.map((dose) {
                  bool isSelected = med.dosage == dose;
                  return InkWell(
                    onTap: () { setState(() => med.dosage = dose); _autoSave(); },
                    child: Container(
                      width: 54, height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: isSelected ? TxTheme.primary : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? TxTheme.primary : TxTheme.border, width: isSelected ? 2 : 1),
                          boxShadow: isSelected ? [BoxShadow(color: TxTheme.primary.withAlpha(50), blurRadius: 10, offset: const Offset(0,4))] : []
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(dose, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isSelected ? Colors.white : TxTheme.textMain)),
                          Text(med.unit, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: isSelected ? Colors.white.withAlpha(180) : TxTheme.textSub)),
                        ],
                      ),
                    ),
                  );
                }),
                // Custom Dosage Input (Labeled)
                Container(
                  width: 90, height: 54,
                  decoration: BoxDecoration(
                    color: !currentDoseOptions.contains(med.dosage) ? TxTheme.primary.withAlpha(10) : Colors.white,
                    borderRadius: BorderRadius.circular(27),
                    border: Border.all(color: !currentDoseOptions.contains(med.dosage) ? TxTheme.primary : TxTheme.border, width: 1.5)
                  ),
                  alignment: Alignment.center,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: !currentDoseOptions.contains(med.dosage) ? med.dosage : null,
                      hint: const Text("Custom", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TxTheme.primary)),
                      icon: const SizedBox.shrink(),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      menuMaxHeight: 300,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: TxTheme.primary),
                      items: List.generate(100, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(
                        value: v, 
                        child: Center(child: Text(v))
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            med.dosage = v;
                            _customDosageController.text = v;
                          });
                          _autoSave();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
              const SizedBox(height: 32),
              _buildSectionTitle("TIMING & FREQUENCY", Icons.access_time),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildModernTimingBlock("Breakfast", Icons.wb_twilight_rounded, med,
                      med.timing.beforeBreakfast, med.timing.afterBreakfast,
                          (v) { setState(() => med.timing.beforeBreakfast = v); _autoSave(); },
                          (v) { setState(() => med.timing.afterBreakfast = v); _autoSave(); }
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _buildModernTimingBlock("Lunch", Icons.wb_sunny_rounded, med,
                      med.timing.beforeLunch, med.timing.afterLunch,
                          (v) { setState(() => med.timing.beforeLunch = v); _autoSave(); },
                          (v) { setState(() => med.timing.afterLunch = v); _autoSave(); }
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _buildModernTimingBlock("Dinner", Icons.nights_stay_rounded, med,
                      med.timing.beforeDinner, med.timing.afterDinner,
                          (v) { setState(() => med.timing.beforeDinner = v); _autoSave(); },
                          (v) { setState(() => med.timing.afterDinner = v); _autoSave(); }
                  )),
                ],
              ),
              const SizedBox(height: 32),
              _buildSectionTitle("DURATION", Icons.calendar_today_outlined),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ..._durationOptions.map((dur) {
                    bool isSelected = med.duration == dur;
                    return InkWell(
                      onTap: () { setState(() => med.duration = dur); _autoSave(); },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? TxTheme.textMain : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? TxTheme.textMain : TxTheme.border),
                        ),
                        child: Text(dur, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSelected ? Colors.white : TxTheme.textSub)),
                      ),
                    );
                  }).toList(),
                  // Custom Duration Input (Boxed with Units)
                  Container(
                    width: 130, // Wider for units
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(8), 
                      border: Border.all(color: TxTheme.border, width: 1.5)
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _customDurationController.text.isNotEmpty ? _customDurationController.text : null,
                                hint: const Text("...", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                icon: const SizedBox.shrink(),
                                dropdownColor: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                menuMaxHeight: 300,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: TxTheme.textMain),
                                items: List.generate(60, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(
                                  value: v, 
                                  child: Center(child: Text(v))
                                )).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      _customDurationController.text = v;
                                      med.duration = "$v$_customDurationUnit";
                                    });
                                    _autoSave();
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        // Unit Selector (D/M/Y)
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _customDurationUnit,
                            isDense: true,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: TxTheme.primary),
                            items: ['d', 'm', 'y'].map((u) => DropdownMenuItem(value: u, child: Text(u.toUpperCase()))).toList(),
                            onChanged: (val) {
                              if(val != null) {
                                setState(() {
                                  _customDurationUnit = val;
                                  med.duration = "${_customDurationController.text}$val";
                                });
                                _autoSave();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle("INSTRUCTIONS / NOTES", Icons.sticky_note_2_outlined),
                  // QUICK SHORTCUTS
                  Container(
                    height: 28,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      children: [
                        _buildNoteShortcut("Once a week", med),
                        _buildNoteShortcut("Once a day", med),
                        _buildNoteShortcut("Once a month", med),
                        _buildNoteShortcut("STAT dose", med),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _noteController.clear();
                              med.note = "";
                            });
                            _autoSave();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.red.withAlpha(20), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.withAlpha(40))),
                            child: const Text("CLEAR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: TxTheme.border)),
                child: TextField(
                  controller: _noteController,
                  onChanged: (val) { med.note = val; _autoSave(); },
                  maxLines: 2,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                      hintText: "e.g. Take with warm water...",
                      hintStyle: TextStyle(color: Colors.black26),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16)
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderDropdown({
    required String? value,
    required List<String> items,
    required String hint,
    required Color bgColor,
    required Color textColor,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(7)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor.withAlpha(160))),
          isDense: true,
          iconSize: 16,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textColor),
          items: items.map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: TxTheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TxTheme.textSub, letterSpacing: 1.0)),
      ],
    );
  }

  Widget _buildModernTimingBlock(String label, IconData icon, PrescriptionEntry med, String beforeVal, String afterVal, Function(String) setBefore, Function(String) setAfter) {
    bool isBeforeActive = beforeVal != "0";
    bool isAfterActive = afterVal != "0";
    bool isAnyActive = isBeforeActive || isAfterActive;
    String activeDose = isBeforeActive ? beforeVal : (isAfterActive ? afterVal : med.dosage);

    List<String> doseOptions;
    if (med.type == "SYRUP" || med.type == "SUSP" || med.type == "DROP" || med.unit == "ml" || med.unit == "tsp" || med.unit == "drop") {
      doseOptions = ["0.5", "1", "2", "2.5", "5", "7.5", "10", "15", "20", "30", "40", "50"];
    } else if (med.type == "INJ" || med.unit == "inj" || med.unit == "amp") {
      doseOptions = ["0.5", "1", "2", "3", "4", "5", "10"];
    } else {
      doseOptions = ["0.25", "0.5", "1", "1.5", "2", "3", "4"];
    }

    if (!doseOptions.contains(activeDose)) {
      doseOptions.add(activeDose);
    }

    // Dropdown items
    List<DropdownMenuItem<String>> menuItems = doseOptions.map((val) => DropdownMenuItem<String>(
      value: val,
      child: Text("$val ${med.unit}"),
    )).toList();
    
    menuItems.add(const DropdownMenuItem<String>(
      value: "custom",
      child: Text("Custom...", style: TextStyle(color: TxTheme.primary, fontWeight: FontWeight.bold)),
    ));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TxTheme.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: isAnyActive ? TxTheme.primary : TxTheme.textSub, size: 20),
                if (isAnyActive)
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: TxTheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: activeDose,
                        isDense: true,
                        icon: const Icon(Icons.arrow_drop_down, size: 14, color: TxTheme.primary),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TxTheme.primary),
                        dropdownColor: Colors.white,
                        items: menuItems,
                        onChanged: (val) {
                          if (val == "custom") {
                            _showCustomDosageDialog(context, med.unit, (customVal) {
                              if (isBeforeActive) setBefore(customVal);
                              if (isAfterActive) setAfter(customVal);
                            });
                          } else if (val != null) {
                            if (isBeforeActive) setBefore(val);
                            if (isAfterActive) setAfter(val);
                          }
                        },
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 24), // Consistent layout height
              ],
            ),
          ),
          const Divider(height: 1, color: TxTheme.border),
          Row(
            children: [
              Expanded(
                child: _buildTimeToggle(
                  "Before",
                  isBeforeActive,
                  () {
                    if (isBeforeActive) {
                      setBefore("0");
                    } else {
                      setBefore(activeDose);
                      setAfter("0");
                    }
                  },
                ),
              ),
              Container(width: 1, height: 35, color: TxTheme.border),
              Expanded(
                child: _buildTimeToggle(
                  "After",
                  isAfterActive,
                  () {
                    if (isAfterActive) {
                      setAfter("0");
                    } else {
                      setAfter(activeDose);
                      setBefore("0");
                    }
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTimeToggle(String text, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 35,
        alignment: Alignment.center,
        color: isActive ? TxTheme.primary : Colors.transparent,
        child: Text(text, style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? Colors.white : TxTheme.textSub
        )),
      ),
    );
  }

  Widget _buildNoteShortcut(String label, PrescriptionEntry med) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () {
          setState(() {
            _noteController.text = label;
            med.note = label;
          });
          _autoSave();
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TxTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TxTheme.primary.withAlpha(20)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: TxTheme.primary)),
        ),
      ),
    );
  }

  // --- NEW: PROFESSIONAL SCROLL PICKER ---
  void _showScrollPicker({
    required String title,
    required List<String> options,
    required String initialValue,
    required Function(String) onSelect,
  }) {
    int initialIndex = options.indexOf(initialValue);
    if (initialIndex == -1) initialIndex = 0;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          height: 350,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: TxTheme.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Select $title", style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("DONE", style: TextStyle(fontWeight: FontWeight.bold, color: TxTheme.primary)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 50,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) => onSelect(options[index]),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: options.length,
                    builder: (context, index) {
                      return Center(
                        child: Text(
                          options[index],
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: TxTheme.textMain),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBulkDurationDialog() {
    String selectedNum = "5";
    String selectedUnit = "d";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.auto_fix_high_rounded, color: TxTheme.primary),
                  const SizedBox(width: 10),
                  Text("Bulk Duration", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Apply this duration to ALL selected medicines:", style: TextStyle(fontSize: 13, color: TxTheme.textSub)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Number Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedNum,
                            items: List.generate(60, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                            onChanged: (v) { if(v!=null) setDialogState(() => selectedNum = v); },
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      // Unit Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: TxTheme.primary.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedUnit,
                            items: ['d', 'm', 'y'].map((u) => DropdownMenuItem(value: u, child: Text(u.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: TxTheme.primary)))).toList(),
                            onChanged: (v) { if(v!=null) setDialogState(() => selectedUnit = v); },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: TxTheme.textSub))),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      final newDur = "$selectedNum$selectedUnit";
                      for (var med in _currentPrescription) {
                        med.duration = newDur;
                      }
                      // Update UI controllers if a medicine is currently selected
                      if (_selectedMedicine != null) {
                        _customDurationController.text = selectedNum;
                        _customDurationUnit = selectedUnit;
                      }
                    });
                    _autoSave();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Duration set to $selectedNum${selectedUnit.toUpperCase()} for all medicines"), behavior: SnackBarBehavior.floating),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: TxTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("APPLY TO ALL"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showCustomDosageDialog(BuildContext context, String unit, Function(String) onConfirm) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Custom Dosage ($unit)", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: "Enter dosage (e.g. 2.5, 12, 50)",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () {
                final val = controller.text.trim();
                if (val.isNotEmpty) {
                  onConfirm(val);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TxTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("SAVE"),
            ),
          ],
        );
      },
    );
  }

  void _showCustomUnitDialog(BuildContext context, Function(String) onConfirm) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Custom Unit", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              hintText: "Enter unit (e.g. puff, sachet, patch)",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () {
                final val = controller.text.trim().toLowerCase();
                if (val.isNotEmpty) {
                  onConfirm(val);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TxTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("SAVE"),
            ),
          ],
        );
      },
    );
  }
}
