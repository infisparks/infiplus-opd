import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../supabase_handler.dart';


class BloodTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF8FAFC);
  static const Color textMain = Color(0xFF1E293B);
  static const Color textSub = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
}

class BloodTestTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const BloodTestTab({super.key, required this.patient, required this.opdId});

  @override
  State<BloodTestTab> createState() => _BloodTestTabState();
}

class _BloodTestTabState extends State<BloodTestTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _masterParams = [];
  List<Map<String, dynamic>> _records = [];
  Set<int> _dirtyRecordIds = {};
  String _searchQuery = "";
  Timer? _debounce;

  // Controllers for adding new param
  final TextEditingController _paramsSearchController = TextEditingController();
  final TextEditingController _newNameController = TextEditingController();
  final TextEditingController _newUnitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _paramsSearchController.dispose();
    _newNameController.dispose();
    _newUnitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Master Parameters from opd_datasets
      final datasetResponse = await SupabaseHandler.client
          .from('opd_datasets')
          .select('datajson')
          .eq('dataname', 'investigations')
          .maybeSingle();

      if (datasetResponse != null && datasetResponse['datajson'] is List) {
        _masterParams = (datasetResponse['datajson'] as List).map((e) {
          if (e is String) return {'name': e, 'unit': '', 'isHidden': false};
          return Map<String, dynamic>.from(e);
        }).toList();
      }

      // 2. Fetch Records (History) for this patient
      final historyResponse = await SupabaseHandler.client
          .from('opd_registration')
          .select('id, created_at, clinical_data')
          .eq('uhid', widget.patient.id)
          .order('created_at', ascending: false) // Latest (Today) comes first (Leftmost)
          .limit(10);

      if (historyResponse != null) {
        _records = (historyResponse as List).map((r) {
          Map<String, dynamic> clinical = {};
          if (r['clinical_data'] != null) {
            clinical = Map<String, dynamic>.from(r['clinical_data']);
          }
          // We use 'investigation_values' key inside clinical_data for these results
          Map<String, dynamic> values = {};
          if (clinical['investigation_values'] != null) {
            values = Map<String, dynamic>.from(clinical['investigation_values']);
          }
          
          return {
            'id': r['id'],
            'created_at': r['created_at'],
            'values': values,
          };
        }).toList();
      }

      // Sort _masterParams so that parameters with values are on top
      var indexedParams = _masterParams.asMap().entries.toList();
      indexedParams.sort((aEntry, bEntry) {
        var a = aEntry.value;
        var b = bEntry.value;
        bool aHasValue = _records.any((r) {
          final val = r['values'][a['name']]?.toString();
          return val != null && val.trim().isNotEmpty;
        });
        bool bHasValue = _records.any((r) {
          final val = r['values'][b['name']]?.toString();
          return val != null && val.trim().isNotEmpty;
        });

        if (aHasValue && !bHasValue) return -1;
        if (!aHasValue && bHasValue) return 1;
        return aEntry.key.compareTo(bEntry.key);
      });
      _masterParams = indexedParams.map((e) => e.value).toList();

    } catch (e) {
      debugPrint("Error loading BloodTestTab: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onValueChange(int recordId, String paramName, String value) {
    setState(() {
      final recordIndex = _records.indexWhere((r) => r['id'] == recordId);
      if (recordIndex != -1) {
        _records[recordIndex]['values'][paramName] = value;
      }
      _dirtyRecordIds.add(recordId);
    });
    _autoSave();
  }

  void _autoSave() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      if (_dirtyRecordIds.isEmpty) return;
      setState(() => _isSaving = true);
      
      try {
        for (int id in _dirtyRecordIds) {
          final record = _records.firstWhere((r) => r['id'] == id);
          
          // Fetch current clinical data to merge
          final current = await SupabaseHandler.client
              .from('opd_registration')
              .select('clinical_data')
              .eq('id', id)
              .maybeSingle();
              
          Map<String, dynamic> clinical = {};
          if (current != null && current['clinical_data'] != null) {
            clinical = Map<String, dynamic>.from(current['clinical_data']);
          }
          
          clinical['investigation_values'] = record['values'];
          
          await SupabaseHandler.client
              .from('opd_registration')
              .update({'clinical_data': clinical})
              .eq('id', id);
        }
        _dirtyRecordIds.clear();
      } catch (e) {
        debugPrint("Error saving BloodTest data: $e");
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    });
  }

  void _addNewParam() async {
    final name = _newNameController.text.trim();
    if (name.isEmpty) return;

    final newParam = {
      'name': name.toUpperCase(),
      'unit': _newUnitController.text.toUpperCase().trim(),
      'isHidden': false
    };

    setState(() {
      _masterParams.add(newParam);
      _newNameController.clear();
      _newUnitController.clear();
    });

    try {
      await SupabaseHandler.client
          .from('opd_datasets')
          .upsert({
            'dataname': 'investigations',
            'datajson': _masterParams,
          }, onConflict: 'dataname');
    } catch (e) {
      debugPrint("Error updating investigations dataset: $e");
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final filteredParams = _masterParams.where((p) {
      if (p['isHidden'] == true) return false;
      if (_searchQuery.isEmpty) return true;
      return p['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: BloodTheme.background,
      body: Column(
        children: [
          // Header Bar
          _buildHeaderBar(),
          
          // Main Table
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildTable(filteredParams),
              ),
            ),
          ),
          
          // Footer
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: BloodTheme.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("BLOOD TEST TIMELINE", 
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: BloodTheme.textMain, letterSpacing: 1)),
              Text("MEDICAL HISTORY", 
                style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: BloodTheme.textSub)),
            ],
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: BloodTheme.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 16, color: BloodTheme.textSub),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: "Quick search parameter...",
                        hintStyle: TextStyle(color: BloodTheme.textSub),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          _buildSyncIndicator(),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _showAddParamDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: BloodTheme.textMain,
              elevation: 0,
              side: const BorderSide(color: BloodTheme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Add Parameter", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncIndicator() {
    if (_isSaving) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: BloodTheme.primary)),
            const SizedBox(width: 8),
            Text("SAVING...", style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w800, color: BloodTheme.primary)),
          ],
        ),
      );
    }
    if (_dirtyRecordIds.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text("DRAFTING...", style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.orange)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text("SAVED", style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.green)),
        ],
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> params) {
    if (params.isEmpty && _searchQuery.isNotEmpty) {
      return Container(
        width: MediaQuery.of(context).size.width,
        padding: const EdgeInsets.all(64),
        child: const Center(child: Text("No parameters found", style: TextStyle(color: BloodTheme.textSub, fontWeight: FontWeight.bold))),
      );
    }

    return DataTable(
      horizontalMargin: 20,
      columnSpacing: 32,
      headingRowHeight: 64,
      dataRowMinHeight: 84,
      dataRowMaxHeight: 84,
      border: const TableBorder(
        horizontalInside: BorderSide(color: Color(0xFFF1F5F9)),
      ),
      columns: [
        DataColumn(label: _buildColumnHeader("PARAMETER NAME", "Hold to hide")),
        DataColumn(label: _buildColumnHeader("UNIT", "")),
        ..._records.map((r) {
          final isCurrent = r['id'] == widget.opdId;
          final dateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(r['created_at']));
          return DataColumn(
            label: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(dateStr, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, color: isCurrent ? BloodTheme.primary : BloodTheme.textSub)),
                if (isCurrent)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: BloodTheme.primary, borderRadius: BorderRadius.circular(4)),
                    child: const Text("Current visit", style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          );
        }),
      ],
      rows: params.map((p) {
        return DataRow(
          cells: [
            DataCell(
              GestureDetector(
                onLongPress: () => _confirmHideParam(p['name']),
                child: Text(p['name'], style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: BloodTheme.textMain)),
              ),
            ),
            DataCell(Text(p['unit'] ?? '', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: BloodTheme.textSub, fontStyle: FontStyle.italic))),
            ..._records.map((r) {
              final isCurrent = r['id'] == widget.opdId;
              final val = r['values'][p['name']]?.toString() ?? "";
              return DataCell(
                Container(
                  width: 130,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCurrent ? BloodTheme.primary.withAlpha(15) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isCurrent ? BloodTheme.primary.withAlpha(80) : BloodTheme.border, width: 1.5),
                  ),
                  child: TextField(
                    onChanged: (v) => _onValueChange(r['id'], p['name'], v),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: isCurrent ? BloodTheme.primary : BloodTheme.textMain),
                    decoration: InputDecoration(
                      hintText: "—",
                      hintStyle: TextStyle(color: Colors.grey[300], fontSize: 16),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                      isDense: true,
                    ),
                    controller: TextEditingController(text: val)..selection = TextSelection.fromPosition(TextPosition(offset: val.length)),
                  ),
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildColumnHeader(String title, String sub) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, color: BloodTheme.textSub, letterSpacing: 0.5)),
        if (sub.isNotEmpty)
          Text(sub, style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w600, color: BloodTheme.primary.withAlpha(150))),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BloodTheme.border)),
      ),
      child: Row(
        children: [
          _footerStatus(BloodTheme.primary, "Active Data Point"),
          const SizedBox(width: 24),
          _footerStatus(Colors.orange, "Unsaved Edit"),
          const Spacer(),
          Text("${_records.length} VISIT POINTS • SCROLL RIGHT FOR HISTORY", 
            style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: BloodTheme.textSub, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _footerStatus(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label.toUpperCase(), style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: BloodTheme.textSub)),
      ],
    );
  }

  void _showAddParamDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("NEW PARAMETER", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newNameController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "NAME", labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                hintText: "e.g. VITAMIN B12",
                filled: true, fillColor: BloodTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newUnitController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "UNIT", labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                hintText: "e.g. PG/ML",
                filled: true, fillColor: BloodTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: _addNewParam,
            style: ElevatedButton.styleFrom(backgroundColor: BloodTheme.primary, foregroundColor: Colors.white),
            child: const Text("CREATE"),
          ),
        ],
      ),
    );
  }

  void _confirmHideParam(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hide Parameter?"),
        content: Text("Are you sure you want to hide '$name' globally?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
          TextButton(
            onPressed: () async {
              setState(() {
                final idx = _masterParams.indexWhere((p) => p['name'] == name);
                if (idx != -1) _masterParams[idx]['isHidden'] = true;
              });
              try {
                await SupabaseHandler.client
                    .from('opd_datasets')
                    .update({'datajson': _masterParams})
                    .eq('dataname', 'investigations');
              } catch (e) {}
              Navigator.pop(context);
            },
            child: const Text("Yes, Hide"),
          ),
        ],
      ),
    );
  }
}
