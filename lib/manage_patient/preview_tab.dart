import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../services/server_data_service.dart';
import 'doctor/doctor_create.dart';
import 'preview_pdf.dart';
import 'pdf_generator.dart';

class PreviewTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color background = Color(0xFFF1F5F9);
  static const Color panelColor = Colors.white;
  static const Color textMain = Color(0xFF1E293B);
  static const Color textSub = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
}

class PreviewTab extends StatefulWidget {
  final Patient patient;
  final int opdId;

  const PreviewTab({
    super.key,
    required this.patient,
    required this.opdId,
  });

  @override
  State<PreviewTab> createState() => PreviewTabState();
}

class PreviewTabState extends State<PreviewTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final supabase = Supabase.instance.client;

  // --- PRINT PROCESS ---
  // --- PDF GENERATION & ACTIONS ---
  Future<Uint8List?> _generateReportPdf() async {
    try {
      // 1. Prepare Data (Mirroring _buildLivePdfPreview logic)
      final symData = _cloudData['symptoms_list_json'];
      String symText = "";
      if (symData is List) {
        symText = symData.whereType<Map>().map((e) {
          String name = e['name']?.toString() ?? '';
          List<String> details = [];
          if (e['severity'] != null && e['severity'].toString().isNotEmpty) details.add(e['severity'].toString());
          if (e['duration'] != null && e['duration'].toString().isNotEmpty) details.add(e['duration'].toString());
          if (e['note'] != null && e['note'].toString().isNotEmpty) details.add(e['note'].toString());
          return details.isNotEmpty ? "$name (${details.join(', ')})" : name;
        }).join(", ");
      }

      final diagData = _cloudData['diagnosis_list_json'];
      String diagText = (diagData is List) ? diagData.whereType<Map>().map((e) => (e['note']?.toString().isNotEmpty == true) ? "${e['name']} (${e['note']})" : e['name'].toString()).join(", ") : "";

      final rxData = _cloudData['rx_list_json'];
      final List<Map<String, String>> rxDisplay = (rxData is List) ? rxData.whereType<Map>().map<Map<String, String>>((item) {
        String freqFull = "";
        if (item['timing'] is Map) {
          final t = item['timing'] as Map;
          String d = item['dosage']?.toString().trim() ?? "1";
          if (d.isEmpty) d = "1";
          String m = (t['bb'] == true || t['ab'] == true) ? d : "0";
          String a = (t['bl'] == true || t['al'] == true) ? d : "0";
          String n = (t['bd'] == true || t['ad'] == true) ? d : "0";
          freqFull = "$m-$a-$n";
        } else {
          freqFull = item['freq']?.toString() ?? "0-0-0";
        }

        List<String> instParts = [];
        if (item['timing'] is Map) {
          final t = item['timing'] as Map;
          if (t['bb'] == true) instParts.add("Before Breakfast");
          if (t['ab'] == true) instParts.add("After Breakfast");
          if (t['bl'] == true) instParts.add("Before Lunch");
          if (t['al'] == true) instParts.add("After Lunch");
          if (t['bd'] == true) instParts.add("Before Dinner");
          if (t['ad'] == true) instParts.add("After Dinner");
        }
        String manualNote = item['note']?.toString() ?? '';
        if (manualNote.isNotEmpty) instParts.add(manualNote);

        String durationRaw = item['duration']?.toString() ?? '';
        String durationFull = durationRaw.toLowerCase().replaceAll('d', ' Days').replaceAll('w', ' Weeks').replaceAll('m', ' Months');

        return {
          "type": item['type']?.toString().toUpperCase() == 'ALLOPATHY' ? "" : (item['type']?.toString() ?? '').toUpperCase(),
          "name": item['name']?.toString() ?? '',
          "unit": item['unit']?.toString() ?? '',
          "freq": freqFull,
          "dur": durationFull.trim(),
          "note": instParts.join(", ")
        };
      }).toList() : [];

      final instList = _cloudData['instructions_list_json'] as List?;
      final invList = _cloudData['investigations_list_json'] as List?;
      final procList = _cloudData['procedures_list_json'] as List?;

      Map<String, String> vitalMap = {};
      if (_cloudData['bp']?.toString().isNotEmpty == true) vitalMap['BP'] = _cloudData['bp'].toString();
      if (_cloudData['pulse']?.toString().isNotEmpty == true) vitalMap['Pulse'] = "${_cloudData['pulse']} bpm";
      if (_cloudData['spo2']?.toString().isNotEmpty == true) vitalMap['SpO2'] = "${_cloudData['spo2']}%";
      if (_cloudData['sugar']?.toString().isNotEmpty == true) vitalMap['Sugar'] = "${_cloudData['sugar']} mg/dL";
      if (_cloudData['temp']?.toString().isNotEmpty == true) vitalMap['Temp'] = "${_cloudData['temp']} °F";
      if (_cloudData['weight']?.toString().isNotEmpty == true) vitalMap['Wt'] = "${_cloudData['weight']} kg";

      if (_cloudData['clinical_data']?['checkup_data'] is Map) {
        Map<String, dynamic> cData = Map<String, dynamic>.from(_cloudData['clinical_data']['checkup_data']);
        cData.forEach((k, v) {
          String key = k.trim().toLowerCase(); String val = v.toString().trim(); if (val.isEmpty) return;
          if (key == 'bp') { if (!vitalMap.containsKey('BP')) vitalMap['BP'] = val; }
          else if (key == 'pulse') { if (!vitalMap.containsKey('Pulse')) vitalMap['Pulse'] = val.contains('bpm') ? val : "$val bpm"; }
          else if (key == 'weight' || key == 'wt') { if (!vitalMap.containsKey('Wt')) vitalMap['Wt'] = val.contains('kg') ? val : "$val kg"; }
          else if (key == 'spo2') { if (!vitalMap.containsKey('SpO2')) vitalMap['SpO2'] = val.contains('%') ? val : "$val%"; }
        });
      }
      String vitalsStr = vitalMap.entries.map((e) => "${e.key}: ${e.value}").join("  |  ");

      String hText = "";
      if (_cloudData['clinical_data']?['medical_history'] is List) {
        hText = (_cloudData['clinical_data']['medical_history'] as List).map((e) => e['name']?.toString() ?? '').where((s) => s.isNotEmpty).join(", ");
      }

      List<Map<String, dynamic>> fDisplay = [];
      if (_cloudData['clinical_data']?['fitness_data'] is List) {
        for (var plan in (_cloudData['clinical_data']['fitness_data'] as List).whereType<Map>()) {
          if (plan['isAssigned'] == true) {
            String type = plan['type']?.toString().toLowerCase() ?? '';
            fDisplay.add({'title': plan['title'], 'type': type, 'entries': (type.contains('diet') ? plan['dietEntries'] : plan['exerciseEntries']) ?? []});
          }
        }
      }

      List<Map<String, String>> bResults = [];
      if (_cloudData['clinical_data']?['investigation_values'] is Map) {
        final values = Map<String, dynamic>.from(_cloudData['clinical_data']['investigation_values']);
        values.forEach((param, val) {
          if (val.toString().trim().isNotEmpty) {
            String unit = "";
            try {
              final mParam = _investigationsMaster.firstWhere((m) => m['name']?.toString().toUpperCase() == param.toString().toUpperCase(), orElse: () => null);
              if (mParam != null) unit = mParam['unit']?.toString() ?? "";
            } catch(e) {}
            bResults.add({'name': param.toString(), 'value': val.toString(), 'unit': unit});
          }
        });
      }

      // 2. Call PDF Generator
      return await ReportPdfGenerator.generatePdf(
        patient: widget.patient,
        opdId: widget.opdId,
        date: DateTime.now(),
        config: {'margin_top': _marginTop, 'margin_bottom': _marginBottom, 'toggles': _printSettings},
        symptomsText: symText,
        diagnosisText: diagText,
        historyText: hText,
        checkupsText: (_cloudData['clinical_data']?['checkup_data'] is Map) ? (Map<String, dynamic>.from(_cloudData['clinical_data']['checkup_data'])).entries.where((e) => !['bp','pulse','temp','weight','wt','spo2'].contains(e.key.toLowerCase())).map((e) => "${e.key}: ${e.value}").join(", ") : "",
        vitalsText: vitalsStr,
        rxList: rxDisplay,
        instructionsText: (instList)?.join("\n") ?? "",
        investigationsText: (invList)?.join(", ") ?? "",
        proceduresText: (procList)?.join(", ") ?? "",
        fitnessPlans: fDisplay,
        notesText: _clinicalNoteController.text,
        followUpText: _selectedFollowUp.isNotEmpty ? "Next Review: After $_selectedFollowUp" : "",
        referDoctorText: _selectedReferDoctor != null ? "Ref: Dr. ${_selectedReferDoctor!['name']}" : "",
        bloodResults: bResults,
      );
    } catch (e) {
      debugPrint("PDF Gen Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF Gen Error: $e"), backgroundColor: Colors.red));
      return null;
    }
  }

  Future<void> _shareReport() async {
    setState(() => _isSharing = true);
    try {
      final bytes = await _generateReportPdf();
      if (bytes != null) {
        await ReportPdfGenerator.sharePdf(bytes, 'OPD_Report_${widget.patient.name}_${widget.opdId}.pdf');
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }


  // --- STATE ---
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSharing = false;
  bool _isCheckingOut = false;

  // Data Containers
  Map<String, dynamic> _cloudData = {};
  List<dynamic> _investigationsMaster = [];

  // Notes & Follow Up State
  String _selectedFollowUp = "";

  late TextEditingController _followUpNoteController;
  late TextEditingController _clinicalNoteController;
  late TextEditingController _privateNoteController;
  Timer? _notesDebounce;
  Timer? _privateNotesDebounce;

  Map<String, dynamic>? _selectedReferDoctor;

  // Margin State
  bool _showMargins = false;
  double _marginTop = 50.0;
  double _marginBottom = 50.0;

  // Print Settings
  Map<String, bool> _printSettings = {
    "Symptoms": true,
    "Medical History": true,
    "Check-Ups": true,
    "Diagnosis": true,
    "Investigation Results": true,
    "Procedures": true,
    "Fitness Plan": true,
    "Clinical Notes": true,
    "Instructions": true,
    "Signature": true,
    "Blood Results": true,
  };

  @override
  void initState() {
    super.initState();
    _followUpNoteController = TextEditingController();
    _clinicalNoteController = TextEditingController();
    _privateNoteController = TextEditingController();

    // 1. Load Local Settings (Margins & Toggles)
    _loadSavedSettings();

    // 2. Then Fetch Patient Data
    _fetchAndMergeData();

    // 3. Listen for external syncs
    ServerDataService.refreshNotifier.addListener(_fetchAndMergeData);

    // 4. Register Auto-Save for Notes
    _clinicalNoteController.addListener(_onNoteChanged);
    _privateNoteController.addListener(_onPrivateNoteChanged);
  }

  void _onNoteChanged() {
    if (_notesDebounce?.isActive ?? false) _notesDebounce?.cancel();
    _notesDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _autoSaveNote();
    });
  }

  void _onPrivateNoteChanged() {
    if (_privateNotesDebounce?.isActive ?? false) _privateNotesDebounce?.cancel();
    _privateNotesDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _autoSavePrivateNote();
    });
  }

  Future<void> _autoSaveNote() async {
    final note = _clinicalNoteController.text;
    await ServerDataService.saveData(widget.opdId, 'clinical_notes', note, silent: true);
  }

  Future<void> _autoSavePrivateNote() async {
    final note = _privateNoteController.text;
    await ServerDataService.saveData(widget.opdId, 'private_note', note, silent: true);
  }

  @override
  void dispose() {
    ServerDataService.refreshNotifier.removeListener(_fetchAndMergeData);
    _notesDebounce?.cancel();
    _privateNotesDebounce?.cancel();
    _followUpNoteController.dispose();
    _clinicalNoteController.dispose();
    _privateNoteController.dispose();
    super.dispose();
  }

  // --- LOCAL & CLOUD STORAGE: LOAD ---
  Future<void> _loadSavedSettings() async {
    // 1. Try Loading from Cloud (Supabase) FIRST
    try {
      final cloudResponse = await supabase
          .from('opd_datasets')
          .select('datajson')
          .eq('dataname', 'report_settings')
          .maybeSingle();

      if (cloudResponse != null && cloudResponse['datajson'] != null) {
        final data = cloudResponse['datajson'] as Map<String, dynamic>;
        setState(() {
          _marginTop = (data['margin_top'] ?? 50.0).toDouble();
          _marginBottom = (data['margin_bottom'] ?? 50.0).toDouble();
          if (data['toggles'] != null) {
            Map<String, dynamic> toggles = data['toggles'];
            toggles.forEach((key, value) {
              if (_printSettings.containsKey(key)) {
                _printSettings[key] = value as bool;
              }
            });
          }
        });
        // Sync to local for offline use
        _saveSettingsToLocal();
        return; 
      }
    } catch (e) {
      debugPrint("Cloud Settings Fetch Error: $e");
    }

    // 2. Fallback to Local SharedPreferences if Cloud fails
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (prefs.containsKey('report_margin_top')) {
        _marginTop = prefs.getDouble('report_margin_top') ?? 50.0;
      }
      if (prefs.containsKey('report_margin_bottom')) {
        _marginBottom = prefs.getDouble('report_margin_bottom') ?? 50.0;
      }
      if (prefs.containsKey('report_toggles')) {
        String? jsonStr = prefs.getString('report_toggles');
        if (jsonStr != null) {
          Map<String, dynamic> savedMap = jsonDecode(jsonStr);
          savedMap.forEach((key, value) {
            if (_printSettings.containsKey(key)) {
              _printSettings[key] = value as bool;
            }
          });
        }
      }
    });
  }

  // --- LOCAL STORAGE: SAVE ---
  Future<void> _saveSettingsToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('report_margin_top', _marginTop);
    await prefs.setDouble('report_margin_bottom', _marginBottom);
    await prefs.setString('report_toggles', jsonEncode(_printSettings));
  }

  // --- 1. FETCH & MERGE ---
  Future<void> _fetchAndMergeData() async {
    setState(() => _isLoading = true);
    try {
      // (Sync happens automatically across tabs)

      // 1. Fetch from Main Table (Using generic select to avoid crashes if columns like 'temp' are missing)
      final mainResponse = await supabase
          .from('opd_registration')
          .select() 
          .eq('id', widget.opdId)
          .maybeSingle();

      if (mainResponse != null) {
        Map<String, dynamic> mergedData = Map<String, dynamic>.from(mainResponse);

        // 2. Fetch Structured Tables in PARALLEL
        final List<Future<dynamic>> futures = [
          supabase.from('opd_reg_symptoms').select().eq('opd_id', widget.opdId),
          supabase.from('opd_reg_diagnosis').select().eq('opd_id', widget.opdId),
          supabase.from('opd_reg_rx').select().eq('opd_id', widget.opdId),
          supabase.from('opd_reg_reports').select().eq('opd_id', widget.opdId),
          supabase.from('opd_datasets').select('datajson').eq('dataname', 'investigations').maybeSingle(),
        ];
        final results = await Future.wait(futures);

        // --- Symptoms ---
        final List symRows = results[0] as List;
        mergedData['symptoms_list_json'] = symRows.map((r) => {
          'name': r['name'],
          'note': r['note'],
          'duration': r['duration'],
          'severity': r['severity'],
          'custom_groups': r['custom_groups'],
          'selected_options': r['selected_options'],
        }).toList();

        // --- Diagnosis ---
        final List diagRows = results[1] as List;
        mergedData['diagnosis_list_json'] = diagRows.map((r) => {
           'name': r['name'],
           'note': r['note'],
        }).toList();

        // --- Rx ---
        final List rxRows = results[2] as List;
        mergedData['rx_list_json'] = rxRows.map((r) => {
          'id': r['id'].toString(),
          'name': r['medicine_name'],
          'type': r['medicine_type'],
          'unit': r['unit'],
          'dosage': r['dosage'],
          'duration': r['duration'],
          'timing': r['timing_json'],
          'note': r['note'],
        }).toList();

        // --- Reports ---
        final List reportRows = results[3] as List;
        mergedData['instructions_list_json'] = reportRows.where((r) => r['report_type'] == 'instruction').map((r) => r['item_name']).toList();
        mergedData['investigations_list_json'] = reportRows.where((r) => r['report_type'] == 'investigation').map((r) => r['item_name']).toList();
        mergedData['procedures_list_json'] = reportRows.where((r) => r['report_type'] == 'procedure').map((r) => r['item_name']).toList();

        // --- Master Investigations ---
        final masterRes = results[4] as Map?;
        _investigationsMaster = (masterRes != null && masterRes['datajson'] is List) ? masterRes['datajson'] : [];

        // 3. MERGE LOCAL EDITS (REMOVED - FETCHING ONLINE ONLY)
        // Relies on cloud data fetched above in results


        // Clinical Data
        // Clinical Data (Using cloud states only)
        final clinicalMap = (mergedData['clinical_data'] != null)
            ? Map<String, dynamic>.from(mergedData['clinical_data'])
            : {};
        
        mergedData['clinical_data'] = clinicalMap;

        // Apply to UI State
        _cloudData = mergedData;

        // Meta (Follow Up, Notes, Refer)
        _selectedFollowUp = mergedData['follow_up_duration'] ?? "";
        _followUpNoteController.text = mergedData['follow_up_note'] ?? "";

        String loadedClinicalNote = mergedData['clinical_notes'] ?? "";
        if (loadedClinicalNote.isEmpty && clinicalMap['clinical_notes'] != null) {
          loadedClinicalNote = clinicalMap['clinical_notes'];
        }

        // Only update if different (avoid cursor jumps/auto-save loops)
        if (_clinicalNoteController.text != loadedClinicalNote) {
           _clinicalNoteController.text = loadedClinicalNote;
        }

        String loadedPrivateNote = mergedData['private_note'] ?? "";
        if (_privateNoteController.text != loadedPrivateNote) {
          _privateNoteController.text = loadedPrivateNote;
        }

        if (mergedData['referring_doctor_name'] != null) {
          _selectedReferDoctor = {'name': mergedData['referring_doctor_name']};
        }
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. BUILD PREVIEW DATA ---
  Widget _buildLivePdfPreview() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // A. SYMPTOMS
    final symData = _cloudData['symptoms_list_json'];
    String symText = "";
    if (symData is List) {
      symText = symData.whereType<Map>().map((e) {
        String name = e['name']?.toString() ?? '';
        List<String> details = [];
        if (e['severity'] != null && e['severity'].toString().isNotEmpty) details.add(e['severity'].toString());
        if (e['duration'] != null && e['duration'].toString().isNotEmpty) details.add(e['duration'].toString());
        if (e['note'] != null && e['note'].toString().isNotEmpty) details.add(e['note'].toString());
        
        return details.isNotEmpty ? "$name (${details.join(', ')})" : name;
      }).join(", ");
    }

    // B. DIAGNOSIS
    final diagData = _cloudData['diagnosis_list_json'];
    String diagText = "";
    if (diagData is List) {
      diagText = diagData.whereType<Map>().map((e) {
        String name = e['name']?.toString() ?? '';
        String note = e['note']?.toString() ?? '';
        return note.isNotEmpty ? "$name ($note)" : name;
      }).join(", ");
    }

    // C. RX (Treatment)
    final rxData = _cloudData['rx_list_json'];
    final List<Map<String, String>> rxDisplay = (rxData is List) ? rxData.whereType<Map>().map<Map<String, String>>((item) {
          // 1. Frequency (Full Form)
          String freqFull = "";
          int count = 0;
          List<String> times = [];
          
          if (item['timing'] is Map) {
            final t = item['timing'] as Map;
            if (t['bb'] == true || t['ab'] == true) { count++; times.add("Morning"); }
            if (t['bl'] == true || t['al'] == true) { count++; times.add("Afternoon"); }
            if (t['bd'] == true || t['ad'] == true) { count++; times.add("Night"); }
          } else if (item['freq'] != null) {
            String f = item['freq'].toString().replaceAll(" ", ""); // Remove all spaces
            List<String> parts = f.split('-');
            if (parts.length == 3) {
              if (parts[0] == '1') { count++; times.add("Morning"); }
              if (parts[1] == '1') { count++; times.add("Afternoon"); }
              if (parts[2] == '1') { count++; times.add("Night"); }
            }
          }

          if (item['timing'] is Map) {
            final t = item['timing'] as Map;
            String d = item['dosage']?.toString().trim() ?? "1";
            if (d.isEmpty) d = "1";
            String m = (t['bb'] == true || t['ab'] == true) ? d : "0";
            String a = (t['bl'] == true || t['al'] == true) ? d : "0";
            String n = (t['bd'] == true || t['ad'] == true) ? d : "0";
            freqFull = "$m-$a-$n";
          } else {
            freqFull = item['freq']?.toString() ?? "0-0-0";
          }

          // 2. Automated Instructions from Selection
          List<String> instParts = [];
          if (item['timing'] is Map) {
            final t = item['timing'] as Map;
            if (t['bb'] == true) instParts.add("Before Breakfast");
            if (t['ab'] == true) instParts.add("After Breakfast");
            if (t['bl'] == true) instParts.add("Before Lunch");
            if (t['al'] == true) instParts.add("After Lunch");
            if (t['bd'] == true) instParts.add("Before Dinner");
            if (t['ad'] == true) instParts.add("After Dinner");
          }
          
          // Append manual note if exists
          String manualNote = item['note']?.toString() ?? '';
          // 3. Medicine Data Extraction
          String type = item['type']?.toString().toLowerCase() == 'allopathy' ? "" : (item['type']?.toString() ?? '');
          String name = item['name']?.toString() ?? '';
          String unit = item['unit']?.toString() ?? '';
          
          String durationRaw = item['duration']?.toString() ?? '';
          String durationFull = durationRaw.toLowerCase()
              .replaceAll('d', ' Days')
              .replaceAll('w', ' Weeks')
              .replaceAll('m', ' Months');
          if (durationFull.isEmpty) durationFull = durationRaw;

          if (manualNote.isNotEmpty) instParts.add(manualNote);
          String finalInst = instParts.join(", ");

          return {
            "type": type.toUpperCase(),
            "name": name,
            "unit": unit.isNotEmpty ? "($unit)" : "",
            "freq": freqFull,
            "dur": durationFull.trim(),
            "note": finalInst
          };
        }).toList() : <Map<String, String>>[];

    // D. INSTRUCTIONS
    final instList = _cloudData['instructions_list_json'] as List?;
    final invList = _cloudData['investigations_list_json'] as List?;
    final procList = _cloudData['procedures_list_json'] as List?;

    String instText = (instList)?.join("\n") ?? "";
    String invText = (invList)?.join(", ") ?? "";
    String procText = (procList)?.join(", ") ?? "";

    // E. VITALS & CHECKUPS (Enhanced Fetching)
    Map<String, String> vitalMap = {};
    
    // 1. Try Top-Level Columns first
    if (_cloudData['bp']?.toString().isNotEmpty == true) vitalMap['BP'] = _cloudData['bp'].toString();
    if (_cloudData['pulse']?.toString().isNotEmpty == true) vitalMap['Pulse'] = "${_cloudData['pulse']} bpm";
    if (_cloudData['spo2']?.toString().isNotEmpty == true) vitalMap['SpO2'] = "${_cloudData['spo2']}%";
    if (_cloudData['sugar']?.toString().isNotEmpty == true) vitalMap['Sugar'] = "${_cloudData['sugar']} mg/dL";
    if (_cloudData['weight']?.toString().isNotEmpty == true) vitalMap['Wt'] = "${_cloudData['weight']} kg";

    // 2. Supplement from checkup_data (if missing)
    List<String> checkupsList = [];
    if (_cloudData['clinical_data']?['checkup_data'] != null) {
      Map<String, dynamic> cData = Map<String, dynamic>.from(_cloudData['clinical_data']['checkup_data']);
      
      cData.forEach((k, v) {
        String key = k.trim().toLowerCase();
        String val = v.toString().trim();
        if (val.isEmpty) return;

        // Map known vitals if not already found
        if (key == 'bp' || key == 'blood pressure') { if (!vitalMap.containsKey('BP')) vitalMap['BP'] = val; }
        else if (key == 'pulse' || key == 'heart rate') { if (!vitalMap.containsKey('Pulse')) vitalMap['Pulse'] = val.contains('bpm') ? val : "$val bpm"; }
        else if (key == 'weight' || key == 'wt') { if (!vitalMap.containsKey('Wt')) vitalMap['Wt'] = val.contains('kg') ? val : "$val kg"; }
        else if (key == 'spo2') { if (!vitalMap.containsKey('SpO2')) vitalMap['SpO2'] = val.contains('%') ? val : "$val%"; }
        else {
          // It's a general observation
          checkupsList.add("${k.trim()}: $val");
        }
      });
    }

    String vitalsStr = vitalMap.entries.map((e) => "${e.key}: ${e.value}").join("  |  ");
    String checkupsStr = checkupsList.join(", ");

    // F. MEDICAL HISTORY
    String histText = "";
    if (_cloudData['clinical_data'] != null) {
      final hData = _cloudData['clinical_data']['medical_history'];
      if(hData is List) {
        histText = hData.whereType<Map>().map((e) => e['name']?.toString() ?? '').where((s) => s.isNotEmpty).join(", ");
      }
    }

    // G. FITNESS
    List<Map<String, dynamic>> fitnessDisplay = [];
    if (_cloudData['clinical_data'] != null) {
      final fData = _cloudData['clinical_data']['fitness_data'];
      if (fData is List) {
        for (var plan in fData.whereType<Map>()) {
          if (plan['isAssigned'] == true) {
            String type = plan['type']?.toString().toLowerCase() ?? '';
            List<dynamic> entries = [];
            if (type.contains('diet')) {
              entries = plan['dietEntries'] is List ? plan['dietEntries'] : [];
            } else {
              entries = plan['exerciseEntries'] is List ? plan['exerciseEntries'] : [];
            }
            fitnessDisplay.add({
              'title': plan['title'],
              'type': type,
              'entries': entries
            });
          }
        }
      }
    }

    // H. NOTES
    String noteStr = _clinicalNoteController.text;

    // Extraction of Blood Test Results for Print
    List<Map<String, String>> bloodResults = [];
    if (_cloudData['clinical_data']?['investigation_values'] != null) {
      final values = Map<String, dynamic>.from(_cloudData['clinical_data']['investigation_values']);
      
      // Use Pre-fetched Master Parameters for Units
      List<dynamic> master = _investigationsMaster;
      
      values.forEach((param, val) {
        if (val.toString().trim().isNotEmpty) {
          String unit = "";
          try {
            final mParam = master.firstWhere((m) => m['name']?.toString().toUpperCase() == param.toString().toUpperCase(), orElse: () => null);
            if (mParam != null) unit = mParam['unit']?.toString() ?? "";
          } catch(e) {}
          
          bloodResults.add({
            'name': param.toString(),
            'value': val.toString(),
            'unit': unit
          });
        }
      });
    }

    // I. CONFIG
    Map<String, dynamic> config = {
      'margin_top': _marginTop,
      'margin_bottom': _marginBottom,
      'toggles': _printSettings
    };

    return PreviewPdfComponent(
      patient: widget.patient,
      opdId: widget.opdId,
      date: DateTime.now(),
      config: config,
      symptomsText: symText,
      diagnosisText: diagText,
      historyText: histText,
      checkupsText: checkupsStr,
      vitalsText: vitalsStr,
      rxList: rxDisplay,
      instructionsText: instText,
      investigationsText: invText,
      proceduresText: procText,
      fitnessPlans: fitnessDisplay,
      notesText: noteStr,
      followUpText: _selectedFollowUp.isNotEmpty ? "Next Review: After $_selectedFollowUp" : "",
      referDoctorText: _selectedReferDoctor != null ? "Ref: Dr. ${_selectedReferDoctor!['name']}" : "",
      bloodResults: bloodResults,
    );
  }

  // --- 3. SUBMIT TO SUPABASE ---
  Future<void> submitDataToSupabase() async {
    setState(() => _isSubmitting = true);
    final opdId = widget.opdId;
    final finalClinicalNote = _clinicalNoteController.text;
    final finalFollowUpNote = _followUpNoteController.text;

    try {
      await ServerDataService.saveData(opdId, 'clinical_notes', finalClinicalNote);
      await ServerDataService.saveData(opdId, 'private_note', _privateNoteController.text);

      DateTime? nextReviewDate = _calculateNextReview();

      Map<String, dynamic> existingClinicalData = (_cloudData['clinical_data'] as Map<String, dynamic>?) ?? {};
      existingClinicalData['print_settings'] = _printSettings;
      existingClinicalData['margins'] = {'top': _marginTop, 'bottom': _marginBottom};
      existingClinicalData['refer_doctor'] = _selectedReferDoctor;
      existingClinicalData['meta_followup'] = {'duration': _selectedFollowUp, 'note': finalFollowUpNote};
      existingClinicalData['clinical_notes'] = finalClinicalNote;

      final Map<String, dynamic> updateData = {
        'follow_up_duration': _selectedFollowUp,
        'follow_up_note': finalFollowUpNote,
        'clinical_notes': finalClinicalNote,
        'private_note': _privateNoteController.text,
        'referring_doctor_name': _selectedReferDoctor != null ? _selectedReferDoctor!['name'] : null,
        'next_review_date': nextReviewDate?.toIso8601String(),
        'is_finalized': true,
        'visit_status': 'Finalized',
        'finalized_at': DateTime.now().toIso8601String(),
        'clinical_data': existingClinicalData
      };

      await supabase.from('opd_registration').update(updateData).eq('id', opdId);
      
      // Notify listeners (Dashboard List) to refresh
      ServerDataService.refreshNotifier.value++;
      
      await _fetchAndMergeData();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved & Finalized! Prepare to Share..."), backgroundColor: Colors.green));

      // Automatically trigger share after finalize
      await _shareReport();

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  DateTime? _calculateNextReview() {
    if (_selectedFollowUp.isEmpty) return null;
    final now = DateTime.now();
    try {
      if (_selectedFollowUp.contains("d")) return now.add(Duration(days: int.parse(_selectedFollowUp.replaceAll("d", ""))));
      if (_selectedFollowUp.contains("w")) return now.add(Duration(days: int.parse(_selectedFollowUp.replaceAll("w", "")) * 7));
      if (_selectedFollowUp.contains("m")) return now.add(Duration(days: int.parse(_selectedFollowUp.replaceAll("m", "")) * 30));
      if (_selectedFollowUp.contains("y")) return now.add(const Duration(days: 365));
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<void> _saveAndCheckout() async {
    setState(() => _isCheckingOut = true);
    final opdId = widget.opdId;
    final finalClinicalNote = _clinicalNoteController.text;
    final finalFollowUpNote = _followUpNoteController.text;

    try {
      await ServerDataService.saveData(opdId, 'clinical_notes', finalClinicalNote);
      await ServerDataService.saveData(opdId, 'private_note', _privateNoteController.text);

      DateTime? nextReviewDate = _calculateNextReview();

      Map<String, dynamic> existingClinicalData = (_cloudData['clinical_data'] as Map<String, dynamic>?) ?? {};
      existingClinicalData['print_settings'] = _printSettings;
      existingClinicalData['margins'] = {'top': _marginTop, 'bottom': _marginBottom};
      existingClinicalData['refer_doctor'] = _selectedReferDoctor;
      existingClinicalData['meta_followup'] = {'duration': _selectedFollowUp, 'note': finalFollowUpNote};
      existingClinicalData['clinical_notes'] = finalClinicalNote;

      final Map<String, dynamic> updateData = {
        'follow_up_duration': _selectedFollowUp,
        'follow_up_note': finalFollowUpNote,
        'clinical_notes': finalClinicalNote,
        'private_note': _privateNoteController.text,
        'referring_doctor_name': _selectedReferDoctor != null ? _selectedReferDoctor!['name'] : null,
        'next_review_date': nextReviewDate?.toIso8601String(),
        'is_finalized': false, // Keep open for later
        'visit_status': 'Checked Out',
        'clinical_data': existingClinicalData
      };

      await supabase.from('opd_registration').update(updateData).eq('id', opdId);
      
      // Notify listeners (Dashboard List) to refresh
      ServerDataService.refreshNotifier.value++;
      
      await _fetchAndMergeData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patient Checked Out Successfully!"), backgroundColor: Colors.blue));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  Future<void> _saveGlobalConfig() async {
    // 1. Save to Supabase (Cloud)
    await supabase.from('opd_datasets').upsert({
      'dataname': 'report_settings',
      'datajson': {'margin_top': _marginTop, 'margin_bottom': _marginBottom, 'toggles': _printSettings},
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'dataname');

    // 2. Save to SharedPreferences (Local)
    await _saveSettingsToLocal();

    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Default Settings Saved!"), ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- LEFT SIDEBAR (CONTROLS) ---
          Container(
            width: 320,
            decoration: const BoxDecoration(
                color: PreviewTheme.panelColor,
                border: Border(right: BorderSide(color: PreviewTheme.border))
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: PreviewTheme.border))),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: PreviewTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.tune, size: 18, color: PreviewTheme.primary)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Report Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: PreviewTheme.textMain)),
                          Text(
                            _cloudData['is_finalized'] == true 
                              ? "FINALIZED" 
                              : (_cloudData['visit_status'] == 'Checked Out' ? "CHECKED OUT (PENDING)" : "LIVE DRAFT"),
                            style: TextStyle(
                              fontSize: 9, 
                              fontWeight: FontWeight.w800, 
                              letterSpacing: 0.5,
                              color: _cloudData['is_finalized'] == true ? AppColors.success : (_cloudData['visit_status'] == 'Checked Out' ? AppColors.warning : AppColors.primary)
                            )
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // List Controls
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: (_isSubmitting || _isSharing) ? null : submitDataToSupabase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_cloudData['is_finalized'] == true) ? Colors.orange[700] : PreviewTheme.primary, 
                            foregroundColor: Colors.white, 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                          ),
                          icon: (_isSubmitting || _isSharing)
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : Icon((_cloudData['is_finalized'] == true) ? Icons.refresh_rounded : Icons.share_rounded, size: 20),
                          label: Text(
                            (_isSubmitting || _isSharing) ? "Processing..." : (_cloudData['is_finalized'] == true ? "UPDATE & SHARE" : "FINALIZE & SHARE"), 
                            style: const TextStyle(fontWeight: FontWeight.bold)
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: (_isSubmitting || _isSharing || _isCheckingOut) ? null : _saveAndCheckout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo[600],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _isCheckingOut 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Icon(Icons.logout_rounded, size: 20),
                          label: const Text("SAVE & CHECK-OUT", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: PreviewTheme.border)),

                      // MARGINS
                      InkWell(
                        onTap: () => setState(() => _showMargins = !_showMargins),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildSidebarSectionTitle("PAGE MARGINS"), Icon(_showMargins ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: Colors.grey)]),
                        ),
                      ),
                      if (_showMargins) ...[
                        const SizedBox(height: 12),
                        _buildSliderControl(
                            "Top",
                            _marginTop,
                                (v) => setState(() => _marginTop = v),
                                (v) => _saveSettingsToLocal() // Save on drag end
                        ),
                        const SizedBox(height: 16),
                        _buildSliderControl(
                            "Bottom",
                            _marginBottom,
                                (v) => setState(() => _marginBottom = v),
                                (v) => _saveSettingsToLocal() // Save on drag end
                        ),
                        const SizedBox(height: 12),
                        SizedBox(width: double.infinity, child: TextButton.icon(onPressed: _saveGlobalConfig, icon: const Icon(Icons.save_outlined, size: 16), label: const Text("Save Default"))),
                      ],
                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: PreviewTheme.border)),

                      // FOLLOW UP
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSidebarSectionTitle("FOLLOW UP"),
                          if (_selectedFollowUp.isNotEmpty)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedFollowUp = "";
                                  _followUpNoteController.clear();
                                });
                              },
                              child: const Text("Reset", style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                            )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: ["3d", "5d", "1w", "2w", "1m", "45d", "3m", "6m", "1y"].map((dur) {
                          bool isSelected = _selectedFollowUp == dur;
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedFollowUp = dur);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: 42, height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: isSelected ? PreviewTheme.primary : Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: isSelected ? PreviewTheme.primary : PreviewTheme.border)),
                              child: Text(dur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : PreviewTheme.textSub)),
                            ),
                          );
                        }).toList(),
                      ),

                      if (_selectedFollowUp.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _followUpNoteController,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(hintText: "Follow-up specific note...", isDense: true, filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PreviewTheme.border))),
                        ),
                      ],

                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: PreviewTheme.border)),

                      _buildSidebarSectionTitle("CASUALTY / CLINICAL NOTE"),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _clinicalNoteController,
                        onChanged: (val) => setState(() {}),
                        maxLines: 4,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Enter casualty or clinical remarks...",
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PreviewTheme.border)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: PreviewTheme.border)),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSidebarSectionTitle("PRIVATE NOTE"),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                            child: const Text("NOT IN PDF", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.red)),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _privateNoteController,
                        onChanged: (val) => setState(() {}),
                        maxLines: 3,
                        style: const TextStyle(fontSize: 13, color: Colors.indigo),
                        decoration: InputDecoration(
                          hintText: "Internal remarks (won't print)...",
                          isDense: true,
                          filled: true,
                          fillColor: Colors.indigo.withOpacity(0.02),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PreviewTheme.border)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1, color: PreviewTheme.border)),

                      _buildSidebarSectionTitle("ACTIONS"),
                      const SizedBox(height: 12),
                      _buildModernActionTile("Refer Patient", Icons.person_add_alt_1_outlined, subtitle: _selectedReferDoctor != null ? _selectedReferDoctor!['name'] : "Select Doctor", isActive: _selectedReferDoctor != null, onTap: _openDoctorSelector, onRemove: _selectedReferDoctor != null ? _removeReferDoctor : null),
                      const SizedBox(height: 10),
                      _buildModernActionTile("Report Sections", Icons.visibility_outlined, subtitle: "Show/Hide Content", onTap: _showReportSettingsDialog),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- RIGHT PANEL (PREVIEW) ---
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 2.0,
              child: Container(
                color: const Color(0xFFE2E8F0),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildLivePdfPreview(),
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSidebarSectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: PreviewTheme.textSub));

  Widget _buildModernActionTile(String title, IconData icon, {String? subtitle, bool isActive = false, VoidCallback? onTap, VoidCallback? onRemove}) {
    return Container(
      decoration: BoxDecoration(
          color: isActive ? PreviewTheme.primary.withOpacity(0.05) : Colors.white,
          border: Border.all(color: isActive ? PreviewTheme.primary.withOpacity(0.3) : PreviewTheme.border),
          borderRadius: BorderRadius.circular(8)
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(icon, color: isActive ? PreviewTheme.primary : PreviewTheme.textSub, size: 18),
        title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? PreviewTheme.primary : PreviewTheme.textMain)),
        subtitle: subtitle != null ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: PreviewTheme.textSub)) : null,
        trailing: isActive && onRemove != null
            ? InkWell(onTap: onRemove, child: const Icon(Icons.close, size: 16, color: Colors.red))
            : const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  // --- UPDATED SLIDER CONTROL: Auto-save on drag end ---
  Widget _buildSliderControl(String label, double val, Function(double) onChanged, Function(double) onChangeEnd) {
    return Row(
      children: [
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 12, color: PreviewTheme.textMain))),
        Expanded(
          child: SizedBox(
            height: 20,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: PreviewTheme.primary,
                inactiveTrackColor: Colors.grey[200],
                thumbColor: PreviewTheme.primary,
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: val,
                min: 0,
                max: 200,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd, // Saves when user releases handle
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openDoctorSelector() async {
    final result = await showDialog(context: context, builder: (context) => const DoctorSelectionDialog());
    if (result != null && result is Map<String, dynamic>) {
      setState(() => _selectedReferDoctor = result);
    }
  }

  void _removeReferDoctor() {
    setState(() => _selectedReferDoctor = null);
  }

  void _showReportSettingsDialog() {
    showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  title: const Text("Report Sections"),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _printSettings.keys.map((key) {
                        return CheckboxListTile(
                          title: Text(key, style: const TextStyle(fontSize: 13)),
                          value: _printSettings[key]!,
                          activeColor: Colors.blue,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (val) {
                            setStateDialog(() => _printSettings[key] = val!);
                            setState(() => _printSettings[key] = val!);
                            _saveSettingsToLocal(); // Auto-save on toggle
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
                );
              }
          );
        }
    );
  }
}