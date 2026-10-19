import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../services/server_data_service.dart';
import '../services/offline_sync_service.dart';
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
        String getDose(dynamic beforeVal, dynamic afterVal, String defaultDose) {
          String parseSingle(dynamic val) {
            if (val == null) return "0";
            if (val is bool) return val ? defaultDose : "0";
            final s = val.toString().trim();
            return s.isEmpty ? "0" : s;
          }
          final b = parseSingle(beforeVal);
          final a = parseSingle(afterVal);
          if (b != "0") return b;
          return a;
        }

        bool isActive(dynamic val) {
          if (val == null) return false;
          if (val is bool) return val;
          final s = val.toString().trim();
          return s.isNotEmpty && s != "0";
        }

        dynamic timingObj = item['timing'] ?? item['timing_json'];
        Map<String, dynamic> t = {};
        if (timingObj is Map) {
          t = Map<String, dynamic>.from(timingObj);
        } else if (timingObj is String && timingObj.trim().isNotEmpty) {
          try {
            final dec = jsonDecode(timingObj);
            if (dec is Map) t = Map<String, dynamic>.from(dec);
          } catch (_) {}
        }

        if (t.isNotEmpty) {
          String d = item['dosage']?.toString().trim() ?? "1";
          if (d.isEmpty) d = "1";
          String m = getDose(t['bb'], t['ab'], d);
          String a = getDose(t['bl'], t['al'], d);
          String n = getDose(t['bd'], t['ad'], d);
          freqFull = "$m-$a-$n";
        } else {
          freqFull = item['freq']?.toString() ?? "0-0-0";
        }

        List<String> instParts = [];
        if (t.isNotEmpty) {
          if (isActive(t['bb'])) instParts.add("Before Breakfast");
          if (isActive(t['ab'])) instParts.add("After Breakfast");
          if (isActive(t['bl'])) instParts.add("Before Lunch");
          if (isActive(t['al'])) instParts.add("After Lunch");
          if (isActive(t['bd'])) instParts.add("Before Dinner");
          if (isActive(t['ad'])) instParts.add("After Dinner");
        }
        String manualNote = item['note']?.toString() ?? '';
        if (manualNote.isNotEmpty) instParts.add(manualNote);

        String durationRaw = item['duration']?.toString() ?? '';
        String durationFull = durationRaw.toLowerCase().replaceAll('d', ' Days').replaceAll('w', ' Weeks').replaceAll('m', ' Months');

        String medType = (item['type'] ?? item['medicine_type'] ?? '').toString();
        String medName = (item['name'] ?? item['medicine_name'] ?? '').toString();

        return {
          "type": medType.toUpperCase() == 'ALLOPATHY' ? "" : medType.toUpperCase(),
          "name": medName,
          "unit": item['unit']?.toString() ?? '',
          "freq": freqFull,
          "dur": (durationFull.isEmpty ? durationRaw : durationFull).trim(),
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
      final visitDate = _cloudData['created_at'] != null ? DateTime.parse(_cloudData['created_at']).toLocal() : DateTime.now();
      return await ReportPdfGenerator.generatePdf(
        patient: widget.patient,
        opdId: widget.opdId,
        date: visitDate,
        config: {
          'margin_top': _marginTop,
          'margin_bottom': _marginBottom,
          'margin_horizontal': _marginHorizontal,
          'toggles': _printSettings
        },
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
        followUpText: _formatFollowUpText(visitDate),
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
  bool _showCustomFollowUp = false;
  int _customFollowUpNumber = 1;
  String _customFollowUpUnit = 'd'; // 'd' = Day, 'm' = Month, 'y' = Year

  late TextEditingController _followUpNoteController;
  late TextEditingController _clinicalNoteController;
  late TextEditingController _privateNoteController;
  Timer? _notesDebounce;
  Timer? _privateNotesDebounce;

  Map<String, dynamic>? _selectedReferDoctor;

  // Margin & Padding State (Closed by default)
  bool _showMargins = false;
  bool _showSections = false;
  double _marginTop = 50.0;
  double _marginBottom = 50.0;
  double _marginHorizontal = 35.0;

  // Print Settings
  final Map<String, bool> _printSettings = {
    "Header": true,
    "Vitals": true,
    "Symptoms": true,
    "Diagnosis": true,
    "Rx": true,
    "Instructions": true,
    "Check-Ups": true,
    "Medical History": true,
    "Blood Results": true,
    "Investigation Results": true,
    "Procedures": true,
    "Fitness Plan": true,
    "Clinical Notes": true,
    "Follow Up": true,
    "Signature": true,
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
    // 1. FIRST: Load instantly from Local Storage (0ms offline guarantee)
    try {
      final cachedHive = OfflineSyncService().getCachedMasterData('report_settings');
      if (cachedHive is Map) {
        _applySettingsMap(Map<String, dynamic>.from(cachedHive));
      }

      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('report_margin_top')) {
        _marginTop = prefs.getDouble('report_margin_top') ?? _marginTop;
      }
      if (prefs.containsKey('report_margin_bottom')) {
        _marginBottom = prefs.getDouble('report_margin_bottom') ?? _marginBottom;
      }
      if (prefs.containsKey('report_margin_horizontal')) {
        _marginHorizontal = prefs.getDouble('report_margin_horizontal') ?? _marginHorizontal;
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
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Local settings load error: $e");
    }

    // 2. Fetch from Cloud in background with a 2-second timeout (never blocks UI or offline)
    try {
      final cloudResponse = await supabase
          .from('opd_datasets')
          .select('datajson')
          .eq('dataname', 'report_settings')
          .maybeSingle()
          .timeout(const Duration(seconds: 2));

      if (cloudResponse != null && cloudResponse['datajson'] != null) {
        final rawData = cloudResponse['datajson'];
        final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
        if (mounted && data.isNotEmpty) {
          setState(() {
            _applySettingsMap(data);
          });
          // Cache to local disk for future offline sessions
          _saveSettingsToLocal();
        }
      }
    } catch (e) {
      debugPrint("Cloud Settings Fetch fallback (offline/cached): $e");
    }
  }

  void _applySettingsMap(Map<String, dynamic> data) {
    if (data['margin_top'] != null) {
      _marginTop = (data['margin_top'] as num).toDouble();
    }
    if (data['margin_bottom'] != null) {
      _marginBottom = (data['margin_bottom'] as num).toDouble();
    }
    if (data['margin_horizontal'] != null) {
      _marginHorizontal = (data['margin_horizontal'] as num).toDouble();
    } else if (data['margin_side'] != null) {
      _marginHorizontal = (data['margin_side'] as num).toDouble();
    }
    if (data['toggles'] != null && data['toggles'] is Map) {
      Map<String, dynamic> toggles = Map<String, dynamic>.from(data['toggles']);
      toggles.forEach((key, value) {
        if (_printSettings.containsKey(key) && value is bool) {
          _printSettings[key] = value;
        }
      });
    }
  }

  // --- LOCAL STORAGE: SAVE ---
  Future<void> _saveSettingsToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('report_margin_top', _marginTop);
      await prefs.setDouble('report_margin_bottom', _marginBottom);
      await prefs.setDouble('report_margin_horizontal', _marginHorizontal);
      await prefs.setString('report_toggles', jsonEncode(_printSettings));

      await OfflineSyncService().cacheMasterData('report_settings', {
        'margin_top': _marginTop,
        'margin_bottom': _marginBottom,
        'margin_horizontal': _marginHorizontal,
        'toggles': _printSettings,
      });
    } catch (e) {
      debugPrint("Error saving settings to local: $e");
    }
  }
  void refreshData() {
    _fetchAndMergeData();
  }

  // --- 1. FETCH & MERGE ---
  Future<void> _fetchAndMergeData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Base merged data with fallback patient info
      Map<String, dynamic> mergedData = {
        'id': widget.opdId,
        'uhid': widget.patient.id,
        'patient_name': widget.patient.name,
        'created_at': widget.patient.visitDate.toIso8601String(),
      };

      // 2. Load Local Disk Clinical Data FIRST (< 1ms offline guarantee)
      final localRx = OfflineSyncService().getLocalClinicalData(widget.opdId, 'treatment_data');
      if (localRx is List && localRx.isNotEmpty) {
        mergedData['rx_list_json'] = localRx.map((item) {
          if (item is Map) {
            return {
              'id': item['id']?.toString() ?? '',
              'name': item['name'] ?? item['medicine_name'] ?? '',
              'type': item['type'] ?? item['medicine_type'] ?? '',
              'unit': item['unit'] ?? '',
              'dosage': item['dosage'] ?? '',
              'duration': item['duration'] ?? '',
              'timing': item['timing'] ?? item['timing_json'] ?? {},
              'note': item['note'] ?? '',
            };
          }
          return <String, dynamic>{};
        }).toList();
      }

      final localSym = OfflineSyncService().getLocalClinicalData(widget.opdId, 'symptoms');
      if (localSym is List && localSym.isNotEmpty) {
        mergedData['symptoms_list_json'] = localSym;
      }

      final localDiag = OfflineSyncService().getLocalClinicalData(widget.opdId, 'diagnosis_data');
      if (localDiag is List && localDiag.isNotEmpty) {
        mergedData['diagnosis_list_json'] = localDiag;
      }

      final localReports = OfflineSyncService().getLocalClinicalData(widget.opdId, 'instructions_data');
      if (localReports is Map) {
        if (localReports['instructions'] is List) {
          mergedData['instructions_list_json'] = localReports['instructions'];
        }
        if (localReports['investigations'] is List) {
          mergedData['investigations_list_json'] = localReports['investigations'];
        }
        if (localReports['procedures'] is List) {
          mergedData['procedures_list_json'] = localReports['procedures'];
        }
      }

      // 3. Attempt Cloud Fetch (if online) with short timeout
      try {
        final mainResponse = await supabase
            .from('opd_registration')
            .select()
            .eq('id', widget.opdId)
            .maybeSingle()
            .timeout(const Duration(seconds: 3));

        if (mainResponse != null) {
          mergedData.addAll(Map<String, dynamic>.from(mainResponse));
        }

        final List<Future<dynamic>> futures = [
          supabase.from('opd_reg_symptoms').select().eq('opd_id', widget.opdId).timeout(const Duration(seconds: 3)),
          supabase.from('opd_reg_diagnosis').select().eq('opd_id', widget.opdId).timeout(const Duration(seconds: 3)),
          supabase.from('opd_reg_rx').select().eq('opd_id', widget.opdId).timeout(const Duration(seconds: 3)),
          supabase.from('opd_reg_reports').select().eq('opd_id', widget.opdId).timeout(const Duration(seconds: 3)),
          supabase.from('opd_datasets').select('datajson').eq('dataname', 'investigations').maybeSingle().timeout(const Duration(seconds: 3)),
        ];
        final results = await Future.wait(futures);

        // Symptoms (cloud overrides only if local was empty)
        final List symRows = results[0] as List;
        if (mergedData['symptoms_list_json'] == null || (mergedData['symptoms_list_json'] as List).isEmpty) {
          mergedData['symptoms_list_json'] = symRows.map((r) => {
            'name': r['name'],
            'note': r['note'],
            'duration': r['duration'],
            'severity': r['severity'],
            'custom_groups': r['custom_groups'],
            'selected_options': r['selected_options'],
          }).toList();
        }

        // Diagnosis (cloud overrides only if local was empty)
        final List diagRows = results[1] as List;
        if (mergedData['diagnosis_list_json'] == null || (mergedData['diagnosis_list_json'] as List).isEmpty) {
          mergedData['diagnosis_list_json'] = diagRows.map((r) => {
            'name': r['name'],
            'note': r['note'],
          }).toList();
        }

        // Rx (cloud overrides only if local was empty and no pending offline edits)
        final List rxRows = results[2] as List;
        final bool hasPendingRx = OfflineSyncService().hasPendingSync(widget.opdId, 'treatment_data');
        if (!hasPendingRx && (mergedData['rx_list_json'] == null || (mergedData['rx_list_json'] as List).isEmpty)) {
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
          if (rxRows.isNotEmpty) {
            OfflineSyncService().cacheServerData(widget.opdId, 'treatment_data', mergedData['rx_list_json']);
          }
        }

        // Reports
        final List reportRows = results[3] as List;
        if (mergedData['instructions_list_json'] == null) {
          mergedData['instructions_list_json'] = reportRows.where((r) => r['report_type'] == 'instruction').map((r) => r['item_name']).toList();
        }
        if (mergedData['investigations_list_json'] == null) {
          mergedData['investigations_list_json'] = reportRows.where((r) => r['report_type'] == 'investigation').map((r) => r['item_name']).toList();
        }
        if (mergedData['procedures_list_json'] == null) {
          mergedData['procedures_list_json'] = reportRows.where((r) => r['report_type'] == 'procedure').map((r) => r['item_name']).toList();
        }

        // Master investigations
        final masterRes = results[4] as Map?;
        if (masterRes != null && masterRes['datajson'] is List) {
          _investigationsMaster = masterRes['datajson'];
        }
      } catch (cloudErr) {
        debugPrint("Cloud fetch fallback in preview: $cloudErr");
      }

      // Clinical Data
      final clinicalMap = (mergedData['clinical_data'] != null)
          ? Map<String, dynamic>.from(mergedData['clinical_data'])
          : {};
      mergedData['clinical_data'] = clinicalMap;

      // Apply visit-specific margins & print settings if present
      if (clinicalMap['margins'] != null && clinicalMap['margins'] is Map) {
        final m = clinicalMap['margins'];
        if (m['top'] != null) _marginTop = (m['top'] as num).toDouble();
        if (m['bottom'] != null) _marginBottom = (m['bottom'] as num).toDouble();
        if (m['horizontal'] != null) _marginHorizontal = (m['horizontal'] as num).toDouble();
      }
      if (clinicalMap['print_settings'] != null && clinicalMap['print_settings'] is Map) {
        final ps = clinicalMap['print_settings'] as Map;
        ps.forEach((k, v) {
          if (_printSettings.containsKey(k) && v is bool) {
            _printSettings[k] = v;
          }
        });
      }

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
          List<String> times = [];
          
          bool isActive(dynamic val) {
            if (val == null) return false;
            if (val is bool) return val;
            final s = val.toString().trim();
            return s.isNotEmpty && s != "0";
          }

          String getDose(dynamic beforeVal, dynamic afterVal, String defaultDose) {
            String parseSingle(dynamic val) {
              if (val == null) return "0";
              if (val is bool) return val ? defaultDose : "0";
              final s = val.toString().trim();
              return s.isEmpty ? "0" : s;
            }
            final b = parseSingle(beforeVal);
            final a = parseSingle(afterVal);
            if (b != "0") return b;
            return a;
          }

          dynamic timingObj = item['timing'] ?? item['timing_json'];
          Map<String, dynamic> t = {};
          if (timingObj is Map) {
            t = Map<String, dynamic>.from(timingObj);
          } else if (timingObj is String && timingObj.trim().isNotEmpty) {
            try {
              final dec = jsonDecode(timingObj);
              if (dec is Map) t = Map<String, dynamic>.from(dec);
            } catch (_) {}
          }

          if (t.isNotEmpty) {
            if (isActive(t['bb']) || isActive(t['ab'])) { times.add("Morning"); }
            if (isActive(t['bl']) || isActive(t['al'])) { times.add("Afternoon"); }
            if (isActive(t['bd']) || isActive(t['ad'])) { times.add("Night"); }
          } else if (item['freq'] != null) {
            String f = item['freq'].toString().replaceAll(" ", ""); // Remove all spaces
            List<String> parts = f.split('-');
            if (parts.length == 3) {
              if (parts[0] != '0') { times.add("Morning"); }
              if (parts[1] != '0') { times.add("Afternoon"); }
              if (parts[2] != '0') { times.add("Night"); }
            }
          }

          if (t.isNotEmpty) {
            String d = item['dosage']?.toString().trim() ?? "1";
            if (d.isEmpty) d = "1";
            String m = getDose(t['bb'], t['ab'], d);
            String a = getDose(t['bl'], t['al'], d);
            String n = getDose(t['bd'], t['ad'], d);
            freqFull = "$m-$a-$n";
          } else {
            freqFull = item['freq']?.toString() ?? "0-0-0";
          }

          // 2. Automated Instructions from Selection
          List<String> instParts = [];
          if (t.isNotEmpty) {
            if (isActive(t['bb'])) instParts.add("Before Breakfast");
            if (isActive(t['ab'])) instParts.add("After Breakfast");
            if (isActive(t['bl'])) instParts.add("Before Lunch");
            if (isActive(t['al'])) instParts.add("After Lunch");
            if (isActive(t['bd'])) instParts.add("Before Dinner");
            if (isActive(t['ad'])) instParts.add("After Dinner");
          }
          
          // Append manual note if exists
          String manualNote = item['note']?.toString() ?? '';
          // 3. Medicine Data Extraction
          String medType = (item['type'] ?? item['medicine_type'] ?? '').toString();
          String type = medType.toLowerCase() == 'allopathy' ? "" : medType;
          String name = (item['name'] ?? item['medicine_name'] ?? '').toString();
          String unit = (item['unit'] ?? '').toString();
          
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
      'margin_horizontal': _marginHorizontal,
      'toggles': _printSettings
    };

    final visitDate = _cloudData['created_at'] != null ? DateTime.parse(_cloudData['created_at']).toLocal() : DateTime.now();
    return PreviewPdfComponent(
      patient: widget.patient,
      opdId: widget.opdId,
      date: visitDate,
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
      followUpText: _formatFollowUpText(visitDate),
      referDoctorText: _selectedReferDoctor != null ? "Ref: Dr. ${_selectedReferDoctor!['name']}" : "",
      bloodResults: bloodResults,
    );
  }

  String _formatFollowUpText(DateTime visitDate) {
    if (_selectedFollowUp.isEmpty) return "";
    final reviewDate = _calculateNextReview(visitDate);
    final note = _followUpNoteController.text.trim();
    if (reviewDate != null) {
      final formattedDate = DateFormat('dd MMM yyyy').format(reviewDate);
      if (note.isNotEmpty) {
        return "Next Review: $formattedDate ($note)";
      }
      return "Next Review: $formattedDate";
    }
    if (note.isNotEmpty) {
      return "Next Review: $_selectedFollowUp ($note)";
    }
    return "Next Review: $_selectedFollowUp";
  }

  // --- 3. SUBMIT TO SUPABASE ---
  Future<void> submitDataToSupabase() async {
    setState(() => _isSubmitting = true);
    final opdId = widget.opdId;
    final finalClinicalNote = _clinicalNoteController.text;
    final finalFollowUpNote = _followUpNoteController.text;

    try {
      // 1. Save notes locally and in background
      await ServerDataService.saveData(opdId, 'clinical_notes', finalClinicalNote);
      await ServerDataService.saveData(opdId, 'private_note', _privateNoteController.text);

      final visitDate = _cloudData['created_at'] != null ? DateTime.parse(_cloudData['created_at']).toLocal() : widget.patient.visitDate;
      DateTime? nextReviewDate = _calculateNextReview(visitDate);

      // 2. Safe extraction of clinical_data (prevents _Map<dynamic, dynamic> cast error)
      Map<String, dynamic> existingClinicalData = {};
      if (_cloudData['clinical_data'] is Map) {
        try {
          existingClinicalData = Map<String, dynamic>.from(_cloudData['clinical_data'] as Map);
        } catch (_) {
          existingClinicalData = {};
        }
      }
      existingClinicalData['print_settings'] = _printSettings;
      existingClinicalData['margins'] = {
        'top': _marginTop,
        'bottom': _marginBottom,
        'horizontal': _marginHorizontal
      };
      await _saveSettingsToLocal();
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

      // 3. Immediately save to disk cache & offline sync queue (zero data loss offline)
      _cloudData.addAll(updateData);
      await OfflineSyncService().saveClinicalData(opdId, 'opd_registration_update', updateData);
      OfflineSyncService().updateCachedPatientStatus(opdId, isFinalized: true, visitStatus: 'Finalized');

      // 4. Opportunistically update Supabase (silent fallback if offline)
      bool isOnlineSuccess = false;
      try {
        await supabase
            .from('opd_registration')
            .update(updateData)
            .eq('id', opdId)
            .timeout(const Duration(seconds: 4));
        isOnlineSuccess = true;
      } catch (netErr) {
        debugPrint("Offline mode: patient finalization queued for sync ($netErr)");
      }
      
      // Notify listeners (Dashboard List) to refresh
      ServerDataService.refreshNotifier.value++;
      
      await _fetchAndMergeData();

      if (mounted) {
        if (isOnlineSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Saved & Finalized! Prepare to Share..."), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Saved & Finalized Locally (Offline)! Auto-syncing when online."), backgroundColor: Colors.blue),
          );
        }
      }

      // Automatically trigger share after finalize
      await _shareReport();

    } catch (e) {
      debugPrint("Finalize Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  DateTime? _calculateNextReview([DateTime? baseDate]) {
    if (_selectedFollowUp.isEmpty) return null;
    final base = baseDate ?? (_cloudData['created_at'] != null 
        ? DateTime.parse(_cloudData['created_at']).toLocal() 
        : widget.patient.visitDate);
    try {
      final str = _selectedFollowUp.trim().toLowerCase();
      if (str.endsWith("d")) {
        final days = int.parse(str.replaceAll("d", ""));
        return base.add(Duration(days: days));
      } else if (str.endsWith("w")) {
        final weeks = int.parse(str.replaceAll("w", ""));
        return base.add(Duration(days: weeks * 7));
      } else if (str.endsWith("m")) {
        final months = int.parse(str.replaceAll("m", ""));
        int year = base.year;
        int month = base.month + months;
        year += (month - 1) ~/ 12;
        month = ((month - 1) % 12) + 1;
        int lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
        int day = base.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : base.day;
        return DateTime(year, month, day, base.hour, base.minute);
      } else if (str.endsWith("y")) {
        final years = int.parse(str.replaceAll("y", ""));
        int year = base.year + years;
        int lastDayOfTargetMonth = DateTime(year, base.month + 1, 0).day;
        int day = base.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : base.day;
        return DateTime(year, base.month, day, base.hour, base.minute);
      }
    } catch (e) {
      debugPrint("Error calculating next review: $e");
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

      final visitDate = _cloudData['created_at'] != null ? DateTime.parse(_cloudData['created_at']).toLocal() : widget.patient.visitDate;
      DateTime? nextReviewDate = _calculateNextReview(visitDate);

      // Safe extraction of clinical_data (prevents _Map<dynamic, dynamic> cast error)
      Map<String, dynamic> existingClinicalData = {};
      if (_cloudData['clinical_data'] is Map) {
        try {
          existingClinicalData = Map<String, dynamic>.from(_cloudData['clinical_data'] as Map);
        } catch (_) {
          existingClinicalData = {};
        }
      }
      existingClinicalData['print_settings'] = _printSettings;
      existingClinicalData['margins'] = {
        'top': _marginTop,
        'bottom': _marginBottom,
        'horizontal': _marginHorizontal
      };
      await _saveSettingsToLocal();
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

      // Immediately save to disk cache & offline sync queue
      _cloudData.addAll(updateData);
      await OfflineSyncService().saveClinicalData(opdId, 'opd_registration_update', updateData);
      OfflineSyncService().updateCachedPatientStatus(opdId, isFinalized: false, visitStatus: 'Checked Out');

      // Opportunistically update Supabase
      bool isOnlineSuccess = false;
      try {
        await supabase
            .from('opd_registration')
            .update(updateData)
            .eq('id', opdId)
            .timeout(const Duration(seconds: 4));
        isOnlineSuccess = true;
      } catch (netErr) {
        debugPrint("Offline mode: patient checkout queued for sync ($netErr)");
      }
      
      // Notify listeners (Dashboard List) to refresh
      ServerDataService.refreshNotifier.value++;
      
      await _fetchAndMergeData();

      if (mounted) {
        if (isOnlineSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Patient Checked Out Successfully!"), backgroundColor: Colors.blue),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Patient Checked Out Locally (Offline)! Auto-syncs when online."), backgroundColor: Colors.blue),
          );
        }
      }

    } catch (e) {
      debugPrint("Checkout Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  Future<void> _saveGlobalConfig() async {
    // 1. Save to Local Storage FIRST (instant 0ms persistence)
    await _saveSettingsToLocal();

    // 2. Save to Supabase (Cloud) with a short timeout so offline never hangs
    try {
      await supabase.from('opd_datasets').upsert({
        'dataname': 'report_settings',
        'datajson': {
          'margin_top': _marginTop,
          'margin_bottom': _marginBottom,
          'margin_horizontal': _marginHorizontal,
          'toggles': _printSettings
        },
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'dataname').timeout(const Duration(seconds: 4));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Default Settings Saved (Cloud & Local)!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Cloud save failed (saved locally): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Settings Saved Locally on Device (Offline)"), backgroundColor: Colors.blue),
        );
      }
    }
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

                      // MARGINS & PADDING
                      InkWell(
                        onTap: () => setState(() => _showMargins = !_showMargins),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSidebarSectionTitle("PAGE MARGINS & PADDING"),
                              Icon(_showMargins ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                      if (_showMargins) ...[
                        const SizedBox(height: 8),
                        _buildSliderControl(
                          "Top Margin (Header)",
                          _marginTop,
                          200.0,
                          (v) => setState(() => _marginTop = v),
                          () => _saveSettingsToLocal(),
                        ),
                        const SizedBox(height: 12),
                        _buildSliderControl(
                          "Bottom Margin (Footer)",
                          _marginBottom,
                          200.0,
                          (v) => setState(() => _marginBottom = v),
                          () => _saveSettingsToLocal(),
                        ),
                        const SizedBox(height: 12),
                        _buildSliderControl(
                          "Side Padding (Left / Right)",
                          _marginHorizontal,
                          80.0,
                          (v) => setState(() => _marginHorizontal = v),
                          () => _saveSettingsToLocal(),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _saveGlobalConfig,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  side: BorderSide(color: PreviewTheme.primary.withValues(alpha: 0.4)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                icon: const Icon(Icons.save_outlined, size: 14),
                                label: const Text("Save Default", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _resetDefaultMargins,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: PreviewTheme.border),
                                ),
                                child: const Text("Reset", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: PreviewTheme.textSub)),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: PreviewTheme.border)),

                      // PRINT SECTIONS TOGGLE
                      InkWell(
                        onTap: () => setState(() => _showSections = !_showSections),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSidebarSectionTitle("PRINT SECTIONS"),
                              Row(
                                children: [
                                  Text(
                                    "${_printSettings.values.where((v) => v).length}/${_printSettings.length} ON",
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: PreviewTheme.primary),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(_showSections ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showSections) ...[
                        const SizedBox(height: 6),
                        ..._printSettings.keys.map((key) {
                          final isChecked = _printSettings[key] ?? true;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                setState(() {
                                  _printSettings[key] = !isChecked;
                                });
                                _saveSettingsToLocal();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: isChecked,
                                        activeColor: PreviewTheme.primary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        onChanged: (val) {
                                          setState(() {
                                            _printSettings[key] = val ?? true;
                                          });
                                          _saveSettingsToLocal();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _getSectionFriendlyLabel(key),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                                          color: isChecked ? PreviewTheme.textMain : PreviewTheme.textSub,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: PreviewTheme.border)),

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
                        children: [
                          ...["3d", "5d", "1w", "2w", "1m", "45d", "3m", "6m", "1y"].map((dur) {
                            bool isSelected = _selectedFollowUp == dur && !_showCustomFollowUp;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedFollowUp = dur;
                                  _showCustomFollowUp = false;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 42, height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: isSelected ? PreviewTheme.primary : Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: isSelected ? PreviewTheme.primary : PreviewTheme.border)),
                                child: Text(dur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : PreviewTheme.textSub)),
                              ),
                            );
                          }),
                          // Custom chip
                          InkWell(
                            onTap: () {
                              setState(() {
                                _showCustomFollowUp = !_showCustomFollowUp;
                                if (_showCustomFollowUp) {
                                  // Build the value immediately on open
                                  _selectedFollowUp = "$_customFollowUpNumber$_customFollowUpUnit";
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _showCustomFollowUp ? PreviewTheme.primary : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _showCustomFollowUp ? PreviewTheme.primary : PreviewTheme.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune_rounded, size: 12, color: _showCustomFollowUp ? Colors.white : PreviewTheme.textSub),
                                  const SizedBox(width: 4),
                                  Text("Custom", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _showCustomFollowUp ? Colors.white : PreviewTheme.textSub)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Custom Follow-Up Inline Picker
                      if (_showCustomFollowUp) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: PreviewTheme.primary.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Text("After", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: PreviewTheme.textSub)),
                              const SizedBox(width: 8),
                              // Number picker
                              Container(
                                height: 34,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: PreviewTheme.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _customFollowUpNumber,
                                    isDense: true,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: PreviewTheme.textMain),
                                    items: List.generate(99, (i) => i + 1).map((n) => DropdownMenuItem(value: n, child: Text(n.toString()))).toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() {
                                        _customFollowUpNumber = v;
                                        _selectedFollowUp = "$v$_customFollowUpUnit";
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Unit picker
                              Container(
                                height: 34,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: PreviewTheme.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _customFollowUpUnit,
                                    isDense: true,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: PreviewTheme.textMain),
                                    items: const [
                                      DropdownMenuItem(value: 'd', child: Text('Day')),
                                      DropdownMenuItem(value: 'm', child: Text('Month')),
                                      DropdownMenuItem(value: 'y', child: Text('Year')),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) setState(() {
                                        _customFollowUpUnit = v;
                                        _selectedFollowUp = "$_customFollowUpNumber$v";
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // Preview badge
                              if (_selectedFollowUp.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: PreviewTheme.primary, borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                    _calculateNextReview() != null ? DateFormat('dd MMM yyyy').format(_calculateNextReview()!) : _selectedFollowUp,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],

                      if (_selectedFollowUp.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: PreviewTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: PreviewTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_available_rounded, size: 14, color: PreviewTheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "Next Review: ${_calculateNextReview() != null ? DateFormat('dd MMM yyyy (EEEE)').format(_calculateNextReview()!) : _selectedFollowUp}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: PreviewTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _followUpNoteController,
                          onChanged: (val) => setState(() {}),
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

  // --- UPDATED SLIDER CONTROL: Auto-save on drag end with live point badge ---
  Widget _buildSliderControl(String label, double val, double maxVal, Function(double) onChanged, VoidCallback onChangeEnd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PreviewTheme.textMain)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: PreviewTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "${val.toInt()} pt",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: PreviewTheme.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: PreviewTheme.primary,
              inactiveTrackColor: Colors.grey[200],
              thumbColor: PreviewTheme.primary,
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: val.clamp(0.0, maxVal),
              min: 0,
              max: maxVal,
              onChanged: onChanged,
              onChangeEnd: (_) => onChangeEnd(), // Saves when user releases handle
            ),
          ),
        ),
      ],
    );
  }

  void _resetDefaultMargins() {
    setState(() {
      _marginTop = 50.0;
      _marginBottom = 50.0;
      _marginHorizontal = 35.0;
    });
    _saveSettingsToLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Margins reset to default (Top 50, Bottom 50, Side 35 pt)"), duration: Duration(seconds: 1)),
      );
    }
  }

  String _getSectionFriendlyLabel(String key) {
    switch (key) {
      case "Header": return "Patient Header & Barcode";
      case "Vitals": return "Vitals Banner";
      case "Symptoms": return "Symptoms";
      case "Diagnosis": return "Diagnosis";
      case "Rx": return "Medicines (Rx Table)";
      case "Instructions": return "Instructions & Advice";
      case "Check-Ups": return "Check-Ups & Observations";
      case "Medical History": return "Medical History";
      case "Blood Results": return "Blood Test Results";
      case "Investigation Results": return "Investigations";
      case "Procedures": return "Procedures";
      case "Fitness Plan": return "Fitness & Diet Plans";
      case "Clinical Notes": return "Remarks / Clinical Notes";
      case "Follow Up": return "Follow-Up Footer";
      case "Signature": return "Doctor Signature";
      default: return key;
    }
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
                          title: Text(_getSectionFriendlyLabel(key), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          value: _printSettings[key] ?? true,
                          activeColor: PreviewTheme.primary,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (val) {
                            setStateDialog(() => _printSettings[key] = val ?? true);
                            setState(() => _printSettings[key] = val ?? true);
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