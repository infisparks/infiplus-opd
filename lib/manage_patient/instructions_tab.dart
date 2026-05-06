import 'dart:async'; // For Debounce Timer
import 'dart:convert'; // For JSON
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Local DB
import '../supabase_handler.dart';
import '../services/master_data_service.dart'; // NEW
import '../main.dart'; // Imports Patient Model
import '../services/server_data_service.dart'; // For Sync Logic
import 'full_screen_search.dart';


// --- MODERN UI COLORS ---
class InstTheme {
  static const Color primary = Color(0xFF2563EB); // Royal Blue
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF0F172A); // Slate 900
  static const Color textSub = Color(0xFF64748B); // Slate 500
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color accent = Color(0xFF6366F1); // Indigo
  static const Color success = Color(0xFF10B981); // Emerald
}

class InstructionsTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const InstructionsTab({
    super.key,
    required this.patient,
    required this.opdId
  });

  @override
  State<InstructionsTab> createState() => _InstructionsTabState();
}

class _InstructionsTabState extends State<InstructionsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // --- UI STATE ---
  int _selectedSubTab = 0; // 0: Instructions, 1: Investigations, 2: Procedures
  String _searchQuery = "";
  bool _isLoadingMaster = true;

  // --- DATA LISTS ---
  List<String> _instructionsList = [];
  List<String> _investigationsList = [];
  List<String> _proceduresList = [];

  // --- SELECTIONS ---
  final Set<String> _selectedInstructions = {};
  final Set<String> _selectedInvestigations = {};
  final Set<String> _selectedProcedures = {};

  // --- HELPERS ---
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

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
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _refreshFromLocal() async {
    if (!mounted) return;
    final serverData = await ServerDataService.fetchData(widget.opdId, 'instructions_data');
    if (serverData != null) {
      setState(() {
         _populateSelections(serverData);
      });
    }
  }

  Future<void> _loadAllData() async {
    await _loadMasterData();
    await _loadPatientData();
  }

  // ==========================================
  // 1. MASTER DATA LOGIC
  // ==========================================
  Future<void> _loadMasterData() async {
    final master = MasterDataService();
    await master.loadUsageRanks(); // LOAD RANKS FIRST
    setState(() {
      _instructionsList = master.instructions;
      _investigationsList = master.investigations;
      _proceduresList = master.procedures;
      _isLoadingMaster = false;
    });

    // Background Refresh (Silent)
    master.syncWithCloud().then((_) {
      if (mounted) {
        setState(() {
          _instructionsList = master.instructions;
          _investigationsList = master.investigations;
          _proceduresList = master.procedures;
        });
      }
    });
  }



  // ==========================================
  // 2. PATIENT DATA LOGIC
  // ==========================================
  Future<void> _loadPatientData() async {
    final serverData = await ServerDataService.fetchData(widget.opdId, 'instructions_data');
    if (mounted && serverData != null) {
      setState(() => _populateSelections(serverData));
    }
  }

  void _populateSelections(dynamic data) {
    if (data == null || data is! Map) return;

    _selectedInstructions.clear();
    _selectedInvestigations.clear();
    _selectedProcedures.clear();

    if (data['instructions'] is List) _selectedInstructions.addAll(List<String>.from(data['instructions']));
    if (data['investigations'] is List) _selectedInvestigations.addAll(List<String>.from(data['investigations']));
    if (data['procedures'] is List) _selectedProcedures.addAll(List<String>.from(data['procedures']));
  }

  // ==========================================
  // 3. AUTO SAVE LOGIC
  // ==========================================
  void _autoSave() {
    final payload = {
      'instructions': _selectedInstructions.toList(),
      'investigations': _selectedInvestigations.toList(),
      'procedures': _selectedProcedures.toList(),
    };

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ServerDataService.saveData(widget.opdId, 'instructions_data', payload, silent: true);
    });
  }

  // --- GETTERS ---
  List<String> get _currentList {
    List<String> source;
    String type;
    if (_selectedSubTab == 0) { source = _instructionsList; type = 'instruction'; }
    else if (_selectedSubTab == 1) { source = _investigationsList; type = 'investigation'; }
    else { source = _proceduresList; type = 'procedure'; }

    List<String> filtered = source;
    if (_searchQuery.isNotEmpty) {
      filtered = source.where((s) => s.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    
    // 1. Sort selected items to the top
    // 2. Sort by usage frequency (Most Used)
    final selectedSet = _currentSelectedSet;
    final sorted = List<String>.from(filtered);
    sorted.sort((a, b) {
      bool aSelected = selectedSet.contains(a);
      bool bSelected = selectedSet.contains(b);
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;
      
      // Secondary sort: Usage Rank
      int countA = MasterDataService().getUsageCount(type, a);
      int countB = MasterDataService().getUsageCount(type, b);
      if (countA != countB) return countB.compareTo(countA);
      
      return a.compareTo(b); // Alphabetical fallback
    });

    return sorted;
  }

  Set<String> get _currentSelectedSet {
    if (_selectedSubTab == 0) return _selectedInstructions;
    if (_selectedSubTab == 1) return _selectedInvestigations;
    return _selectedProcedures;
  }

  void _toggleSelection(String item) {
    setState(() {
      final set = _currentSelectedSet;
      if (set.contains(item)) set.remove(item);
      else {
        set.add(item);
        // TRACK USAGE (Moves to top next time)
        final type = _selectedSubTab == 0 ? 'instruction' : (_selectedSubTab == 1 ? 'investigation' : 'procedure');
        MasterDataService().trackUsage(type, item);
      }
    });
    _autoSave();
  }

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingMaster && _instructionsList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: InstTheme.background,
      body: Column(
        children: [
          // 1. Header & Tabs
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: const BoxDecoration(
              color: InstTheme.surface,
              border: Border(bottom: BorderSide(color: InstTheme.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: InstTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.assignment_outlined, color: InstTheme.accent, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("CLINICAL REPORTS & ADVICE",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: InstTheme.textSub, letterSpacing: 1.2)),
                          Text("Select instructions, labs, and procedures",
                            style: GoogleFonts.poppins(fontSize: 14, color: InstTheme.textMain, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSegmentedControl(),
                const SizedBox(height: 16),
                _buildModernSearchBar(),
              ],
            ),
          ),

          // 2. Active Selections Bar
          if (_currentSelectedSet.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: InstTheme.primary.withValues(alpha: 0.05),
                border: const Border(bottom: BorderSide(color: InstTheme.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: InstTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    "${_currentSelectedSet.length} Items Selected",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: InstTheme.primary),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _currentSelectedSet.clear();
                      });
                      _autoSave();
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          Text("Clear All", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. List Content
          Expanded(
            child: _currentList.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _currentList.length,
              separatorBuilder: (c, i) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _currentList[index];
                final isSelected = _currentSelectedSet.contains(item);
                return _buildListItem(item, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: InstTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InstTheme.border),
      ),
      child: Row(
        children: [
          _buildSegmentTab("Instructions", 0),
          _buildSegmentTab("Investigations", 1),
          _buildSegmentTab("Procedures", 2),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(String title, int index) {
    bool isSelected = _selectedSubTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedSubTab = index;
          _searchQuery = "";
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? InstTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0,2))] : [],
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? InstTheme.primary : InstTheme.textSub,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernSearchBar() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => FullScreenSearchPage(
              title: _selectedSubTab == 0
                  ? "Search Instructions"
                  : _selectedSubTab == 1
                      ? "Search Investigations"
                      : "Search Procedures",
              hintText: _selectedSubTab == 0
                  ? "Type instruction name..."
                  : _selectedSubTab == 1
                      ? "Type investigation name..."
                      : "Type procedure name...",
              allItems: _selectedSubTab == 0
                  ? _instructionsList
                  : _selectedSubTab == 1
                      ? _investigationsList
                      : _proceduresList,
              onItemSelected: (selected) {
                final type = _selectedSubTab == 0 ? 'instruction' : (_selectedSubTab == 1 ? 'investigation' : 'procedure');
                MasterDataService().trackUsage(type, selected);

                if (_selectedSubTab == 0) {
                  if (!_instructionsList.contains(selected)) {
                    _instructionsList.add(selected);
                    MasterDataService().saveDataset('instructions', _instructionsList);
                  }
                  if (!_selectedInstructions.contains(selected)) {
                    _selectedInstructions.add(selected);
                  }
                } else if (_selectedSubTab == 1) {
                  if (!_investigationsList.contains(selected)) {
                    _investigationsList.add(selected);
                    MasterDataService().saveDataset('investigations', _investigationsList);
                  }
                  if (!_selectedInvestigations.contains(selected)) {
                    _selectedInvestigations.add(selected);
                  }
                } else {
                  if (!_proceduresList.contains(selected)) {
                    _proceduresList.add(selected);
                    MasterDataService().saveDataset('procedures', _proceduresList);
                  }
                  if (!_selectedProcedures.contains(selected)) {
                    _selectedProcedures.add(selected);
                  }
                }
                setState(() {});
                _autoSave();
              },
              onItemRemoved: (selected) {
                setState(() {
                  if (_selectedSubTab == 0) {
                    _selectedInstructions.remove(selected);
                  } else if (_selectedSubTab == 1) {
                    _selectedInvestigations.remove(selected);
                  } else {
                    _selectedProcedures.remove(selected);
                  }
                });
                _autoSave();
              },
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: InstTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: InstTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: InstTheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedSubTab == 0
                    ? "Search instructions..."
                    : _selectedSubTab == 1
                        ? "Search investigations..."
                        : "Search procedures...",
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(String item, bool isSelected) {
    return InkWell(
      onTap: () => _toggleSelection(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? InstTheme.primary.withValues(alpha: 0.05) : InstTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? InstTheme.primary.withValues(alpha: 0.5) : InstTheme.border),
          boxShadow: isSelected
              ? [BoxShadow(color: InstTheme.primary.withValues(alpha: 0.1), blurRadius: 4)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 2, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: isSelected ? InstTheme.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? InstTheme.primary : Colors.grey[300]!, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? InstTheme.textMain : InstTheme.textMain.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.blueGrey.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text("No results for '$_searchQuery'", style: TextStyle(fontSize: 16, color: InstTheme.textSub, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Create & Select"),
              style: ElevatedButton.styleFrom(
                backgroundColor: InstTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final val = _searchQuery.trim();
                if (val.isNotEmpty) {
                  if (_selectedSubTab == 0) {
                    if (!_instructionsList.contains(val)) _instructionsList.add(val);
                    MasterDataService().saveDataset('instructions', _instructionsList);
                  } else if (_selectedSubTab == 1) {
                    if (!_investigationsList.contains(val)) _investigationsList.add(val);
                    MasterDataService().saveDataset('investigations', _investigationsList);
                  } else {
                    if (!_proceduresList.contains(val)) _proceduresList.add(val);
                    MasterDataService().saveDataset('procedures', _proceduresList);
                  }
                  
                  final type = _selectedSubTab == 0 ? 'instruction' : (_selectedSubTab == 1 ? 'investigation' : 'procedure');
                  MasterDataService().trackUsage(type, val);
                  
                  _toggleSelection(val);
                  setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  });
                }
              },
            )
          ],
        ),
      );
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.format_list_bulleted_rounded, size: 48, color: Colors.blueGrey.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            "No items found",
            style: TextStyle(fontSize: 16, color: InstTheme.textSub, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            "Try searching for something else",
            style: TextStyle(fontSize: 12, color: InstTheme.textSub.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}