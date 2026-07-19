import 'dart:async';
import 'package:flutter/material.dart';
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

  // Cached TextStyle constants for ultra-fast rendering (0 font resolution overhead)
  static const TextStyle paramStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMain,
    fontFamily: 'Roboto',
  );
  static const TextStyle unitStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textSub,
    fontStyle: FontStyle.italic,
    fontFamily: 'Roboto',
  );
  static const TextStyle headerStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: textSub,
    letterSpacing: 0.5,
    fontFamily: 'Roboto',
  );
  static const TextStyle inputStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textMain,
    fontFamily: 'Roboto',
  );
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
  final Set<int> _dirtyRecordIds = {};
  String _searchQuery = "";
  Timer? _debounce;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
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
    _searchController.dispose();
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

      _records = (historyResponse as List).map((r) {
        Map<String, dynamic> clinical = {};
        if (r['clinical_data'] != null) {
          clinical = Map<String, dynamic>.from(r['clinical_data']);
        }
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

      // Sort _masterParams so parameters with values are on top
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
    final recordIndex = _records.indexWhere((r) => r['id'] == recordId);
    if (recordIndex != -1) {
      _records[recordIndex]['values'][paramName] = value;
    }
    final wasEmpty = _dirtyRecordIds.isEmpty;
    _dirtyRecordIds.add(recordId);

    // Only update sync status state if transition occurs (Saved -> Drafting)
    if (wasEmpty && mounted) {
      setState(() {});
    }
    _autoSave();
  }

  void _autoSave() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      if (_dirtyRecordIds.isEmpty) return;
      if (mounted) setState(() => _isSaving = true);

      try {
        for (int id in _dirtyRecordIds) {
          final record = _records.firstWhere((r) => r['id'] == id);

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
      await SupabaseHandler.client.from('opd_datasets').upsert({
        'dataname': 'investigations',
        'datajson': _masterParams,
      }, onConflict: 'dataname');
    } catch (e) {
      debugPrint("Error updating investigations dataset: $e");
    }
    if (!mounted) return;
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            // Header Bar
            _buildHeaderBar(),

            // Virtualized Lightweight Table Content
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (filteredParams.isEmpty && _searchQuery.isNotEmpty) {
                    return const Center(
                      child: Text(
                        "No parameters found",
                        style: TextStyle(color: BloodTheme.textSub, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    );
                  }

                  bool useDualColumn = _records.length <= 2 && constraints.maxWidth >= 650;

                  if (useDualColumn) {
                    return _buildDualColumnView(filteredParams);
                  }

                  return _buildSingleColumnView(filteredParams);
                },
              ),
            ),

            // Footer Status Bar
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: BloodTheme.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "BLOOD TEST TIMELINE",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: BloodTheme.textMain, letterSpacing: 0.5),
              ),
              Text(
                "MEDICAL HISTORY",
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: BloodTheme.textSub),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: BloodTheme.background,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: BloodTheme.textSub),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: "Quick search parameter...",
                        hintStyle: TextStyle(color: BloodTheme.textSub, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildSyncIndicator(),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showAddParamDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: BloodTheme.textMain,
              elevation: 0,
              side: const BorderSide(color: BloodTheme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.add, size: 15),
            label: const Text("Add Parameter", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncIndicator() {
    if (_isSaving) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
        child: Row(
          children: const [
            SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 2, color: BloodTheme.primary)),
            SizedBox(width: 6),
            Text("SAVING...", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: BloodTheme.primary)),
          ],
        ),
      );
    }
    if (_dirtyRecordIds.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(6)),
        child: Row(
          children: [
            Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text("DRAFTING...", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.orange)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text("SAVED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.green)),
        ],
      ),
    );
  }

  // --- LIGHTWEIGHT DUAL-COLUMN VIEW (0 LAG, VIRTUALIZED LIST) ---
  Widget _buildDualColumnView(List<Map<String, dynamic>> params) {
    int mid = (params.length / 2).ceil();
    final leftParams = params.sublist(0, mid);
    final rightParams = params.sublist(mid);

    return Column(
      children: [
        // Dual Column Sticky Header
        Container(
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: BloodTheme.border)),
          ),
          child: Row(
            children: [
              Expanded(child: _buildTableHeaderSection()),
              Container(width: 1, color: BloodTheme.border),
              Expanded(child: _buildTableHeaderSection()),
            ],
          ),
        ),
        // Synced Virtualized Body List (Only renders visible rows!)
        Expanded(
          child: ListView.builder(
            itemCount: mid,
            itemExtent: 38, // Fixed row height for instant 60/120fps scrolling
            itemBuilder: (context, index) {
              final leftItem = leftParams[index];
              final rightItem = index < rightParams.length ? rightParams[index] : null;

              return Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildParamRow(leftItem)),
                    Container(width: 1, color: BloodTheme.border),
                    Expanded(
                      child: rightItem != null ? _buildParamRow(rightItem) : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- LIGHTWEIGHT SINGLE-COLUMN VIEW ---
  Widget _buildSingleColumnView(List<Map<String, dynamic>> params) {
    double totalWidth = 220.0 + (_records.length * 118.0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            // Header
            Container(
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: BloodTheme.border)),
              ),
              child: _buildTableHeaderSection(),
            ),
            // Virtualized Body
            Expanded(
              child: ListView.builder(
                itemCount: params.length,
                itemExtent: 38,
                itemBuilder: (context, index) {
                  return Container(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                    ),
                    child: _buildParamRow(params[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header content builder
  Widget _buildTableHeaderSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text("PARAMETER NAME", style: BloodTheme.headerStyle),
          ),
          const SizedBox(
            width: 55,
            child: Text("UNIT", style: BloodTheme.headerStyle),
          ),
          ..._records.map((r) {
            final isCurrent = r['id'] == widget.opdId;
            final dateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(r['created_at']));
            return SizedBox(
              width: 110,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? BloodTheme.primary : BloodTheme.textSub,
                    ),
                  ),
                  if (isCurrent)
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: BloodTheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        "Current visit",
                        style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
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

  // Row content builder (ultra light)
  Widget _buildParamRow(Map<String, dynamic> p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Parameter Name
          Expanded(
            flex: 3,
            child: GestureDetector(
              onLongPress: () => _confirmHideParam(p['name']),
              child: Text(
                p['name'],
                style: BloodTheme.paramStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Unit
          SizedBox(
            width: 55,
            child: Text(
              p['unit'] ?? '',
              style: BloodTheme.unitStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Values per record
          ..._records.map((r) {
            final isCurrent = r['id'] == widget.opdId;
            final val = r['values'][p['name']]?.toString() ?? "";
            return Container(
              width: 110,
              padding: const EdgeInsets.only(right: 6),
              alignment: Alignment.centerLeft,
              child: _BloodTestCellInput(
                key: ValueKey("${r['id']}_${p['name']}"),
                initialValue: val,
                isCurrentVisit: isCurrent,
                onChanged: (v) => _onValueChange(r['id'], p['name'], v),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BloodTheme.border)),
      ),
      child: Row(
        children: [
          _footerStatus(BloodTheme.primary, "Active Data Point"),
          const SizedBox(width: 16),
          _footerStatus(Colors.orange, "Unsaved Edit"),
          const Spacer(),
          Text(
            "${_records.length} VISITS • 0-LAG ULTRA FAST LIGHT",
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: BloodTheme.textSub, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _footerStatus(Color color, String label) {
    return Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: BloodTheme.textSub)),
      ],
    );
  }

  void _showAddParamDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text("NEW PARAMETER", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newNameController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "NAME",
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                hintText: "e.g. VITAMIN B12",
                filled: true,
                fillColor: BloodTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newUnitController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "UNIT",
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                hintText: "e.g. PG/ML",
                filled: true,
                fillColor: BloodTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(fontSize: 12))),
          ElevatedButton(
            onPressed: _addNewParam,
            style: ElevatedButton.styleFrom(backgroundColor: BloodTheme.primary, foregroundColor: Colors.white),
            child: const Text("CREATE", style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _confirmHideParam(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hide Parameter?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to hide '$name' globally?", style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("No", style: TextStyle(fontSize: 12))),
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
              } catch (e) {
                debugPrint("Error hiding parameter: $e");
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text("Yes, Hide", style: TextStyle(fontSize: 12, color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// Lightweight Cell Input (No rebuild loops, minimal overhead)
class _BloodTestCellInput extends StatefulWidget {
  final String initialValue;
  final bool isCurrentVisit;
  final ValueChanged<String> onChanged;

  const _BloodTestCellInput({
    super.key,
    required this.initialValue,
    required this.isCurrentVisit,
    required this.onChanged,
  });

  @override
  State<_BloodTestCellInput> createState() => _BloodTestCellInputState();
}

class _BloodTestCellInputState extends State<_BloodTestCellInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _BloodTestCellInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 30,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: widget.isCurrentVisit ? BloodTheme.primary.withAlpha(12) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: widget.isCurrentVisit ? BloodTheme.primary.withAlpha(80) : BloodTheme.border,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        textAlign: TextAlign.left,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: BloodTheme.inputStyle,
        decoration: const InputDecoration(
          hintText: "—",
          hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
