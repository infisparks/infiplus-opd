import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class PatientVitalsTrend extends StatefulWidget {
  final String patientUhid;
  final int? currentOpdId;

  const PatientVitalsTrend({super.key, required this.patientUhid, this.currentOpdId});

  @override
  State<PatientVitalsTrend> createState() => _PatientVitalsTrendState();
}

class _PatientVitalsTrendState extends State<PatientVitalsTrend> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _vitalsData = [];

  // UI Constants
  final double _rowHeight = 56.0;
  final double _labelColumnWidth = 140.0;
  final double _dataColumnWidth = 90.0;

  @override
  void initState() {
    super.initState();
    _fetchVitals();
  }

  @override
  void didUpdateWidget(covariant PatientVitalsTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientUhid != widget.patientUhid) {
      _fetchVitals();
    }
  }

  Future<void> _fetchVitals() async {
    setState(() {
      _isLoading = true;
      _vitalsData = [];
    });

    try {
      // 1. Fetch using standard select() which is more robust than naming specific columns
      final response = await Supabase.instance.client
          .from('opd_registration')
          .select() 
          .eq('uhid', widget.patientUhid)
          .order('created_at', ascending: false)
          .limit(10); 

      if (mounted) {
        List<Map<String, dynamic>> results = (response as List).map((row) => {
          'id':      row['id'],
          'created_at': row['created_at'],
          'bp':      row['bp']?.toString() ?? '',
          'pulse':   row['pulse']?.toString() ?? '',
          'weight':  row['weight']?.toString() ?? '',
          'spo2':    row['spo2']?.toString() ?? '',
          'temp':    row['temp']?.toString() ?? '',
          'sugar':   row['sugar']?.toString() ?? '',
        }).toList();

        // Check if currentOpdId is in the list
        if (widget.currentOpdId != null) {
          final currentExists = results.any((r) => r['id'] == widget.currentOpdId);
          if (!currentExists) {
            results.insert(0, {
              'id':      widget.currentOpdId,
              'created_at': DateTime.now().toIso8601String(),
              'bp':      '', 'pulse': '', 'weight': '', 'spo2': '', 'temp': '', 'sugar': '',
            });
          }
        }

        setState(() {
          _vitalsData = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching vitals trend tracking: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateVital(int opdId, String field, String value) async {
    try {
      await Supabase.instance.client
          .from('opd_registration')
          .update({field: value})
          .eq('id', opdId);
      
      // Update local state without re-fetching
      setState(() {
        final index = _vitalsData.indexWhere((v) => v['id'] == opdId);
        if (index != -1) {
          _vitalsData[index][field] = value;
        }
      });
    } catch (e) {
      debugPrint("Update Vital Error: $e");
    }
  }

  String _formatDateLine1(String? dateStr) {
    if (dateStr == null) return "-";
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM').format(date);
    } catch (e) { return "-"; }
  }

  String _formatDateLine2(String? dateStr) {
    if (dateStr == null) return "";
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('yyyy').format(date);
    } catch (e) { return ""; }
  }

  @override
  Widget build(BuildContext context) {
    // Modern Container Styling
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER SECTION ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Vitals History & Trend",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text("Trend over last ${_vitalsData.length} visits • Interactive Grid",
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                InkWell(
                  onTap: _fetchVitals,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue.withAlpha(15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.refresh_rounded, size: 22, color: Colors.blue.shade700),
                  ),
                )
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),

          // --- CONTENT SECTION ---
          _isLoading ? _buildLoadingState() : 
                  _vitalsData.isEmpty ? _buildEmptyState() : _buildDataGrid(),
        ],
      ),
    );
  }

  // --- SPLIT VIEW GRID (Sticky Labels + Scrollable Data) ---
  Widget _buildDataGrid() {
    // Total 6 rows: visit date + 5 vital metrics
    return SizedBox(
      height: _rowHeight * 7, 
      child: Row(
        children: [
          // 1. FIXED LEFT COLUMN (Labels)
          Container(
            width: _labelColumnWidth,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFixedHeaderCell("Visit Date"),
                _buildFixedLabelCell("Blood Pressure", Icons.favorite_outline_rounded, Colors.red.shade400),
                _buildFixedLabelCell("Pulse Rate", Icons.monitor_heart_outlined, Colors.blue.shade400),
                _buildFixedLabelCell("SpO2 (%)", Icons.opacity_rounded, Colors.cyan.shade500),
                _buildFixedLabelCell("Sugar (mg/dL)", Icons.water_drop_outlined, const Color(0xFF10B981)),
                _buildFixedLabelCell("Body Weight (kg)", Icons.monitor_weight_outlined, Colors.orange.shade400),
              ],
            ),
          ),

          // 2. SCROLLABLE RIGHT AREA (Data)
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 4,
              radius: const Radius.circular(4),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _vitalsData.asMap().entries.map((entry) {
                    int index = entry.key;
                    var data = entry.value;
                    bool isLatest = index == 0; // Highlight the first column

                    return Container(
                      width: _dataColumnWidth,
                      color: isLatest ? Colors.blue.withAlpha(10) : Colors.transparent, // Highlight latest
                      child: Column(
                        children: [
                          _buildDateHeaderCell(data['created_at'], isLatest),
                          _buildEditableCell(data['id'], 'bp', data['bp']?.toString() ?? "", isBold: true, keyboardType: TextInputType.datetime), // BP needs slash
                          _buildEditableCell(data['id'], 'pulse', data['pulse']?.toString() ?? "", unit: "bpm"),
                          _buildEditableCell(data['id'], 'spo2', data['spo2']?.toString() ?? "", unit: "%"),
                          _buildEditableCell(data['id'], 'sugar', data['sugar']?.toString() ?? "", unit: ""),
                          _buildEditableCell(data['id'], 'weight', data['weight']?.toString() ?? "", unit: "kg"),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildEmptyState() {
    return Container(
      height: 150,
      width: double.infinity,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text("No vitals recorded yet", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: _rowHeight * 6,
      child: Center(
        child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade200),
        ),
      ),
    );
  }

  Widget _buildFixedHeaderCell(String text) {
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.only(left: 20, top: 18),
      alignment: Alignment.topLeft,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildFixedLabelCell(String text, IconData icon, Color iconColor) {
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade50)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeaderCell(String? dateStr, bool isLatest) {
    return Container(
      height: _rowHeight,
      width: _dataColumnWidth,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: isLatest ? const Border(bottom: BorderSide(color: Colors.blue, width: 2)) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatDateLine1(dateStr),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isLatest ? Colors.blue.shade700 : const Color(0xFF1E293B),
            ),
          ),
          Text(
            _formatDateLine2(dateStr),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableCell(int id, String field, String value, {String? unit, bool isBold = false, TextInputType keyboardType = const TextInputType.numberWithOptions(decimal: true)}) {
    return _CellEditor(
      value: value,
      unit: unit,
      isBold: isBold,
      keyboardType: keyboardType,
      onSave: (val) => _updateVital(id, field, val),
    );
  }
}

class _CellEditor extends StatefulWidget {
  final String value;
  final String? unit;
  final bool isBold;
  final TextInputType keyboardType;
  final Function(String) onSave;

  const _CellEditor({required this.value, this.unit, this.isBold = false, required this.onSave, required this.keyboardType});

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_CellEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isEditing) {
      _controller.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
        child: TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: widget.keyboardType,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          onSubmitted: (val) {
            setState(() => _isEditing = false);
            widget.onSave(val);
          },
          onTapOutside: (_) {
            setState(() => _isEditing = false);
            widget.onSave(_controller.text);
          },
        ),
      );
    }

    bool isEmpty = widget.value.isEmpty || widget.value == "--";
    return InkWell(
      onTap: () => setState(() => _isEditing = true),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade100)),
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: isEmpty ? "--" : widget.value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: widget.isBold && !isEmpty ? FontWeight.w900 : FontWeight.w500,
                  color: isEmpty ? Colors.grey.shade300 : const Color(0xFF334155),
                ),
              ),
              if (!isEmpty && widget.unit != null && widget.unit!.isNotEmpty)
                TextSpan(
                  text: " ${widget.unit}",
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
      ),
    );
  }
}