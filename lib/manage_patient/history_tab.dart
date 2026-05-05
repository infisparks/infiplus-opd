import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../supabase_handler.dart';
import '../services/server_data_service.dart';

class HistoryTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF1F5F9);
  static const Color textMain = Color(0xFF1E293B);
  static const Color textSub = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
}

class HistoryTab extends StatefulWidget {
  final Patient patient;
  final int currentOpdId;

  const HistoryTab({super.key, required this.patient, required this.currentOpdId});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isLoading = true;
  List<Map<String, dynamic>> _visits = [];
  int _selectedIndex = 0;
  String _searchTerm = "";
  int? _copiedId;

  // Detailed data for the selected visit
  Map<int, Map<String, dynamic>> _visitDetails = {};
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _fetchVisitDetails(int opdId) async {
    if (_visitDetails.containsKey(opdId)) return; // Already cached for this session
    
    setState(() => _isLoadingDetails = true);
    try {
      final results = await Future.wait([
        SupabaseHandler.client.from('opd_reg_symptoms').select().eq('opd_id', opdId),
        SupabaseHandler.client.from('opd_reg_diagnosis').select().eq('opd_id', opdId),
        SupabaseHandler.client.from('opd_reg_rx').select().eq('opd_id', opdId),
        SupabaseHandler.client.from('opd_reg_reports').select().eq('opd_id', opdId),
      ]);

      _visitDetails[opdId] = {
        'symptoms': results[0] as List,
        'diagnosis': results[1] as List,
        'rx': results[2] as List,
        'reports': results[3] as List,
      };
    } catch (e) {
      debugPrint("Error fetching history details: $e");
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final response = await SupabaseHandler.client
          .from('opd_registration')
          .select('*')
          .eq('uhid', widget.patient.id)
          .neq('id', widget.currentOpdId)
          .order('created_at', ascending: false);

      if (response != null && response is List) {
        _visits = List<Map<String, dynamic>>.from(response);
        if (_visits.isNotEmpty) {
          _fetchVisitDetails(_visits[_selectedIndex]['id']);
        }
      }
    } catch (e) {
      debugPrint("Error loading history: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCopy(Map<String, dynamic> visit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reassign History?"),
        content: const Text("This will overwrite your current consultation draft with data from this visit. Shall we proceed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("YES, REASSIGN")),
        ],
      ),
    );

    if (confirmed != true) return;

