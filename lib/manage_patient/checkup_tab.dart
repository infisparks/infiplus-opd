import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../main.dart'; // Imports Patient Model
import '../services/server_data_service.dart';
import '../supabase_handler.dart';

// --- MODERN THEME COLORS ---
class CheckupTheme {
  static const Color primary = Color(0xFF2563EB); // Inter Blue
  static const Color background = Color(0xFFF1F5F9); // Slate 100
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF1E293B); // Slate 800
  static const Color textSub = Color(0xFF64748B); // Slate 500
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color danger = Color(0xFFEF4444); // Red
}

// --- MODELS (UNCHANGED) ---
class CheckupItemConfig {
  String section;
  String title;
  List<String> options;
  String type; // 'toggle' or 'text'

  CheckupItemConfig({
    required this.section,
    required this.title,
    required this.options,
    this.type = 'toggle',
  });

  factory CheckupItemConfig.fromJson(Map<String, dynamic> json) {
    return CheckupItemConfig(
      section: json['section'] ?? 'General',
      title: json['title'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      type: json['type'] ?? 'toggle',
    );
  }
}

class VisitType {
  String id;
  String name;
  VisitType({required this.id, required this.name});
}

// -------------------------------------------------------

class CheckupTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const CheckupTab({super.key, required this.patient, required this.opdId});

  @override
  State<CheckupTab> createState() => _CheckupTabState();
}

