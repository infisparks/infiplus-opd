import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../services/server_data_service.dart';
import '../supabase_handler.dart';
import '../services/master_data_service.dart'; // NEW
import 'full_screen_search.dart';
import 'package:intl/intl.dart';


class DiagnosisTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const DiagnosisTab({super.key, required this.patient, required this.opdId});

  @override
  State<DiagnosisTab> createState() => _DiagnosisTabState();
}

class _DiagnosisTabState extends State<DiagnosisTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _selectedDiagnosis = []; // List of {'name': String, 'note': String}
  List<String> _masterDiagnosis = [];
  String _searchQuery = "";
  Timer? _debounce;
  int _leftTabIndex = 0; // 0 = Capture, 1 = History
  List<Map<String, dynamic>> _patientHistory = [];
  bool _isLoadingHistory = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchPatientHistory();
    _fetchAISuggestions(); // Initial fetch

    // Listen for external syncs/reassignments (e.g. from HistoryTab)
    ServerDataService.refreshNotifier.addListener(_refreshFromLocal);
  }

  @override
  void dispose() {
    ServerDataService.refreshNotifier.removeListener(_refreshFromLocal);
    _debounce?.cancel();
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _refreshFromLocal() async {
    if (!mounted) return;
    final serverData = await ServerDataService.fetchData(widget.opdId, 'diagnosis_data');
    final serverNotes = await ServerDataService.fetchData(widget.opdId, 'clinical_notes');
    if (serverData != null || serverNotes != null) {
      setState(() {
        _populateSelections({
          'diagnosis': serverData ?? [],
          'notes': serverNotes ?? '',
        });
      });
    }
  }

  List<String> _aiSuggestions = [];

  Future<void> _fetchAISuggestions() async {
    try {
      final symData = await ServerDataService.fetchData(widget.opdId, 'symptoms');
      
      // If no symptoms yet, just load some common diagnoses as suggestions
      if (symData == null || (symData is List && symData.isEmpty)) {
        _loadDefaultCommonDiag();
        return;
      }

      final List<Map<String, String>> sources = (symData as List).map((s) => {
        'type': 'symptom',
        'val': s['name'].toString()
      }).toList();

      final response = await SupabaseHandler.client.rpc('get_opd_suggestions', params: {
        'p_sources': sources,
        'p_target_type': 'diagnosis'
      });

      if (mounted && response != null && (response as List).isNotEmpty) {
        setState(() {
          _aiSuggestions = (response as List).map((e) => e['target_value'].toString()).toList();
        });
      } else {
        _loadDefaultCommonDiag();
      }
    } catch (e) {
      debugPrint("AI Suggestion Fetch Error: $e");
      _loadDefaultCommonDiag();
    }
  }

  void _loadDefaultCommonDiag() {
    if (_masterDiagnosis.isNotEmpty && mounted) {
      setState(() {
        _aiSuggestions = _masterDiagnosis.take(10).toList();
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Instant Memory Load
      final master = MasterDataService();
      _masterDiagnosis = master.diagnoses;
      
      // Silent Background Refresh
      master.syncWithCloud().then((_) {
        if(mounted) setState(() => _masterDiagnosis = master.diagnoses);
      });


      // 2. Load Patient Data from Server
      final localData = await ServerDataService.fetchData(widget.opdId, 'diagnosis_data');
      final localNotes = await ServerDataService.fetchData(widget.opdId, 'clinical_notes');

      if (localData != null || localNotes != null) {
        _populateSelections({
          'diagnosis': localData ?? [],
          'notes': localNotes ?? '',
        });
      }
    } catch (e) {
      debugPrint("Error loading DiagnosisTab: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPatientHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final response = await SupabaseHandler.client
          .from('opd_reg_diagnosis')
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
              'diagnosis_list_json': []
            };
          }
        }

        // Fetch the actual diagnosis for these OPDs
        if (grouped.isNotEmpty) {
          final dResponse = await SupabaseHandler.client
              .from('opd_reg_diagnosis')
              .select()
              .inFilter('opd_id', grouped.keys.toList());

          for (var d in dResponse as List) {
            int oid = d['opd_id'];
            (grouped[oid]!['diagnosis_list_json'] as List).add({
              'name': d['name'],
              'note': d['note'],
            });
          }
        }

        setState(() {
          _patientHistory = grouped.values.toList();
        });
      }
    } catch (e) {
      debugPrint("Diagnosis History Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }


  void _reassignFromHistory(List<dynamic> oldDiagnosis) {
    if (oldDiagnosis.isEmpty) return;
    setState(() {
      _selectedDiagnosis.clear(); // Clear current for clean overwrite
      for (var item in oldDiagnosis) {
        if (item is Map) {
          _selectedDiagnosis.add({
            'name': item['name']?.toString() ?? "",
            'note': item['note']?.toString() ?? "",
          });
        } else {
          _selectedDiagnosis.add({
            'name': item.toString(),
            'note': '',
          });
        }
      }
      _leftTabIndex = 0;
    });
    _autoSave();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Reassigned ${oldDiagnosis.length} from history"), behavior: SnackBarBehavior.floating),
    );
  }

  void _populateSelections(Map<String, dynamic> data) {
    try {
      final diag = data['diagnosis'];
      final notes = data['notes']?.toString() ?? '';
      
      if (notes.isNotEmpty && _notesController.text != notes) {
        _notesController.text = notes;
      }
      
      if (diag is List) {
        _selectedDiagnosis = diag.map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return {'name': e.toString(), 'note': ''};
        }).toList();
      } else if (diag is String && diag.isNotEmpty) {
        try {
          final decoded = jsonDecode(diag);
          if (decoded is List) {
            _selectedDiagnosis = decoded.map((e) {
              if (e is Map) return Map<String, dynamic>.from(e);
              return {'name': e.toString(), 'note': ''};
            }).toList();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error populating diagnosis selections: $e");
    }
  }

  void _onToggle(String diagnosisName) {
    setState(() {
      int idx = _selectedDiagnosis.indexWhere((e) => e['name'] == diagnosisName);
      if (idx != -1) {
        _selectedDiagnosis.removeAt(idx);
      } else {
        _selectedDiagnosis.add({'name': diagnosisName, 'note': ''});
      }
    });
    _autoSave();
  }

  void _autoSave() {
    setState(() => _saving = true);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      await ServerDataService.saveData(widget.opdId, 'diagnosis_data', _selectedDiagnosis, silent: true);
      if (mounted) setState(() => _saving = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Refresh suggestions whenever the tab is viewed to stay in sync with symptoms
    _fetchAISuggestions();
    
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtered = _masterDiagnosis
        .where((d) => d.toLowerCase().contains(_searchQuery.toLowerCase()))
        .where((d) => !_selectedDiagnosis.any((e) => e['name'] == d))
        .toList();

    // Pull AI Suggestions to the top of the list if searching is empty
    List<String> displayList = [];
    if (_searchQuery.isEmpty && _aiSuggestions.isNotEmpty && _leftTabIndex == 0) {
      // Show suggestions that are in master list and not yet selected
      final availableSuggestions = _aiSuggestions
          .where((s) => _masterDiagnosis.contains(s) && !_selectedDiagnosis.any((e) => e['name'] == s))
          .toList();
      
      displayList.addAll(availableSuggestions);
      displayList.addAll(filtered.where((f) => !availableSuggestions.contains(f)));
    } else {
      displayList = filtered;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          // Left Panel: Search & Master
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildCombinedHeaderTabs(),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Expanded(
                    child: _leftTabIndex == 0 ? _buildCurrentColumn(displayList) : _buildHistoryColumn(),
                  ),
                ],
              ),
            ),
          ),

          // Vertical Divider
          Container(width: 1, color: const Color(0xFFE2E8F0)),

          // Right Panel: Structured Selection & Notes
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text("DIAGNOSIS & CLINICAL NOTES", 
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.2)),
                      const Spacer(),
                      if (_saving)
                        Text("Saving...", style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_selectedDiagnosis.isEmpty)
                    _buildEmptySelectionState()
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _selectedDiagnosis.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final diag = _selectedDiagnosis[index];
                          return _buildDiagnosisNoteCard(diag, index);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => FullScreenSearchPage(
                title: "Search Diagnosis",
                hintText: "Type diagnosis name...",
                allItems: _masterDiagnosis,
                onItemSelected: (selected) {
                  if (!_masterDiagnosis.contains(selected)) {
                    _masterDiagnosis.add(selected);
                    MasterDataService().diagnoses = _masterDiagnosis;
                  }
                  if (!_selectedDiagnosis.any((e) => e['name'] == selected)) {
                    _selectedDiagnosis.add({'name': selected, 'note': ''});
                  }
                  setState(() {});
                  _autoSave();
                },
                onItemRemoved: (selected) {
                  setState(() {
                    _selectedDiagnosis.removeWhere((e) => e['name'] == selected);
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
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Search diagnosis...",
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosisItem(String name) {
    return InkWell(
      onTap: () => _onToggle(name),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(name, 
                style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            ),
            Icon(Icons.add_rounded, size: 18, color: AppColors.primary.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosisNoteCard(Map<String, dynamic> diag, int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 8, height: 24,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(diag['name'], 
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                IconButton(
                  onPressed: () => _onToggle(diag['name']),
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.danger),
                  visualDensity: VisualDensity.compact,
                )
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          // Note Input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (val) {
                diag['note'] = val;
                _autoSave();
              },
              maxLines: 2,
              minLines: 1,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
              // We don't use individual controllers to avoid overhead, initial state is key
              controller: TextEditingController.fromValue(
                TextEditingValue(
                  text: diag['note'] ?? '',
                  selection: TextSelection.collapsed(offset: (diag['note'] ?? '').length),
                ),
              ),
              decoration: InputDecoration(
                hintText: "Add observation for this diagnosis...",
                hintStyle: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedHeaderTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            Expanded(child: _buildPanelTabItem("Capture", 0)),
            Expanded(child: _buildPanelTabItem("History", 1)),
          ],
        ),
      ),
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
        child: Text(text, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 11, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildCurrentColumn(List<String> filtered) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchBar(),

          // --- SELECTED ITEMS SECTION (NOW ON TOP) ---
          if (_selectedDiagnosis.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 4, height: 16,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  Text("ACTIVE DIAGNOSES (${_selectedDiagnosis.length})",
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.5)),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _selectedDiagnosis.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final diag = _selectedDiagnosis[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text("DX",
                          style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          diag['name'] ?? '',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _onToggle(diag['name'] ?? ''),
                      ),
                    ],
                  ),
                );
              },
            ),
          ] else
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  "No items selected yet. Tap to search above.",
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            ),

          // --- AI SUGGESTIONS SECTION (NOW DOWN) ---
          if (_aiSuggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Text("AI SUGGESTED", 
                        style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF2563EB), letterSpacing: 1.1)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _aiSuggestions.map((name) {
                      bool isSelected = _selectedDiagnosis.any((e) => e['name'] == name);
                      return InkWell(
                        onTap: () => _onToggle(name),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text(name, 
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : const Color(0xFF1E293B))),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryColumn() {
    if (_isLoadingHistory) return const Center(child: CircularProgressIndicator());
    if (_patientHistory.isEmpty) return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text("No Past History", style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _patientHistory.length,
      itemBuilder: (context, index) {
        final visit = _patientHistory[index];
        final List<dynamic> oldDiag = visit['diagnosis_list_json'] ?? [];
        final date = DateTime.parse(visit['created_at']);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd MMM yyyy').format(date), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold)),
                    _buildHistoryCopyBtn(() => _reassignFromHistory(oldDiag)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: oldDiag.map((item) {
                    final isMap = item is Map;
                    final name = isMap ? (item['name']?.toString() ?? 'Unknown') : item.toString();
                    final note = isMap ? (item['note']?.toString() ?? '') : '';
                    
                    bool alreadySelected = _selectedDiagnosis.any((e) => e['name'] == name);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("• $name", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                if (note.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, top: 2),
                                    child: Text(note, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                                  ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              if (!alreadySelected) {
                                setState(() {
                                  _selectedDiagnosis.add({'name': name, 'note': note});
                                  _leftTabIndex = 0;
                                });
                                _autoSave();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Added: $name"), behavior: SnackBarBehavior.floating),
                                );
                              }
                            },
                            child: Icon(
                              alreadySelected ? Icons.check_circle_rounded : Icons.add_circle_outline, 
                              size: 18, 
                              color: alreadySelected ? AppColors.success : AppColors.primary
                            ),
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

  Widget _buildHistoryCopyBtn(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [const Icon(Icons.copy_all, size: 10, color: AppColors.primary), const SizedBox(width: 4), Text("Copy", style: GoogleFonts.poppins(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  Widget _buildEmptySelectionState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: const Icon(Icons.assignment_add, size: 48, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 24),
            Text("No Diagnosis Selected", 
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text("Select items from the left to begin\nadding clinical findings and notes.", 
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