    if (_isLoadingDetails) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please wait, loading visit details...")));
      return;
    }

    try {
      final opdId = widget.currentOpdId;
      final details = _visitDetails[visit['id']];

      if (details == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Visit details not available.")));
        return;
      }

      // 1. Treatment (RX)
      final rxList = details?['rx'] as List?;
      if (rxList != null && rxList.isNotEmpty) {
        final mappedRx = rxList.map((e) => {
          'id': e['id'].toString(),
          'name': e['medicine_name'],
          'type': e['medicine_type'],
          'unit': e['unit'] ?? '',
          'dosage': e['dosage'] ?? '',
          'duration': e['duration'] ?? '',
          'timing': e['timing_json'] ?? {},
          'note': e['note'] ?? '',
        }).toList();
        await ServerDataService.saveData(opdId, 'treatment_data', mappedRx);
      }
      
      // 2. Symptoms
      final symList = details?['symptoms'] as List?;
      if (symList != null && symList.isNotEmpty) {
        final mappedSym = symList.map((e) => {
          'name': e['name'],
          'note': e['note'] ?? '',
          'duration': e['duration'] ?? '',
          'severity': e['severity'] ?? '',
          'custom_groups': e['custom_groups'] ?? [],
          'selected_options': e['selected_options'] ?? [],
        }).toList();
        await ServerDataService.saveData(opdId, 'symptoms', mappedSym);
      }
      
      // 3. Diagnosis
      final diagList = details?['diagnosis'] as List?;
      if (diagList != null && diagList.isNotEmpty) {
        final mappedDiag = diagList.map((e) => {
          'name': e['name'],
          'note': e['note'] ?? '',
        }).toList();
        await ServerDataService.saveData(opdId, 'diagnosis_data', mappedDiag);
      }

      // 4. Instructions/Investigations/Procedures (Reports)
      final reports = details?['reports'] as List?;
      if (reports != null && reports.isNotEmpty) {
        Map<String, dynamic> instructionsData = {
          'instructions': reports.where((r) => r['report_type'] == 'instruction').map((r) => r['item_name']).toList(),
          'investigations': reports.where((r) => r['report_type'] == 'investigation').map((r) => r['item_name']).toList(),
          'procedures': reports.where((r) => r['report_type'] == 'procedure').map((r) => r['item_name']).toList(),
        };
        await ServerDataService.saveData(opdId, 'instructions_data', instructionsData);
      }

      // 5. Clinical Data (Checkup, Fitness, Notes)
      // Check labels in main row
      if (visit['clinical_data'] != null) {
        final clinical = Map<String, dynamic>.from(visit['clinical_data']);
        if (clinical['checkup_data'] != null) {
          await ServerDataService.saveData(opdId, 'checkup_data', clinical['checkup_data']);
        }
        if (clinical['fitness_data'] != null) {
          await ServerDataService.saveData(opdId, 'fitness_data', clinical['fitness_data']);
        }
        if (clinical['clinical_notes'] != null || visit['clinical_notes'] != null) {
          await ServerDataService.saveData(opdId, 'clinical_notes', clinical['clinical_notes'] ?? visit['clinical_notes']);
        }
      } else if (visit['clinical_notes'] != null) {
         await ServerDataService.saveData(opdId, 'clinical_notes', visit['clinical_notes']);
      }

      setState(() => _copiedId = visit['id']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Visit #${visit['id']} reassigned successfully!"), backgroundColor: Colors.green),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _copiedId = null);
      });
    } catch (e) {
      debugPrint("Error copying history data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_visits.isEmpty) return _buildEmptyState();

    final filtered = _visits.where((v) {
      final idStr = v['id'].toString();
      final dateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(v['created_at']));
      return idStr.contains(_searchTerm) || dateStr.toLowerCase().contains(_searchTerm.toLowerCase());
    }).toList();

    return Row(
      children: [
        // Sidebar
        _buildSidebar(filtered),
        
        // Preview Area
        Expanded(
          child: filtered.isEmpty ? const Center(child: Text("No visits found")) : _buildPreviewArea(filtered[_selectedIndex]),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No Previous Visits Found", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: HistoryTheme.textSub)),
        ],
      ),
    );
  }

  Widget _buildSidebar(List<Map<String, dynamic>> filtered) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: HistoryTheme.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() { _searchTerm = v; _selectedIndex = 0; }),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search visits...",
                prefixIcon: const Icon(Icons.search, size: 16),
                filled: true, fillColor: HistoryTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final visit = filtered[idx];
                final isSelected = _selectedIndex == idx;
                final dt = DateTime.parse(visit['created_at']);
                
                return InkWell(
                  onTap: () {
                    setState(() => _selectedIndex = idx);
                    _fetchVisitDetails(visit['id']);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? HistoryTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? HistoryTheme.primary : HistoryTheme.border),
                      boxShadow: isSelected ? [BoxShadow(color: HistoryTheme.primary.withAlpha(40), blurRadius: 10, offset: const Offset(0, 4))] : [],
                    ),
                    child: Row(
                      children: [
                        _buildDateBadge(dt, isSelected),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Visit #${visit['id']}", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : HistoryTheme.textMain)),
                              Text(DateFormat('h:mm a • yyyy').format(dt), style: TextStyle(fontSize: 9, color: isSelected ? Colors.white70 : HistoryTheme.textSub)),
                            ],
                          ),
                        ),
                        if (_copiedId == visit['id'])
                           const Icon(Icons.check_circle_rounded, size: 16, color: Colors.greenAccent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBadge(DateTime dt, bool isSelected) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: isSelected ? Colors.white10 : HistoryTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(DateFormat('dd').format(dt), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : HistoryTheme.textMain, height: 1)),
          Text(DateFormat('MMM').format(dt).toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : HistoryTheme.textSub, height: 1)),
        ],
      ),
    );
  }

  Widget _buildPreviewArea(Map<String, dynamic> visit) {
    final dt = DateTime.parse(visit['created_at']);
    
    return Container(
      color: HistoryTheme.background,
      child: Stack(
        children: [
          // Paper Column
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Container(
                  width: 600,
                  constraints: const BoxConstraints(minHeight: 800),
                  padding: const EdgeInsets.all(40),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Paper Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.patient.id, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w900, color: HistoryTheme.textMain)),
                              Text("PREVIOUS CLINICAL RECORD", style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.bold, color: HistoryTheme.textSub, letterSpacing: 1)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("OPD ID: ${visit['id']}", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
                              Text(DateFormat('dd MMM yyyy, h:mm a').format(dt), style: TextStyle(fontSize: 9, color: HistoryTheme.textSub)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 24),

                      // Vitals
                      _buildPreviewSection("Vitals", Icons.monitor_heart_rounded),
                      Row(
                        children: [
                          _vitalChip("BP", "${visit['bp'] ?? '--'}", "mm/Hg"),
                          _vitalChip("Pulse", "${visit['pulse'] ?? '--'}", "bpm"),
                          _vitalChip("Weight", "${visit['weight'] ?? '--'}", "kg"),
                          _vitalChip("SpO2", "${visit['spo2'] ?? '--'}", "%"),
                        ],
                      ),
                      const SizedBox(height: 32),

                      if (_isLoadingDetails)
                        const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
                      else ...[
                        // Symptoms
                        _buildPreviewSection("Chief Complaints / Symptoms", Icons.sick_rounded),
                        _listOrEmpty(_visitDetails[visit['id']]?['symptoms'] ?? visit['symptoms_list_json'], (item) {
                          final name = item is Map ? (item['name'] ?? '') : item.toString();
                          final sev = item is Map ? (item['severity'] ?? '') : '';
                          final dur = item is Map ? (item['duration'] ?? '') : '';
                          final note = item is Map ? (item['note'] ?? '') : '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("• $name ${sev.isNotEmpty ? '($sev)' : ''} ${dur.isNotEmpty ? '- $dur' : ''}", 
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                if (note.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 32),

                        // Diagnosis
                        _buildPreviewSection("Diagnosis", Icons.assignment_ind_rounded),
                        _listOrEmpty(_visitDetails[visit['id']]?['diagnosis'] ?? visit['diagnosis_list_json'], (item) {
                          final isMap = item is Map;
                          final name = isMap ? (item['name'] ?? 'Unknown') : item.toString();
                          final note = isMap ? (item['note'] ?? '') : '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("• $name", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                if (note.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 32),

                        // Medications
                        _buildPreviewSection("Prescribed Medications", Icons.medication_rounded),
                        _rxTable(_visitDetails[visit['id']]?['rx'] ?? visit['rx_list_json']),
                        const SizedBox(height: 32),

                        // Reports (Instructions / Investigations)
                        _buildPreviewSection("Clinical Reports & Instructions", Icons.biotech_rounded),
                        Builder(builder: (context) {
                           final reports = _visitDetails[visit['id']]?['reports'] as List?;
                           if (reports != null && reports.isNotEmpty) {
                             final inst = reports.where((r) => r['report_type'] == 'instruction').map((r) => r['item_name']).toList();
                             final inv = reports.where((r) => r['report_type'] == 'investigation').map((r) => r['item_name']).toList();
                             final proc = reports.where((r) => r['report_type'] == 'procedure').map((r) => r['item_name']).toList();
                             
                             return Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 if (inv.isNotEmpty) ...[
                                   const Text("INVESTIGATIONS:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                   ...inv.map((e) => Text("• $e", style: const TextStyle(fontSize: 12))),
                                   const SizedBox(height: 12),
                                 ],
                                 if (proc.isNotEmpty) ...[
                                   const Text("PROCEDURES:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                   ...proc.map((e) => Text("• $e", style: const TextStyle(fontSize: 12))),
                                   const SizedBox(height: 12),
                                 ],
                                 if (inst.isNotEmpty) ...[
                                   const Text("INSTRUCTIONS:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                   ...inst.map((e) => Text("• $e", style: const TextStyle(fontSize: 12))),
                                 ],
                               ],
                             );
                           }
                           return const Text("None recorded", style: TextStyle(fontSize: 12, color: HistoryTheme.textSub));
                        }),
                        const SizedBox(height: 32),
                      ],

                      // Clinical Notes
                      _buildPreviewSection("Clinical Notes", Icons.sticky_note_2_rounded),
                      Text(visit['clinical_notes'] ?? "No additional notes provided.", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: HistoryTheme.textSub)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Floating Action Bar
          Positioned(
            top: 24, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                  
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _selectedIndex < _visits.length - 1 ? () => setState(() => _selectedIndex++) : null,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                    ),
                    const SizedBox(width: 12),
                    Text(DateFormat('dd MMMM yyyy').format(dt).toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w900, color: HistoryTheme.textMain)),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _selectedIndex > 0 ? () => setState(() => _selectedIndex--) : null,
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _handleCopy(visit),
                      style: ElevatedButton.styleFrom(backgroundColor: HistoryTheme.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text("REASSIGN DATA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 14, color: HistoryTheme.primary),
          const SizedBox(width: 8),
          Text(title.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w900, color: HistoryTheme.primary, letterSpacing: 1)),
          const SizedBox(width: 12),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _vitalChip(String label, String val, String unit) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: HistoryTheme.textSub)),
          Text(val, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w900, color: HistoryTheme.textMain)),
          Text(unit, style: const TextStyle(fontSize: 8, color: HistoryTheme.textSub)),
        ],
      ),
    );
  }

  Widget _rxTable(dynamic list) {
    if (list == null || (list as List).isEmpty) return const Text("None prescribed", style: TextStyle(fontSize: 12, color: HistoryTheme.textSub));
    
    return Column(
      children: (list as List).map((rx) {
        final name = rx is Map ? (rx['medicine_name'] ?? rx['name'] ?? '') : rx.toString();
        final dosage = rx is Map ? (rx['dosage'] ?? '') : '';
        final duration = rx is Map ? (rx['duration'] ?? '') : '';
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              Expanded(child: Text("$dosage", textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
              Expanded(child: Text("$duration", textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _listOrEmpty(dynamic list, Widget Function(dynamic) builder) {
    if (list == null || (list as List).isEmpty) return const Text("Not recorded", style: TextStyle(fontSize: 12, color: HistoryTheme.textSub));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: (list as List).map((e) => builder(e)).toList(),
    );
  }
}
