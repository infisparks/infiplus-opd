import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../main.dart'; // Imports Patient model
import '../services/server_data_service.dart'; // Import Server Service

// --- MODERN THEME COLORS ---
class FitTheme {
  static const Color primary = Color(0xFF2563EB); // Royal Blue
  static const Color background = Color(0xFFF1F5F9); // Slate 100
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF1E293B); // Slate 800
  static const Color textSub = Color(0xFF64748B); // Slate 500
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color dietColor = Color(0xFFEA580C); // Orange for Diet
  static const Color exerciseColor = Color(0xFF0891B2); // Cyan for Exercise
}

// --- DATA MODELS ---

enum PlanType { diet, exercise }

class DietEntry {
  String timeSlot;
  String description;
  DietEntry({required this.timeSlot, required this.description});

  Map<String, dynamic> toJson() => {'timeSlot': timeSlot, 'description': description};

  factory DietEntry.fromJson(Map<String, dynamic> json) {
    return DietEntry(timeSlot: json['timeSlot'] ?? '', description: json['description'] ?? '');
  }
}

class ExerciseEntry {
  String activity;
  int durationMinutes;
  String? note;
  ExerciseEntry({required this.activity, required this.durationMinutes, this.note});

  Map<String, dynamic> toJson() => {'activity': activity, 'durationMinutes': durationMinutes, 'note': note};

  factory ExerciseEntry.fromJson(Map<String, dynamic> json) {
    return ExerciseEntry(
      activity: json['activity'] ?? '',
      durationMinutes: json['durationMinutes'] ?? 0,
      note: json['note'],
    );
  }
}

class FitnessPlan {
  String id;
  String title;
  PlanType type;
  bool isAssigned;

  List<DietEntry>? dietEntries;
  List<ExerciseEntry>? exerciseEntries;

  FitnessPlan({
    required this.id,
    required this.title,
    required this.type,
    this.isAssigned = false,
    this.dietEntries,
    this.exerciseEntries,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'type': type.toString(), 'isAssigned': isAssigned,
    'dietEntries': dietEntries?.map((e) => e.toJson()).toList(),
    'exerciseEntries': exerciseEntries?.map((e) => e.toJson()).toList(),
  };

  factory FitnessPlan.fromJson(Map<String, dynamic> json) {
    PlanType pType = PlanType.diet;
    if (json['type'].toString().contains('exercise')) pType = PlanType.exercise;

    return FitnessPlan(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] ?? '',
      type: pType,
      isAssigned: json['isAssigned'] ?? false,
      dietEntries: (json['dietEntries'] as List?)?.map((e) => DietEntry.fromJson(e)).toList(),
      exerciseEntries: (json['exerciseEntries'] as List?)?.map((e) => ExerciseEntry.fromJson(e)).toList(),
    );
  }
}

// -------------------------------------------------------

class FitnessTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const FitnessTab({super.key, required this.patient, required this.opdId});

  @override
  State<FitnessTab> createState() => _FitnessTabState();
}