class _CheckupTabState extends State<CheckupTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // --- STATE ---
  String _selectedVisitId = "1m"; // Default
  bool _isLoadingMaster = true;

  // Data
  Map<String, List<CheckupItemConfig>> _masterTemplates = {};
  Map<String, String> _patientResponses = {};

  Timer? _debounce;

  // Sidebar Items
  final List<VisitType> _visits = [
    VisitType(id: "nb", name: "Newborn"),
    VisitType(id: "1m", name: "1 Month"),
    VisitType(id: "2m", name: "2 Months"),
    VisitType(id: "3m", name: "3 Months"),
    VisitType(id: "6m", name: "6 Months"),
    VisitType(id: "9m", name: "9 Months"),
    VisitType(id: "12m", name: "12 Months"),
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _loadMasterTemplates();
    await _loadPatientResponses();
  }

  // --- 1. LOAD TEMPLATES ---
  Future<void> _loadMasterTemplates() async {
    try {
      final response = await SupabaseHandler.client
          .from('opd_datasets')
          .select('datajson')
          .eq('dataname', 'CheckupTemplates')
          .maybeSingle();

      if (response != null && response['datajson'] != null) {
        if (mounted) {
          _parseTemplates(response['datajson']);
          setState(() => _isLoadingMaster = false);
        }
      } else {
        if (mounted) setState(() => _isLoadingMaster = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMaster = false);
    }
  }

  void _parseTemplates(Map<String, dynamic> json) {
    _masterTemplates.clear();
    json.forEach((visitId, questionsList) {
      if (questionsList is List) {
        _masterTemplates[visitId] = questionsList
            .map((q) => CheckupItemConfig.fromJson(q))
            .toList();
      }
    });
  }

  // --- 2. LOAD RESPONSES (UPDATED) ---
  Future<void> _loadPatientResponses() async {
    // Fetch from Cloud (Background)
    final serverData = await ServerDataService.fetchData(widget.opdId, 'checkup_data');
    if (serverData != null && mounted) {
      setState(() {
        _patientResponses = Map<String, String>.from(serverData);
      });
    }
  }

  // --- 3. AUTO SAVE ---
  void _saveResponse(String title, String value) {
    setState(() {
      _patientResponses[title] = value;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 1), () {
      ServerDataService.saveData(widget.opdId, 'checkup_data', _patientResponses, silent: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingMaster && _masterTemplates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentQuestions = _masterTemplates[_selectedVisitId] ?? [];
    final sections = <String, List<CheckupItemConfig>>{};
    for (var q in currentQuestions) {
      if (!sections.containsKey(q.section)) sections[q.section] = [];
      sections[q.section]!.add(q);
    }

    return Scaffold(
      backgroundColor: CheckupTheme.background,
      body: Row(
        children: [
          // LEFT SIDEBAR (Timeline Style)
          Container(
            width: 140,
            decoration: const BoxDecoration(
              color: CheckupTheme.surface,
              border: Border(right: BorderSide(color: CheckupTheme.border)),
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("VISIT STAGES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: CheckupTheme.textSub, letterSpacing: 1.0)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _visits.length,
                    itemBuilder: (context, index) {
                      final visit = _visits[index];
                      bool isSelected = visit.id == _selectedVisitId;

                      return InkWell(
                        onTap: () => setState(() => _selectedVisitId = visit.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          decoration: BoxDecoration(
                              color: isSelected ? CheckupTheme.primary.withOpacity(0.05) : Colors.transparent,
                              border: Border(left: BorderSide(color: isSelected ? CheckupTheme.primary : Colors.transparent, width: 3))
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 14, color: isSelected ? CheckupTheme.primary : CheckupTheme.textSub),
                              const SizedBox(width: 10),
                              Text(
                                visit.name,
                                style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? CheckupTheme.primary : CheckupTheme.textMain,
                                    fontSize: 13
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // RIGHT CONTENT
          Expanded(
            child: Container(
              color: CheckupTheme.background,
              child: currentQuestions.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                padding: const EdgeInsets.all(24),
                children: sections.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section Header
                      Row(
                        children: [
                          Container(width: 4, height: 16, color: CheckupTheme.textSub, margin: const EdgeInsets.only(right: 8)),
                          Text(
                            entry.key.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: CheckupTheme.textMain, letterSpacing: 1.2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Grid of Modern Cards
                      LayoutBuilder(builder: (ctx, constraints) {
                        int cols = constraints.maxWidth > 800 ? 3 : 2;
                        return Wrap(
                          spacing: 16, runSpacing: 16,
                          children: entry.value.map((q) {
                            double w = (constraints.maxWidth - ((cols-1)*16)) / cols;
                            return SizedBox(width: w, child: _buildModernQuestionCard(q));
                          }).toList(),
                        );
                      }),
                      const SizedBox(height: 40),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 48, color: Colors.blueGrey.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text("No template configured", style: TextStyle(fontSize: 16, color: CheckupTheme.textSub)),
        ],
      ),
    );
  }

  Widget _buildModernQuestionCard(CheckupItemConfig item) {
    String? currentVal = _patientResponses[item.title];
    bool hasValue = currentVal != null && currentVal.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CheckupTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasValue ? CheckupTheme.primary.withOpacity(0.2) : CheckupTheme.border),
        
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CheckupTheme.textMain),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if(hasValue)
                const Icon(Icons.check_circle, size: 14, color: CheckupTheme.success)
            ],
          ),
          const SizedBox(height: 16),

          if (item.type == 'text')
          // TEXT INPUT
            Container(
              decoration: BoxDecoration(
                color: CheckupTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: TextEditingController(text: currentVal)
                  ..selection = TextSelection.fromPosition(TextPosition(offset: currentVal?.length ?? 0)),
                onChanged: (val) => _saveResponse(item.title, val),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Enter value...",
                  hintStyle: TextStyle(color: CheckupTheme.textSub.withOpacity(0.5), fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            )
          else
          // MODERN PILL TOGGLES
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: CheckupTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                children: item.options.map((option) {
                  bool isSelected = currentVal == option;

                  // Dynamic Color Logic
                  Color activeBg = CheckupTheme.surface;
                  Color activeText = CheckupTheme.textMain;

                  if(isSelected) {
                    if(["No", "Normal", "Absent", "Done"].contains(option)) {
                      activeBg = CheckupTheme.success;
                      activeText = Colors.white;
                    } else if(["Yes", "Abnormal", "Present"].contains(option)) {
                      activeBg = CheckupTheme.danger;
                      activeText = Colors.white;
                    } else {
                      activeBg = CheckupTheme.primary;
                      activeText = Colors.white;
                    }
                  }

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _saveResponse(item.title, option),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: isSelected ? activeBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0,1))] : []
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? activeText : CheckupTheme.textSub
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            )
        ],
      ),
    );
  }
}