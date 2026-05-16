import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; // For AppColors
import '../services/master_data_service.dart';
import 'full_screen_search.dart';

class PatientMedicalHistoryPage extends StatefulWidget {
  final String uhid;

  const PatientMedicalHistoryPage({super.key, required this.uhid});

  @override
  State<PatientMedicalHistoryPage> createState() => _PatientMedicalHistoryPageState();
}

class _PatientMedicalHistoryPageState extends State<PatientMedicalHistoryPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = true;

  // History Data
  Map<String, dynamic> _historyData = {
    'existing_conditions': <Map<String, dynamic>>[], 
    'current_medications': <Map<String, dynamic>>[],
    'family_history': <Map<String, dynamic>>[],
    'lifestyle_habit': <Map<String, dynamic>>[],
    'food_allergy': <Map<String, dynamic>>[],
    'drug_allergy': <Map<String, dynamic>>[],
    'travel_history': <Map<String, dynamic>>[],
  };
  String _otherHistory = "";

  final List<Map<String, String>> _categories = [
    {'id': 'preview', 'label': 'Preview', 'icon': 'dashboard'}, // New Preview Tab
    {'id': 'existing_conditions', 'label': 'Conditions', 'icon': 'emergency'},
    {'id': 'current_medications', 'label': 'Medications', 'icon': 'medication'},
    {'id': 'family_history', 'label': 'Family', 'icon': 'family_restroom'},
    {'id': 'lifestyle_habit', 'label': 'Habits', 'icon': 'accessibility_new'},
    {'id': 'food_allergy', 'label': 'Food', 'icon': 'restaurant'},
    {'id': 'drug_allergy', 'label': 'Drugs', 'icon': 'vaccines'},
    {'id': 'travel_history', 'label': 'Travel', 'icon': 'flight_takeoff'},
    {'id': 'other_history', 'label': 'Other', 'icon': 'history_edu'},
  ];

  int _selectedCategoryIndex = 0; // Default to Preview
  Map<String, dynamic>? _selectedMedication; 
  Map<String, dynamic>? _selectedCondition;
  Map<String, dynamic>? _selectedFamilyItem;
  Map<String, dynamic>? _selectedHabit;
  Map<String, dynamic>? _selectedFoodAllergy;
  Map<String, dynamic>? _selectedDrugAllergy;
  Map<String, dynamic>? _selectedTravelItem;

  // --- Constants ---
  final List<String> _doseOptions = ["1/4", "1/2", "1", "1½", "2", "3"];
  final List<String> _durationOptions = ["1d", "2d", "3d", "4d", "5d", "1m", "2m", "3m", "4m", "6m", "1y", "2y", "5y"];
  
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _conditionNoteController = TextEditingController();
  final TextEditingController _familyNoteController = TextEditingController();
  final TextEditingController _habitNoteController = TextEditingController();
  final TextEditingController _foodNoteController = TextEditingController();
  final TextEditingController _drugNoteController = TextEditingController();
  final TextEditingController _travelNoteController = TextEditingController();
  final TextEditingController _customDurationController = TextEditingController();
  String _customDurationUnit = 'm';

  // Family Members
  final List<String> _commonRelations = ["Father", "Mother", "Husband", "Wife", "Son", "Daughter", "Brother", "Sister"];
  final List<String> _otherRelations = ["Grandfather", "Grandmother", "Spouse", "Father & Mother", "Cousin Brother", "Cousin Sister", "Paternal Uncle", "Paternal Aunt", "Maternal Uncle", "Maternal Aunt", "Paternal Grandfather", "Paternal Grandmother", "Maternal Grandfather", "Maternal Grandmother", "Great grandfather", "Great grandmother"];
  bool _showAllRelations = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await MasterDataService().initialize();
      await _loadPatientHistory();
    } catch (e) {
      debugPrint("Error loading history data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPatientHistory() async {
    try {
      final response = await supabase.from('patient_medical_history').select().eq('uhid', widget.uhid).maybeSingle();
      if (response != null) {
        setState(() {
          // Migration logic (same as before)
          var conditions = response['existing_conditions'] ?? [];
          if (conditions.isNotEmpty && conditions[0] is String) {
            _historyData['existing_conditions'] = (conditions as List<dynamic>).map((c) => {'name': c, 'since': '1y', 'status': 'Active', 'note': ''}).toList();
          } else { _historyData['existing_conditions'] = List<Map<String, dynamic>>.from(conditions); }

          var family = response['family_history'] ?? [];
          if (family.isNotEmpty && family[0] is String) {
            _historyData['family_history'] = (family as List<dynamic>).map((c) => {'condition': c, 'relation': 'Father', 'status': 'Active', 'note': ''}).toList();
          } else { _historyData['family_history'] = List<Map<String, dynamic>>.from(family); }

          var habits = response['lifestyle_habits'] ?? [];
          if (habits.isNotEmpty && habits[0] is String) {
            _historyData['lifestyle_habit'] = (habits as List<dynamic>).map((c) => {'habit': c, 'since': '1y', 'freq_value': '1', 'freq_unit': 'Day', 'status': 'Active', 'note': ''}).toList();
          } else { _historyData['lifestyle_habit'] = List<Map<String, dynamic>>.from(habits); }

          var food = response['food_allergies'] ?? [];
          if (food.isNotEmpty && food[0] is String) {
            _historyData['food_allergy'] = (food as List<dynamic>).map((c) => {'item': c, 'since': '1y', 'status': 'Active', 'note': ''}).toList();
          } else { _historyData['food_allergy'] = List<Map<String, dynamic>>.from(food); }

          var drug = response['drug_allergies'] ?? [];
          if (drug.isNotEmpty && drug[0] is String) {
            _historyData['drug_allergy'] = (drug as List<dynamic>).map((c) => {'item': c, 'since': '1y', 'status': 'Active', 'note': ''}).toList();
          } else { _historyData['drug_allergy'] = List<Map<String, dynamic>>.from(drug); }

          var travel = response['travel_history'] ?? [];
          if (travel.isNotEmpty && travel[0] is String) {
            _historyData['travel_history'] = (travel as List<dynamic>).map((c) => {'destination': c, 'since': '1m', 'note': ''}).toList();
          } else { _historyData['travel_history'] = List<Map<String, dynamic>>.from(travel); }

          _historyData['current_medications'] = List<Map<String, dynamic>>.from(response['current_medications'] ?? []);
          _otherHistory = response['other_medical_history'] ?? "";
        });
      }
    } catch (e) { debugPrint("Error fetching patient history: $e"); }
  }

  Future<List<String>> _searchMedicines(String query) async {
    try {
      var request = supabase.from('opd_medicine').select('medicine_name');
      if (query.trim().isNotEmpty) request = request.ilike('medicine_name', '%$query%');
      final response = await request.limit(50);
      return (response as List).map((e) => e['medicine_name'] as String).toList();
    } catch (e) { return []; }
  }

  Future<List<String>> _searchMasterData(String categoryId, String query) async {
    try {
      var request = supabase.from('master_dropdown_data').select('item_name').eq('data_type', 'medical_history').eq('data_subtype', categoryId);
      if (query.trim().isNotEmpty) request = request.ilike('item_name', '%$query%');
      final response = await request.order('selected_count', ascending: false).order('item_name', ascending: true).limit(50); 
      return (response as List).map((e) => e['item_name'] as String).toList();
    } catch (e) { return []; }
  }

  Future<void> _saveData() async {
    try {
      await supabase.from('patient_medical_history').upsert({
        'uhid': widget.uhid,
        'existing_conditions': _historyData['existing_conditions'],
        'current_medications': _historyData['current_medications'],
        'family_history': _historyData['family_history'],
        'lifestyle_habits': _historyData['lifestyle_habit'],
        'food_allergies': _historyData['food_allergy'],
        'drug_allergies': _historyData['drug_allergy'],
        'travel_history': _historyData['travel_history'],
        'other_medical_history': _otherHistory,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'uhid');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("History updated successfully"), backgroundColor: Colors.green));
    } catch (e) { debugPrint("Error saving history: $e"); }
  }

  void _addItem(String categoryId, String item) async {
    if (item.trim().isEmpty) return;
    if (categoryId == 'current_medications') {
      final meds = _historyData['current_medications'] as List<Map<String, dynamic>>;
      if (!meds.any((m) => m['name'] == item)) {
        String type = 'TAB', unit = 'tab';
        try {
          final res = await supabase.from('opd_medicine').select('type, unit').eq('medicine_name', item).maybeSingle();
          if (res != null) { type = res['type'] ?? 'TAB'; unit = res['unit'] ?? 'tab'; }
        } catch (e) {}
        setState(() {
          final newMed = { 'name': item, 'type': type, 'unit': unit, 'dosage': '1', 'duration': '6m', 'bb': false, 'ab': true, 'bl': false, 'al': true, 'bd': false, 'ad': true, 'status': 'Active', 'note': '' };
          meds.add(newMed); _selectMedicine(newMed);
        });
      }
    } else if (categoryId == 'existing_conditions') {
      final list = _historyData['existing_conditions'] as List<Map<String, dynamic>>;
      if (!list.any((c) => c['name'] == item)) { setState(() { final newCondition = {'name': item, 'since': '1y', 'status': 'Active', 'note': ''}; list.add(newCondition); _selectCondition(newCondition); }); }
    } else if (categoryId == 'family_history') {
      final list = _historyData['family_history'] as List<Map<String, dynamic>>;
      if (!list.any((c) => c['condition'] == item)) { setState(() { final newItem = {'condition': item, 'relation': 'Father', 'status': 'Active', 'note': ''}; list.add(newItem); _selectFamilyItem(newItem); }); }
    } else if (categoryId == 'lifestyle_habit') {
      final list = _historyData['lifestyle_habit'] as List<Map<String, dynamic>>;
      if (!list.any((c) => c['habit'] == item)) { setState(() { final newItem = {'habit': item, 'since': '1y', 'freq_value': '1', 'freq_unit': 'Day', 'status': 'Active', 'note': ''}; list.add(newItem); _selectHabit(newItem); }); }
    } else if (categoryId == 'food_allergy') {
      final list = _historyData['food_allergy'] as List<Map<String, dynamic>>;
      if (!list.any((c) => c['item'] == item)) { setState(() { final newItem = {'item': item, 'since': '1y', 'status': 'Active', 'note': ''}; list.add(newItem); _selectFoodAllergy(newItem); }); }
    } else if (categoryId == 'drug_allergy') {
      final list = _historyData['drug_allergy'] as List<Map<String, dynamic>>;
      if (!list.any((c) => c['item'] == item)) { setState(() { final newItem = {'item': item, 'since': '1y', 'status': 'Active', 'note': ''}; list.add(newItem); _selectDrugAllergy(newItem); }); }
    } else if (categoryId == 'travel_history') {
      final list = _historyData['travel_history'] as List<Map<String, dynamic>>;
      setState(() { final newItem = {'destination': item, 'since': '1m', 'note': ''}; list.add(newItem); _selectTravelItem(newItem); });
    }
    try { await supabase.rpc('increment_master_data_count', params: {'d_type': 'medical_history', 'd_subtype': categoryId, 'i_name': item}); } catch (e) {}
  }

  void _removeItem(String categoryId, dynamic item) {
    setState(() {
      if (categoryId == 'current_medications') { (_historyData['current_medications'] as List<Map<String, dynamic>>).remove(item); if (_selectedMedication == item) _selectedMedication = null; }
      else if (categoryId == 'existing_conditions') { (_historyData['existing_conditions'] as List<Map<String, dynamic>>).remove(item); if (_selectedCondition == item) _selectedCondition = null; }
      else if (categoryId == 'family_history') { (_historyData['family_history'] as List<Map<String, dynamic>>).remove(item); if (_selectedFamilyItem == item) _selectedFamilyItem = null; }
      else if (categoryId == 'lifestyle_habit') { (_historyData['lifestyle_habit'] as List<Map<String, dynamic>>).remove(item); if (_selectedHabit == item) _selectedHabit = null; }
      else if (categoryId == 'food_allergy') { (_historyData['food_allergy'] as List<Map<String, dynamic>>).remove(item); if (_selectedFoodAllergy == item) _selectedFoodAllergy = null; }
      else if (categoryId == 'drug_allergy') { (_historyData['drug_allergy'] as List<Map<String, dynamic>>).remove(item); if (_selectedDrugAllergy == item) _selectedDrugAllergy = null; }
      else if (categoryId == 'travel_history') { (_historyData['travel_history'] as List<Map<String, dynamic>>).remove(item); if (_selectedTravelItem == item) _selectedTravelItem = null; }
    });
  }

  void _removeMedicine(Map<String, dynamic> med) => _removeItem('current_medications', med);
  void _selectMedicine(Map<String, dynamic> med) { setState(() { _selectedMedication = med; _noteController.text = med['note'] ?? ''; String dur = med['duration'] ?? '6m'; _customDurationController.text = dur.replaceAll(RegExp(r'[dmy]'), ''); _customDurationUnit = dur.replaceAll(RegExp(r'[^dmy]'), ''); }); }
  void _selectCondition(Map<String, dynamic> cond) { setState(() { _selectedCondition = cond; _conditionNoteController.text = cond['note'] ?? ''; }); }
  void _selectFamilyItem(Map<String, dynamic> item) { setState(() { _selectedFamilyItem = item; _familyNoteController.text = item['note'] ?? ''; }); }
  void _selectHabit(Map<String, dynamic> item) { setState(() { _selectedHabit = item; _habitNoteController.text = item['note'] ?? ''; }); }
  void _selectFoodAllergy(Map<String, dynamic> item) { setState(() { _selectedFoodAllergy = item; _foodNoteController.text = item['note'] ?? ''; }); }
  void _selectDrugAllergy(Map<String, dynamic> item) { setState(() { _selectedDrugAllergy = item; _drugNoteController.text = item['note'] ?? ''; }); }
  void _selectTravelItem(Map<String, dynamic> item) { setState(() { _selectedTravelItem = item; _travelNoteController.text = item['note'] ?? ''; }); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBody,
      appBar: AppBar(
        title: Text("Patient Medical History", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        backgroundColor: AppColors.surface, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), color: AppColors.textPrimary, onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton.icon(onPressed: _saveData, icon: const Icon(Icons.save_rounded, size: 18), label: Text("SAVE", style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildCategoryContent(),
      bottomNavigationBar: Container(
        height: 70, decoration: BoxDecoration(color: AppColors.surface, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))]),
        child: ListView.builder(
          scrollDirection: Axis.horizontal, itemCount: _categories.length,
          itemBuilder: (context, index) {
            final cat = _categories[index]; final isSelected = _selectedCategoryIndex == index;
            return InkWell(
              onTap: () => setState(() { _selectedCategoryIndex = index; _selectedMedication = null; _selectedCondition = null; _selectedFamilyItem = null; _selectedHabit = null; _selectedFoodAllergy = null; _selectedDrugAllergy = null; _selectedTravelItem = null; }),
              child: Container(width: 80, padding: const EdgeInsets.symmetric(vertical: 8), color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_getIcon(cat['icon']!), color: isSelected ? AppColors.primary : AppColors.textSecondary, size: 18), const SizedBox(height: 4), Text(cat['label']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 9, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? AppColors.primary : AppColors.textSecondary))])),
            );
          },
        ),
      ),
    );
  }

  IconData _getIcon(String name) {
    switch(name) {
      case 'dashboard': return Icons.dashboard_rounded; case 'emergency': return Icons.emergency_rounded; case 'medication': return Icons.medication_rounded; case 'family_restroom': return Icons.family_restroom_rounded; case 'accessibility_new': return Icons.accessibility_new_rounded; case 'restaurant': return Icons.restaurant_rounded; case 'vaccines': return Icons.vaccines_rounded; case 'flight_takeoff': return Icons.flight_takeoff_rounded; case 'history_edu': return Icons.history_edu_rounded; default: return Icons.label_rounded;
    }
  }

  Widget _buildCategoryContent() {
    final catId = _categories[_selectedCategoryIndex]['id']!;
    if (catId == 'preview') return _buildPreviewHistory();
    if (catId == 'current_medications') return _buildMedicationsCockpit();
    if (catId == 'existing_conditions') return _buildConditionsCockpit();
    if (catId == 'family_history') return _buildFamilyHistoryCockpit();
    if (catId == 'lifestyle_habit') return _buildHabitCockpit();
    if (catId == 'food_allergy') return _buildAllergyCockpit('food_allergy', 'Food Allergy', Icons.restaurant_rounded, _selectedFoodAllergy, _selectFoodAllergy, _foodNoteController);
    if (catId == 'drug_allergy') return _buildAllergyCockpit('drug_allergy', 'Drug Allergy', Icons.vaccines_rounded, _selectedDrugAllergy, _selectDrugAllergy, _drugNoteController);
    if (catId == 'travel_history') return _buildTravelCockpit();

    if (catId == 'other_history') {
      return Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Other Medical History", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Expanded(child: TextField(maxLines: null, expands: true, onChanged: (val) => _otherHistory = val, controller: TextEditingController(text: _otherHistory), decoration: InputDecoration(hintText: "Enter details...", filled: true, fillColor: AppColors.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))))]));
    }
    return const SizedBox();
  }

  // ── PREVIEW HISTORY ────────────────────────────────
  Widget _buildPreviewHistory() {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text("Medical History Summary", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      const SizedBox(height: 4), Text("Overview of all documented clinical data", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 24),
      _previewSection("Existing Conditions", 'existing_conditions', Icons.emergency_rounded, _historyData['existing_conditions'], (i) => "${i['name']} (${i['since']})"),
      _previewSection("Current Medications", 'current_medications', Icons.medication_rounded, _historyData['current_medications'], (i) => "${i['name']} - ${i['dosage']} ${i['unit']} (${i['duration']})"),
      _previewSection("Family History", 'family_history', Icons.family_restroom_rounded, _historyData['family_history'], (i) => "${i['condition']} - ${i['relation']}"),
      _previewSection("Lifestyle Habits", 'lifestyle_habit', Icons.accessibility_new_rounded, _historyData['lifestyle_habit'], (i) => "${i['habit']} (${i['freq_value']} ${i['freq_unit']})"),
      _previewSection("Food Allergies", 'food_allergy', Icons.restaurant_rounded, _historyData['food_allergy'], (i) => "${i['item']} (${i['since']})"),
      _previewSection("Drug Allergies", 'drug_allergy', Icons.vaccines_rounded, _historyData['drug_allergy'], (i) => "${i['item']} (${i['since']})"),
      _previewSection("Travel History", 'travel_history', Icons.flight_takeoff_rounded, _historyData['travel_history'], (i) => i['destination']),
      if (_otherHistory.isNotEmpty) _previewSection("Other History", 'other_history', Icons.history_edu_rounded, [{}], (i) => _otherHistory),
    ]);
  }

  Widget _previewSection(String title, String catId, IconData icon, List<dynamic> items, String Function(dynamic) labelBuilder) {
    if (items.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 8, 12), child: Row(children: [Icon(icon, size: 18, color: AppColors.primary), const SizedBox(width: 10), Expanded(child: Text(title.toUpperCase(), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5))), InkWell(onTap: () { int idx = _categories.indexWhere((c) => c['id'] == catId); if (idx != -1) setState(() => _selectedCategoryIndex = idx); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)), child: const Text("EDIT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary))))])),
        const Divider(height: 1),
        ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 44), itemBuilder: (ctx, i) {
          final item = items[i];
          return ListTile(
            dense: true, visualDensity: VisualDensity.compact, leading: const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.green),
            title: Text(labelBuilder(item), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: (item is Map && (item['note'] ?? '').isNotEmpty) ? Text(item['note'], style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)) : null,
          );
        }),
      ]),
    );
  }

  // ── ALLERGY COCKPIT (FOOD & DRUG) ─────────────────────────
  Widget _buildAllergyCockpit(String catId, String label, IconData icon, Map<String, dynamic>? selectedItem, Function(Map<String, dynamic>) onSelect, TextEditingController noteCtrl) {
    final list = _historyData[catId] as List<Map<String, dynamic>>;
    return Row(children: [
      Container(width: 300, decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenSearchPage(title: "Search $label", hintText: "e.g. Peanuts, Aspirin...", onSearch: (q) => _searchMasterData(catId, q), onItemSelected: (selected) => _addItem(catId, selected)))), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text("Search $label...", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary))])))),
        Expanded(child: list.isEmpty ? Center(child: Text("No $label added", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))) : ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) { final item = list[i]; final isSel = selectedItem == item; return GestureDetector(onTap: () => onSelect(item), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['item'], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textPrimary)), Text("Since: ${item['since']} | ${item['status']}", style: GoogleFonts.poppins(fontSize: 11, color: isSel ? Colors.white70 : AppColors.textSecondary))]))); })),
      ])),
      Expanded(child: selectedItem != null ? _buildGenericEditor(catId, selectedItem, noteCtrl) : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: AppColors.border), const SizedBox(height: 12), Text("Select $label to edit", style: TextStyle(color: AppColors.textSecondary))]))),
    ]);
  }

  Widget _buildGenericEditor(String catId, Map<String, dynamic> item, TextEditingController noteCtrl) {
    return Padding(padding: const EdgeInsets.all(24), child: ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['item'] ?? item['condition'] ?? 'Item', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeItem(catId, item))]),
      const SizedBox(height: 24), _sectionTitle("SINCE (DURATION)", Icons.calendar_today), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [..._durationOptions.map((d) => _genericDurationChip(item, d)), _customGenericDurationInput(item)]),
      const SizedBox(height: 32), _sectionTitle("STATUS", Icons.info_outline), const SizedBox(height: 12),
      Row(children: ["Active", "Stopped", "Inactive"].map((s) { bool isSel = item['status'] == s; return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: isSel, onSelected: (v) => setState(() => item['status'] = s), selectedColor: AppColors.primary, labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary))); }).toList()),
      const SizedBox(height: 32), _sectionTitle("NOTES", Icons.notes), const SizedBox(height: 12),
      TextField(controller: noteCtrl, onChanged: (v) => item['note'] = v, maxLines: 3, decoration: InputDecoration(hintText: "Add details...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    ]));
  }

  // ── TRAVEL COCKPIT ─────────────────────────
  Widget _buildTravelCockpit() {
    final list = _historyData['travel_history'] as List<Map<String, dynamic>>;
    return Row(children: [
      Container(width: 300, decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenSearchPage(title: "Add Destination", hintText: "e.g. Dubai, London...", onSearch: (q) => _searchMasterData('travel_history', q), onItemSelected: (selected) => _addItem('travel_history', selected)))), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Row(children: [const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text("Add Destination...", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary))])))),
        Expanded(child: list.isEmpty ? Center(child: Text("No travel history", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))) : ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) { final item = list[i]; final isSel = _selectedTravelItem == item; return GestureDetector(onTap: () => _selectTravelItem(item), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['destination'], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textPrimary)), Text("Visited: ${item['since']}", style: GoogleFonts.poppins(fontSize: 11, color: isSel ? Colors.white70 : AppColors.textSecondary))]))); })),
      ])),
      Expanded(child: _selectedTravelItem != null ? _buildTravelEditor() : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.flight_takeoff_rounded, size: 48, color: AppColors.border), const SizedBox(height: 12), Text("Select destination to edit", style: TextStyle(color: AppColors.textSecondary))]))),
    ]);
  }

  Widget _buildTravelEditor() {
    final item = _selectedTravelItem!;
    return Padding(padding: const EdgeInsets.all(24), child: ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['destination'], style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeItem('travel_history', item))]),
      const SizedBox(height: 24), _sectionTitle("WHEN (SINCE)", Icons.calendar_today), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [..._durationOptions.map((d) => _genericDurationChip(item, d)), _customGenericDurationInput(item)]),
      const SizedBox(height: 32), _sectionTitle("DESTINATION NOTES", Icons.notes), const SizedBox(height: 12),
      TextField(controller: _travelNoteController, onChanged: (v) => item['note'] = v, maxLines: 5, decoration: InputDecoration(hintText: "Add trip details...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    ]));
  }

  Widget _genericDurationChip(Map<String, dynamic> item, String val) { bool isSel = item['since'] == val; return InkWell(onTap: () => setState(() => item['since'] = val), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: isSel ? AppColors.textPrimary : Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textSecondary)))); }
  Widget _customGenericDurationInput(Map<String, dynamic> item) => Container(width: 120, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Row(children: [Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _durationOptions.contains(item['since']) ? null : item['since'].toString().replaceAll(RegExp(r'[^0-9]'), ''), items: List.generate(30, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() { item['since'] = "$v${item['since'].toString().replaceAll(RegExp(r'[0-9]'), '')}"; })))), DropdownButtonHideUnderline(child: DropdownButton<String>(value: item['since'].toString().replaceAll(RegExp(r'[^dmy]'), '').isEmpty ? 'y' : item['since'].toString().replaceAll(RegExp(r'[^dmy]'), ''), items: ['d','w','m','y'].map((u) => DropdownMenuItem(value: u, child: Text(u.toUpperCase()))).toList(), onChanged: (v) => setState(() { item['since'] = "${item['since'].toString().replaceAll(RegExp(r'[^0-9]'), '')}$v"; }))) ]));

  // ── LIFESTYLE HABIT COCKPIT ─────────────────────────
  Widget _buildHabitCockpit() {
    final list = _historyData['lifestyle_habit'] as List<Map<String, dynamic>>;
    return Row(children: [
      Container(width: 300, decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenSearchPage(title: "Search Habits", hintText: "Smoking, Alcohol...", onSearch: (q) => _searchMasterData('lifestyle_habit', q), onItemSelected: (selected) => _addItem('lifestyle_habit', selected)))), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text("Search Habits...", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary))])))),
        Expanded(child: list.isEmpty ? Center(child: Text("No habits added", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))) : ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) { final item = list[i]; final isSel = _selectedHabit == item; return GestureDetector(onTap: () => _selectHabit(item), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['habit'], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textPrimary)), Text("${item['freq_value']} time/s in a ${item['freq_unit']} | since ${item['since']}", style: GoogleFonts.poppins(fontSize: 11, color: isSel ? Colors.white70 : AppColors.textSecondary))]))); })),
      ])),
      Expanded(child: _selectedHabit != null ? _buildHabitEditor() : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.accessibility_new_rounded, size: 48, color: AppColors.border), const SizedBox(height: 12), Text("Select habit to edit", style: TextStyle(color: AppColors.textSecondary))]))),
    ]);
  }

  Widget _buildHabitEditor() {
    final item = _selectedHabit!;
    return Padding(padding: const EdgeInsets.all(24), child: ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['habit'], style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeItem('lifestyle_habit', item))]),
      const SizedBox(height: 24), _sectionTitle("SINCE (DURATION)", Icons.calendar_today), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [..._durationOptions.map((d) => _habitDurationChip(item, d)), _customHabitDurationInput(item)]),
      const SizedBox(height: 32), _sectionTitle("FREQUENCY", Icons.repeat_rounded), const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)), child: Row(children: [
        DropdownButtonHideUnderline(child: DropdownButton<String>(value: item['freq_value'], items: List.generate(50, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => item['freq_value'] = v))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("time/s in a", style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
        Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: item['freq_unit'], items: ["Hour", "Day", "Week", "Month", "Year"].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (v) => setState(() => item['freq_unit'] = v)))),
      ])),
      const SizedBox(height: 32), _sectionTitle("STATUS", Icons.info_outline), const SizedBox(height: 12),
      Row(children: ["Active", "Stopped", "Inactive"].map((s) { bool isSel = item['status'] == s; return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: isSel, onSelected: (v) => setState(() => item['status'] = s), selectedColor: AppColors.primary, labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary))); }).toList()),
      const SizedBox(height: 32), _sectionTitle("NOTES", Icons.notes), const SizedBox(height: 12),
      TextField(controller: _habitNoteController, onChanged: (v) => item['note'] = v, maxLines: 3, decoration: InputDecoration(hintText: "Add details...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    ]));
  }

  Widget _habitDurationChip(Map<String, dynamic> item, String val) { bool isSel = item['since'] == val; return InkWell(onTap: () => setState(() => item['since'] = val), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: isSel ? AppColors.textPrimary : Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textSecondary)))); }
  Widget _customHabitDurationInput(Map<String, dynamic> item) => Container(width: 120, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Row(children: [Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _durationOptions.contains(item['since']) ? null : item['since'].toString().replaceAll(RegExp(r'[^0-9]'), ''), items: List.generate(30, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() { item['since'] = "$v${item['since'].toString().replaceAll(RegExp(r'[0-9]'), '')}"; })))), DropdownButtonHideUnderline(child: DropdownButton<String>(value: item['since'].toString().replaceAll(RegExp(r'[^dmy]'), '').isEmpty ? 'y' : item['since'].toString().replaceAll(RegExp(r'[^dmy]'), ''), items: ['d','w','m','y'].map((u) => DropdownMenuItem(value: u, child: Text(u.toUpperCase()))).toList(), onChanged: (v) => setState(() { item['since'] = "${item['since'].toString().replaceAll(RegExp(r'[^0-9]'), '')}$v"; }))) ]));

  // ── FAMILY HISTORY COCKPIT ─────────────────────────
  Widget _buildFamilyHistoryCockpit() {
    final list = _historyData['family_history'] as List<Map<String, dynamic>>;
    return Row(children: [
      Container(width: 300, decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenSearchPage(title: "Search Family Condition", hintText: "e.g. Diabetes...", onSearch: (q) => _searchMasterData('family_history', q), onItemSelected: (selected) => _addItem('family_history', selected)))), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text("Search Conditions...", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary))])))),
        Expanded(child: list.isEmpty ? Center(child: Text("No family history added", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))) : ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) { final item = list[i]; final isSel = _selectedFamilyItem == item; return GestureDetector(onTap: () => _selectFamilyItem(item), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['condition'], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textPrimary)), Text("Relation: ${item['relation']} | ${item['status']}", style: GoogleFonts.poppins(fontSize: 11, color: isSel ? Colors.white70 : AppColors.textSecondary))]))); })),
      ])),
      Expanded(child: _selectedFamilyItem != null ? _buildFamilyEditor() : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.family_restroom_rounded, size: 48, color: AppColors.border), const SizedBox(height: 12), Text("Select family history to edit", style: TextStyle(color: AppColors.textSecondary))]))),
    ]);
  }

  Widget _buildFamilyEditor() {
    final item = _selectedFamilyItem!; final relations = _showAllRelations ? [..._commonRelations, ..._otherRelations] : _commonRelations;
    return Padding(padding: const EdgeInsets.all(24), child: ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['condition'], style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeItem('family_history', item))]),
      const SizedBox(height: 24), _sectionTitle("FAMILY MEMBER (RELATION)", Icons.people_outline), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [...relations.map((r) { bool isSel = item['relation'] == r; return ChoiceChip(label: Text(r), selected: isSel, onSelected: (v) => setState(() => item['relation'] = r), selectedColor: AppColors.primary, labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary, fontSize: 12)); }), ActionChip(label: Text(_showAllRelations ? "See Less" : "See More...", style: const TextStyle(fontWeight: FontWeight.bold)), onPressed: () => setState(() => _showAllRelations = !_showAllRelations))]),
      const SizedBox(height: 32), _sectionTitle("STATUS", Icons.info_outline), const SizedBox(height: 12),
      Row(children: ["Active", "Inactive"].map((s) { bool isSel = item['status'] == s; return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: isSel, onSelected: (v) => setState(() => item['status'] = s), selectedColor: AppColors.primary, labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary))); }).toList()),
      const SizedBox(height: 32), _sectionTitle("NOTES", Icons.notes), const SizedBox(height: 12),
      TextField(controller: _familyNoteController, onChanged: (v) => item['note'] = v, maxLines: 3, decoration: InputDecoration(hintText: "Notes...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    ]));
  }

  // ── EXISTING CONDITIONS COCKPIT ─────────────────────────
  Widget _buildConditionsCockpit() {
    final list = _historyData['existing_conditions'] as List<Map<String, dynamic>>;
    return Row(children: [
      Container(width: 300, decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenSearchPage(title: "Search Conditions", hintText: "Type name...", onSearch: (q) => _searchMasterData('existing_conditions', q), onItemSelected: (selected) => _addItem('existing_conditions', selected)))), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text("Search Conditions...", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary))])))),
        Expanded(child: list.isEmpty ? Center(child: Text("No conditions added", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))) : ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) { final item = list[i]; final isSel = _selectedCondition == item; return GestureDetector(onTap: () => _selectCondition(item), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['name'], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textPrimary)), Text("Since: ${item['since']} | ${item['status']}", style: GoogleFonts.poppins(fontSize: 11, color: isSel ? Colors.white70 : AppColors.textSecondary))]))); })),
      ])),
      Expanded(child: _selectedCondition != null ? _buildConditionEditor() : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.emergency_rounded, size: 48, color: AppColors.border), const SizedBox(height: 12), Text("Select condition to edit", style: TextStyle(color: AppColors.textSecondary))]))),
    ]);
  }

  Widget _buildConditionEditor() {
    final cond = _selectedCondition!;
    return Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(cond['name'], style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeItem('existing_conditions', cond))]),
      const SizedBox(height: 24), _sectionTitle("SINCE (DURATION)", Icons.calendar_today), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [..._durationOptions.map((d) => _conditionDurationChip(cond, d)), _customConditionDurationInput(cond)]),
      const SizedBox(height: 32), _sectionTitle("CURRENT STATUS", Icons.info_outline), const SizedBox(height: 12),
      Row(children: ["Active", "Controlled", "Resolved", "Stable", "Inactive"].map((s) { bool isSel = cond['status'] == s; return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: isSel, onSelected: (v) => setState(() => cond['status'] = s), selectedColor: AppColors.primary, labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary))); }).toList()),
      const SizedBox(height: 32), _sectionTitle("NOTES", Icons.notes), const SizedBox(height: 12),
      TextField(controller: _conditionNoteController, onChanged: (v) => cond['note'] = v, maxLines: 3, decoration: InputDecoration(hintText: "Notes...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    ]));
  }

  Widget _conditionDurationChip(Map<String, dynamic> cond, String val) { bool isSel = cond['since'] == val; return InkWell(onTap: () => setState(() => cond['since'] = val), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: isSel ? AppColors.textPrimary : Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textSecondary)))); }
  Widget _customConditionDurationInput(Map<String, dynamic> cond) => Container(width: 120, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Row(children: [Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _durationOptions.contains(cond['since']) ? null : cond['since'].toString().replaceAll(RegExp(r'[^0-9]'), ''), items: List.generate(30, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() { cond['since'] = "$v${cond['since'].toString().replaceAll(RegExp(r'[0-9]'), '')}"; })))), DropdownButtonHideUnderline(child: DropdownButton<String>(value: cond['since'].toString().replaceAll(RegExp(r'[^dmy]'), '').isEmpty ? 'y' : cond['since'].toString().replaceAll(RegExp(r'[^dmy]'), ''), items: ['d','w','m','y'].map((u) => DropdownMenuItem(value: u, child: Text(u.toUpperCase()))).toList(), onChanged: (v) { setState(() { cond['since'] = "${cond['since'].toString().replaceAll(RegExp(r'[^0-9]'), '')}$v"; }); } )) ]));

  // ── MEDICATIONS COCKPIT ─────────────────────────
  Widget _buildMedicationsCockpit() {
    final meds = _historyData['current_medications'] as List<Map<String, dynamic>>;
    return Row(children: [
      Container(width: 300, decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenSearchPage(title: "Search Medicines", hintText: "Type medicine name...", onSearch: _searchMedicines, onItemSelected: (selected) => _addItem('current_medications', selected)))), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Row(children: [const Icon(Icons.search_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text("Search Medicines...", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary))])))),
        Expanded(child: meds.isEmpty ? Center(child: Text("No medicines added", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))) : ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: meds.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) { final med = meds[i]; final isSel = _selectedMedication == med; return GestureDetector(onTap: () => _selectMedicine(med), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(med['name'], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textPrimary)), Text("${med['dosage']} ${med['unit']} | ${med['duration']}", style: GoogleFonts.poppins(fontSize: 11, color: isSel ? Colors.white70 : AppColors.textSecondary))]))); })),
      ])),
      Expanded(child: _selectedMedication != null ? _buildEditor() : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.medication_rounded, size: 48, color: AppColors.border), const SizedBox(height: 12), Text("Select medicine to edit", style: TextStyle(color: AppColors.textSecondary))]))),
    ]);
  }

  Widget _buildEditor() {
    final med = _selectedMedication!;
    return Column(children: [
      Container(padding: const EdgeInsets.all(16), color: Colors.white, child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(med['name'], style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, children: ["TAB","CAP","SYRUP","SUSP","DROP","INJ","CREAM"].map((t) { bool isSel = med['type'] == t; return Padding(padding: const EdgeInsets.only(right: 6), child: InkWell(onTap: () => setState(() => med['type'] = t), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center, decoration: BoxDecoration(color: isSel ? AppColors.primary : AppColors.bgBody, borderRadius: BorderRadius.circular(6)), child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textSecondary))))); }).toList()))),
            const SizedBox(width: 8), _dropdownHeader(med, 'unit', ["mg","ml","mcg","tab","cap","drop"]),
          ]),
        ])),
        const SizedBox(width: 16), _statusToggle(med), const SizedBox(width: 8), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeMedicine(med)),
      ])),
      const Divider(height: 1),
      Expanded(child: ListView(padding: const EdgeInsets.all(24), children: [
        _sectionTitle("DOSAGE PER INTAKE", Icons.pie_chart_outline), const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [..._doseOptions.map((d) => _doseButton(med, d)), _customDoseInput(med)]),
        const SizedBox(height: 32), _sectionTitle("TIMING & FREQUENCY", Icons.access_time), const SizedBox(height: 12),
        Row(children: [Expanded(child: _timingBlock("Breakfast", Icons.wb_twilight, med, 'bb', 'ab')), const SizedBox(width: 12), Expanded(child: _timingBlock("Lunch", Icons.wb_sunny, med, 'bl', 'al')), const SizedBox(width: 12), Expanded(child: _timingBlock("Dinner", Icons.nights_stay, med, 'bd', 'ad'))]),
        const SizedBox(height: 32), _sectionTitle("DURATION / SINCE", Icons.calendar_today_outlined), const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [..._durationOptions.map((dur) => _durationChip(med, dur)), _customDurationInput(med)]),
        const SizedBox(height: 32), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_sectionTitle("INSTRUCTIONS / NOTES", Icons.sticky_note_2_outlined), _noteShortcuts(med)]),
        const SizedBox(height: 12), TextField(controller: _noteController, onChanged: (v) => med['note'] = v, maxLines: 2, decoration: InputDecoration(hintText: "Notes...", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ])),
    ]);
  }

  Widget _sectionTitle(String t, IconData i) => Row(children: [Icon(i, size: 16, color: AppColors.primary), const SizedBox(width: 8), Text(t, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5))]);
  Widget _dropdownHeader(Map<String, dynamic> med, String key, List<String> items) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: med[key], isDense: true, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary), items: items.map((v) => DropdownMenuItem(value: v, child: Text(v.toUpperCase()))).toList(), onChanged: (v) => setState(() => med[key] = v))));
  Widget _statusToggle(Map<String, dynamic> med) => InkWell(onTap: () => setState(() => med['status'] = med['status'] == 'Active' ? 'Stopped' : 'Active'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: med['status'] == 'Active' ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: med['status'] == 'Active' ? Colors.green : Colors.red)), child: Text(med['status'].toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green))));
  Widget _doseButton(Map<String, dynamic> med, String val) { bool isSel = med['dosage'] == val; return InkWell(onTap: () => setState(() => med['dosage'] = val), child: Container(width: 50, height: 50, alignment: Alignment.center, decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, shape: BoxShape.circle, border: Border.all(color: isSel ? AppColors.primary : AppColors.border)), child: Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSel ? Colors.white : AppColors.textPrimary)))); }
  Widget _customDoseInput(Map<String, dynamic> med) => Container(width: 80, height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: AppColors.border)), child: Center(child: DropdownButtonHideUnderline(child: DropdownButton<String>(hint: const Text("Custom", style: TextStyle(fontSize: 10)), value: _doseOptions.contains(med['dosage']) ? null : med['dosage'], items: List.generate(50, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => med['dosage'] = v)))));
  Widget _timingBlock(String label, IconData icon, Map<String, dynamic> med, String k1, String k2) => Container(decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)), child: Column(children: [Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 18, color: AppColors.textSecondary)), const Divider(height: 1), _timeToggle("Before", med[k1], (v) => setState(() => med[k1] = v)), const Divider(height: 1), _timeToggle("After", med[k2], (v) => setState(() => med[k2] = v))]));
  Widget _timeToggle(String text, bool active, Function(bool) onTap) => InkWell(onTap: () => onTap(!active), child: Container(height: 34, alignment: Alignment.center, color: active ? AppColors.primary : Colors.transparent, child: Text(text, style: TextStyle(fontSize: 10, color: active ? Colors.white : AppColors.textSecondary, fontWeight: active ? FontWeight.bold : FontWeight.normal))));
  Widget _durationChip(Map<String, dynamic> med, String val) { bool isSel = med['duration'] == val; return InkWell(onTap: () => setState(() => med['duration'] = val), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: isSel ? AppColors.textPrimary : Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSel ? Colors.white : AppColors.textSecondary)))); }
  Widget _customDurationInput(Map<String, dynamic> med) => Container(width: 120, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Row(children: [Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _customDurationController.text.isNotEmpty ? _customDurationController.text : null, items: List.generate(30, (i) => (i + 1).toString()).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { setState(() { _customDurationController.text = v!; med['duration'] = "$v$_customDurationUnit"; }); }))), DropdownButtonHideUnderline(child: DropdownButton<String>(value: _customDurationUnit, items: ['d','w','m','y'].map((u) => DropdownMenuItem(value: u, child: Text(u.toUpperCase()))).toList(), onChanged: (v) { setState(() { _customDurationUnit = v!; med['duration'] = "${_customDurationController.text}$v"; }); }))]));
  Widget _noteShortcuts(Map<String, dynamic> med) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ["Once a day", "Once a week", "Once a month", "Once a year", "STAT"].map((n) => Padding(padding: const EdgeInsets.only(right: 6), child: InkWell(onTap: () { setState(() { _noteController.text = n; med['note'] = n; }); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text(n, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)))))).toList()));
}