class _FitnessTabState extends State<FitnessTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // --- STATE ---
  String? _selectedPlanId;
  bool _isEditing = false;
  Timer? _debounce;

  // --- DATA ---
  List<FitnessPlan> _plans = [
    FitnessPlan(
        id: "d1", title: "Standard 1500 kcal", type: PlanType.diet,
        dietEntries: [
          DietEntry(timeSlot: "Pre-Breakfast", description: "Warm water + Lemon, 5 Soaked Almonds"),
          DietEntry(timeSlot: "Breakfast", description: "2 Idli / 1 Dosa with Sambhar (No chutney)"),
          DietEntry(timeSlot: "Lunch", description: "1 Cup Brown Rice, 1 Cup Dal, Green Salad"),
          DietEntry(timeSlot: "Dinner", description: "2 Roti, Grilled Veggies/Paneer"),
        ]
    ),
    FitnessPlan(
        id: "d2", title: "Gestational Diabetes", type: PlanType.diet,
        dietEntries: [
          DietEntry(timeSlot: "Breakfast", description: "Oats Porridge (Unsweetened)"),
          DietEntry(timeSlot: "Mid-Morning", description: "1 Apple / Guava"),
          DietEntry(timeSlot: "Lunch", description: "Low GI Rice (1/2 cup), Veggies (2 cups)"),
        ]
    ),
    FitnessPlan(id: "d3", title: "High Protein", type: PlanType.diet, dietEntries: []),
    FitnessPlan(
        id: "e1", title: "Basic Cardio", type: PlanType.exercise,
        exerciseEntries: [
          ExerciseEntry(activity: "Walking", durationMinutes: 30, note: "Brisk pace"),
          ExerciseEntry(activity: "Yoga", durationMinutes: 20),
        ]
    ),
    FitnessPlan(id: "e2", title: "Weight Loss", type: PlanType.exercise, exerciseEntries: []),
  ];

  @override
  void initState() {
    super.initState();
    if (_plans.isNotEmpty) _selectedPlanId = _plans[0].id;
    _loadSavedData();
  }

  // --- 1. LOAD DATA (UPDATED) ---
  Future<void> _loadSavedData() async {
    // Fetch from Cloud (Background)
    final serverData = await ServerDataService.fetchData(widget.opdId, 'fitness_data');
    if (mounted && serverData != null && serverData is List) {
      setState(() => _mergeSavedData(serverData));
    }
  }

  void _mergeSavedData(List<dynamic> jsonList) {
    for (var json in jsonList) {
      FitnessPlan savedPlan = FitnessPlan.fromJson(json);
      int index = _plans.indexWhere((p) => p.id == savedPlan.id);

      if (index != -1) {
        // Update existing plan
        _plans[index] = savedPlan;
      } else {
        // Add new custom plan
        _plans.add(savedPlan);
      }
    }
  }

  // --- 2. AUTO SAVE ---
  void _autoSave() {
    final assignedPlans = _plans.where((p) => p.isAssigned).toList();
    final jsonList = assignedPlans.map((p) => p.toJson()).toList();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 1), () {
      ServerDataService.saveData(widget.opdId, 'fitness_data', jsonList);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // --- ACTIONS ---
  void _toggleAssign() {
    setState(() {
      var plan = _plans.firstWhere((p) => p.id == _selectedPlanId);
      plan.isAssigned = !plan.isAssigned;
    });
    _autoSave();
  }

  void _deletePlanItem(int index) {
    setState(() {
      var plan = _plans.firstWhere((p) => p.id == _selectedPlanId);
      if (plan.type == PlanType.diet) plan.dietEntries?.removeAt(index);
      else plan.exerciseEntries?.removeAt(index);
    });
    _autoSave();
  }

  void _addItemToPlan() {
    setState(() {
      var plan = _plans.firstWhere((p) => p.id == _selectedPlanId);
      if (plan.type == PlanType.diet) {
        plan.dietEntries ??= [];
        plan.dietEntries!.add(DietEntry(timeSlot: "Snack", description: ""));
      } else {
        plan.exerciseEntries ??= [];
        plan.exerciseEntries!.add(ExerciseEntry(activity: "New Activity", durationMinutes: 15));
      }
      _isEditing = true;
    });
    _autoSave();
  }

  FitnessPlan? get _selectedPlan => _plans.firstWhere((p) => p.id == _selectedPlanId, orElse: () => _plans[0]);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: FitTheme.background,
      body: Row(
        children: [
          // --- LEFT SIDEBAR (Plan Library) ---
          Container(
            width: 300,
            decoration: const BoxDecoration(
                color: FitTheme.surface,
                border: Border(right: BorderSide(color: FitTheme.border))
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FitTheme.border))),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: FitTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.library_books_rounded, size: 18, color: FitTheme.primary),
                      ),
                      const SizedBox(width: 12),
                      const Text("Wellness Plans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: FitTheme.textMain)),
                    ],
                  ),
                ),

                // Search
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                        hintText: "Filter templates...",
                        hintStyle: TextStyle(fontSize: 13, color: FitTheme.textSub.withOpacity(0.7)),
                        prefixIcon: const Icon(Icons.search, color: FitTheme.textSub, size: 18),
                        filled: true, fillColor: FitTheme.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0)
                    ),
                  ),
                ),

                // List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSectionLabel("DIET & NUTRITION"),
                      ..._plans.where((p) => p.type == PlanType.diet).map((p) => _buildPlanCard(p)),

                      const SizedBox(height: 24),

                      _buildSectionLabel("PHYSICAL ACTIVITY"),
                      ..._plans.where((p) => p.type == PlanType.exercise).map((p) => _buildPlanCard(p)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- RIGHT CONTENT (Editor) ---
          Expanded(
            child: _selectedPlanId == null
                ? const Center(child: Text("Select a plan to view details"))
                : _buildEditorPanel(),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4, left: 4),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: FitTheme.textSub, letterSpacing: 1.0)),
    );
  }

  Widget _buildPlanCard(FitnessPlan plan) {
    bool isSelected = plan.id == _selectedPlanId;
    Color accent = plan.type == PlanType.diet ? FitTheme.dietColor : FitTheme.exerciseColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedPlanId = plan.id;
            _isEditing = false;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? accent.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? accent : FitTheme.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: FitTheme.border)),
                child: Icon(
                    plan.type == PlanType.diet ? Icons.restaurant_menu_rounded : Icons.directions_run_rounded,
                    size: 16, color: accent
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: FitTheme.textMain)),
                    const SizedBox(height: 2),
                    Text(
                        plan.type == PlanType.diet
                            ? "${plan.dietEntries?.length ?? 0} meals"
                            : "${plan.exerciseEntries?.length ?? 0} activities",
                        style: const TextStyle(fontSize: 11, color: FitTheme.textSub)
                    ),
                  ],
                ),
              ),
              if (plan.isAssigned)
                const Icon(Icons.check_circle, size: 16, color: FitTheme.success)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorPanel() {
    final plan = _selectedPlan!;
    Color accent = plan.type == PlanType.diet ? FitTheme.dietColor : FitTheme.exerciseColor;

    return Column(
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: const BoxDecoration(
              color: FitTheme.surface,
              border: Border(bottom: BorderSide(color: FitTheme.border))
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(plan.type == PlanType.diet ? "NUTRITION PLAN" : "WORKOUT PLAN", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent, letterSpacing: 1.2)),
                        const SizedBox(width: 8),
                        if(plan.isAssigned)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: FitTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                            child: const Text("ASSIGNED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: FitTheme.success)),
                          )
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(plan.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: FitTheme.textMain)),
                  ],
                ),
              ),

              OutlinedButton.icon(
                onPressed: () => setState(() => _isEditing = !_isEditing),
                icon: Icon(_isEditing ? Icons.check : Icons.edit_outlined, size: 16),
                label: Text(_isEditing ? "Done Editing" : "Customize"),
                style: OutlinedButton.styleFrom(
                    foregroundColor: FitTheme.textMain,
                    side: const BorderSide(color: FitTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _toggleAssign,
                icon: Icon(plan.isAssigned ? Icons.close : Icons.add, size: 16),
                label: Text(plan.isAssigned ? "Unassign" : "Assign Plan"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: plan.isAssigned ? Colors.white : FitTheme.primary,
                    foregroundColor: plan.isAssigned ? Colors.red : Colors.white,
                    elevation: 0,
                    side: plan.isAssigned ? BorderSide(color: Colors.red.withOpacity(0.2)) : null,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
                ),
              ),
            ],
          ),
        ),

        // Scrollable Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plan.type == PlanType.diet)
                  _isEditing ? _buildDietEdit(plan) : _buildDietRead(plan)
                else
                  _isEditing ? _buildExerciseEdit(plan) : _buildExerciseRead(plan),

                if(_isEditing) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton.icon(
                      onPressed: _addItemToPlan,
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      label: const Text("Add New Item"),
                      style: TextButton.styleFrom(foregroundColor: FitTheme.primary),
                    ),
                  )
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- DIET VIEWS ---

  Widget _buildDietRead(FitnessPlan plan) {
    if (plan.dietEntries == null || plan.dietEntries!.isEmpty) return _buildEmptyContent("No meal details added.");

    return Column(
      children: plan.dietEntries!.map((entry) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(entry.timeSlot, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: FitTheme.textMain), textAlign: TextAlign.right),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Container(
                width: 2,
                color: FitTheme.border,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32.0),
                  child: Text(entry.description, style: const TextStyle(fontSize: 14, height: 1.5, color: FitTheme.textSub)),
                ),
              )
            ],
          ),
        );
      }).toList(),
    );
  }

  // FIX: Converted to use specialized Sub-Widgets to prevent cursor jumping
  Widget _buildDietEdit(FitnessPlan plan) {
    if (plan.dietEntries == null) return const SizedBox();

    return Column(
      children: List.generate(plan.dietEntries!.length, (index) {
        final entry = plan.dietEntries![index];
        // Use Key to preserve state during list changes
        return DietRowEditor(
          key: ObjectKey(entry),
          entry: entry,
          onDelete: () => _deletePlanItem(index),
          onUpdate: _autoSave,
        );
      }),
    );
  }

  // --- EXERCISE VIEWS ---

  Widget _buildExerciseRead(FitnessPlan plan) {
    if (plan.exerciseEntries == null || plan.exerciseEntries!.isEmpty) return _buildEmptyContent("No exercises added.");

    return Wrap(
      spacing: 16, runSpacing: 16,
      children: plan.exerciseEntries!.map((entry) {
        return Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FitTheme.border),
              ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: FitTheme.exerciseColor.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.directions_run, color: FitTheme.exerciseColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.activity, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: FitTheme.textMain)),
                    const SizedBox(height: 4),
                    Text("${entry.durationMinutes} mins", style: const TextStyle(fontSize: 12, color: FitTheme.textSub, fontWeight: FontWeight.bold)),
                    if(entry.note != null && entry.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(entry.note!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      )
                  ],
                ),
              )
            ],
          ),
        );
      }).toList(),
    );
  }

  // FIX: Converted to use specialized Sub-Widgets to prevent cursor jumping
  Widget _buildExerciseEdit(FitnessPlan plan) {
    if (plan.exerciseEntries == null) return const SizedBox();

    return Column(
      children: List.generate(plan.exerciseEntries!.length, (index) {
        final entry = plan.exerciseEntries![index];
        // Use Key to preserve state during list changes
        return ExerciseRowEditor(
          key: ObjectKey(entry),
          entry: entry,
          onDelete: () => _deletePlanItem(index),
          onUpdate: _autoSave,
        );
      }),
    );
  }

  Widget _buildEmptyContent(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: FitTheme.textSub)),
        ],
      ),
    );
  }
}

// ============================================================================
//   SUB-WIDGETS (FIX FOR CURSOR JUMPING ISSUE)
//   These widgets hold their own TextControllers in State, so rebuilds of
//   the parent don't recreate the controllers and reset cursor position.
// ============================================================================

class DietRowEditor extends StatefulWidget {
  final DietEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onUpdate;

  const DietRowEditor({
    super.key,
    required this.entry,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<DietRowEditor> createState() => _DietRowEditorState();
}

class _DietRowEditorState extends State<DietRowEditor> {
  late TextEditingController _timeCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _timeCtrl = TextEditingController(text: widget.entry.timeSlot);
    _descCtrl = TextEditingController(text: widget.entry.description);
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: FitTheme.border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _timeCtrl,
              onChanged: (val) {
                widget.entry.timeSlot = val;
                widget.onUpdate();
              },
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              decoration: const InputDecoration(
                labelText: "Time Slot",
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _descCtrl,
              onChanged: (val) {
                widget.entry.description = val;
                widget.onUpdate();
              },
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: "Food Items",
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.close, color: Colors.red))
        ],
      ),
    );
  }
}

class ExerciseRowEditor extends StatefulWidget {
  final ExerciseEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onUpdate;

  const ExerciseRowEditor({
    super.key,
    required this.entry,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<ExerciseRowEditor> createState() => _ExerciseRowEditorState();
}

class _ExerciseRowEditorState extends State<ExerciseRowEditor> {
  late TextEditingController _activityCtrl;
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _activityCtrl = TextEditingController(text: widget.entry.activity);
    _noteCtrl = TextEditingController(text: widget.entry.note);
  }

  @override
  void dispose() {
    _activityCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: FitTheme.border)),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, color: Colors.grey),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _activityCtrl,
                        onChanged: (val) {
                          widget.entry.activity = val;
                          widget.onUpdate();
                        },
                        decoration: const InputDecoration(labelText: "Activity Name", isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Pill Selectors for Time
                    Row(
                      children: [15, 30, 45, 60].map((t) {
                        bool isSel = widget.entry.durationMinutes == t;
                        return InkWell(
                          onTap: () {
                            setState(() => widget.entry.durationMinutes = t);
                            widget.onUpdate();
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                                color: isSel ? FitTheme.exerciseColor : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSel ? FitTheme.exerciseColor : FitTheme.border)
                            ),
                            child: Text("$t m", style: TextStyle(fontSize: 11, color: isSel ? Colors.white : FitTheme.textSub, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }).toList(),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  onChanged: (val) {
                    widget.entry.note = val;
                    widget.onUpdate();
                  },
                  decoration: const InputDecoration(labelText: "Notes (Optional)", isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline, color: Colors.red))
        ],
      ),
    );
  }
}