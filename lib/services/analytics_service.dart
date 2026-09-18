import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../supabase_handler.dart';

/// Filter Model for Clinical Data Analytics
class ClinicalAnalyticsFilter {
  DateTime startDate;
  DateTime endDate;
  String hospital;
  List<String> medicines;
  List<String> symptoms;
  List<String> diagnoses;
  List<String> investigations;
  List<String> advices;
  String searchQuery;
  int? limit;

  ClinicalAnalyticsFilter({
    DateTime? startDate,
    DateTime? endDate,
    this.hospital = "All Hospitals",
    List<String>? medicines,
    List<String>? symptoms,
    List<String>? diagnoses,
    List<String>? investigations,
    List<String>? advices,
    this.searchQuery = "",
    this.limit,
  })  : startDate = startDate ?? DateTime.now().subtract(const Duration(days: 7)),
        endDate = endDate ?? DateTime.now(),
        medicines = medicines ?? [],
        symptoms = symptoms ?? [],
        diagnoses = diagnoses ?? [],
        investigations = investigations ?? [],
        advices = advices ?? [];

  ClinicalAnalyticsFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? hospital,
    List<String>? medicines,
    List<String>? symptoms,
    List<String>? diagnoses,
    List<String>? investigations,
    List<String>? advices,
    String? searchQuery,
    int? limit,
  }) {
    return ClinicalAnalyticsFilter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      hospital: hospital ?? this.hospital,
      medicines: medicines ?? List.from(this.medicines),
      symptoms: symptoms ?? List.from(this.symptoms),
      diagnoses: diagnoses ?? List.from(this.diagnoses),
      investigations: investigations ?? List.from(this.investigations),
      advices: advices ?? List.from(this.advices),
      searchQuery: searchQuery ?? this.searchQuery,
      limit: limit ?? this.limit,
    );
  }

  bool get hasActiveFilters =>
      medicines.isNotEmpty ||
      symptoms.isNotEmpty ||
      diagnoses.isNotEmpty ||
      investigations.isNotEmpty ||
      advices.isNotEmpty ||
      (hospital != "All Hospitals" && hospital.isNotEmpty) ||
      searchQuery.trim().isNotEmpty;
}

/// Analytics Patient Record
class AnalyticsPatientRecord {
  final int opdId;
  final String uhid;
  final DateTime createdAt;
  final String hospitalName;
  final String visitType;
  final String visitStatus;
  final bool isFinalized;
  final String patientName;
  final String gender;
  final String ageInfo;
  final String phone;
  final String address;
  final List<String> symptoms;
  final List<String> diagnoses;
  final List<Map<String, dynamic>> medicines;
  final List<String> investigations;
  final List<String> advices;
  final Map<String, dynamic> rawData;

  AnalyticsPatientRecord({
    required this.opdId,
    required this.uhid,
    required this.createdAt,
    required this.hospitalName,
    required this.visitType,
    required this.visitStatus,
    required this.isFinalized,
    required this.patientName,
    required this.gender,
    required this.ageInfo,
    required this.phone,
    required this.address,
    required this.symptoms,
    required this.diagnoses,
    required this.medicines,
    required this.investigations,
    required this.advices,
    required this.rawData,
  });

  factory AnalyticsPatientRecord.fromJson(Map<String, dynamic> json) {
    DateTime visitDate;
    try {
      visitDate = DateTime.parse(json['created_at'].toString()).toLocal();
    } catch (_) {
      visitDate = DateTime.now();
    }

    // Parse symptoms
    List<String> symList = [];
    if (json['symptoms'] is List) {
      for (var s in json['symptoms']) {
        if (s is Map) {
          final n = s['name']?.toString() ?? '';
          if (n.isNotEmpty) symList.add(n);
        } else if (s is String && s.isNotEmpty) {
          symList.add(s);
        }
      }
    }

    // Parse diagnoses
    List<String> diagList = [];
    if (json['diagnoses'] is List) {
      for (var d in json['diagnoses']) {
        if (d is Map) {
          final n = d['name']?.toString() ?? '';
          if (n.isNotEmpty) diagList.add(n);
        } else if (d is String && d.isNotEmpty) {
          diagList.add(d);
        }
      }
    }

    // Parse medicines
    List<Map<String, dynamic>> medList = [];
    if (json['medicines'] is List) {
      for (var m in json['medicines']) {
        if (m is Map) {
          medList.add(Map<String, dynamic>.from(m));
        }
      }
    }

    // Parse reports (investigations & advices)
    List<String> invList = [];
    List<String> advList = [];
    if (json['reports'] is List) {
      for (var r in json['reports']) {
        if (r is Map) {
          final type = r['report_type']?.toString().toLowerCase() ?? '';
          final name = r['item_name']?.toString() ?? '';
          if (name.isNotEmpty) {
            if (type == 'investigation') {
              invList.add(name);
            } else {
              advList.add(name);
            }
          }
        }
      }
    }

    final age = json['age']?.toString() ?? '0';
    final ageUnit = json['age_unit']?.toString() ?? 'Y';

    return AnalyticsPatientRecord(
      opdId: json['opd_id'] is int ? json['opd_id'] : int.tryParse(json['opd_id'].toString()) ?? 0,
      uhid: json['uhid']?.toString() ?? '',
      createdAt: visitDate,
      hospitalName: json['hospital_name']?.toString() ?? '',
      visitType: json['visit_type']?.toString() ?? '',
      visitStatus: json['visit_status']?.toString() ?? '',
      isFinalized: json['is_finalized'] == true,
      patientName: json['patient_name']?.toString() ?? 'Unknown',
      gender: json['gender']?.toString() ?? 'U',
      ageInfo: "$age $ageUnit",
      phone: json['phone']?.toString() ?? 'N/A',
      address: json['address']?.toString() ?? '',
      symptoms: symList,
      diagnoses: diagList,
      medicines: medList,
      investigations: invList,
      advices: advList,
      rawData: json,
    );
  }
}

/// Unified Analytics Result Payload
class ClinicalAnalyticsResult {
  final int totalVisits;
  final int uniquePatients;
  final double avgAge;
  final int maleCount;
  final int femaleCount;
  final int otherCount;
  final List<Map<String, dynamic>> dailyTrends;
  final List<Map<String, dynamic>> topDiagnoses;
  final List<Map<String, dynamic>> topMedicines;
  final List<Map<String, dynamic>> topSymptoms;
  final List<Map<String, dynamic>> topInvestigations;
  final List<AnalyticsPatientRecord> records;

  ClinicalAnalyticsResult({
    required this.totalVisits,
    required this.uniquePatients,
    required this.avgAge,
    required this.maleCount,
    required this.femaleCount,
    required this.otherCount,
    required this.dailyTrends,
    required this.topDiagnoses,
    required this.topMedicines,
    required this.topSymptoms,
    required this.topInvestigations,
    required this.records,
  });

  factory ClinicalAnalyticsResult.empty() {
    return ClinicalAnalyticsResult(
      totalVisits: 0,
      uniquePatients: 0,
      avgAge: 0,
      maleCount: 0,
      femaleCount: 0,
      otherCount: 0,
      dailyTrends: [],
      topDiagnoses: [],
      topMedicines: [],
      topSymptoms: [],
      topInvestigations: [],
      records: [],
    );
  }

  factory ClinicalAnalyticsResult.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};

    List<Map<String, dynamic>> parseList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e is Map ? Map<String, dynamic>.from(e) : {'name': e.toString(), 'count': 0}).toList();
      }
      return [];
    }

    List<AnalyticsPatientRecord> recs = [];
    if (json['records'] is List) {
      recs = (json['records'] as List).map((r) => AnalyticsPatientRecord.fromJson(Map<String, dynamic>.from(r))).toList();
    }

    return ClinicalAnalyticsResult(
      totalVisits: summary['total_visits'] ?? recs.length,
      uniquePatients: summary['unique_patients'] ?? recs.map((r) => r.uhid).toSet().length,
      avgAge: (summary['avg_age'] is num) ? (summary['avg_age'] as num).toDouble() : 0.0,
      maleCount: summary['male_count'] ?? 0,
      femaleCount: summary['female_count'] ?? 0,
      otherCount: summary['other_count'] ?? 0,
      dailyTrends: parseList(json['daily_trends']),
      topDiagnoses: parseList(json['top_diagnoses']),
      topMedicines: parseList(json['top_medicines']),
      topSymptoms: parseList(json['top_symptoms']),
      topInvestigations: parseList(json['top_investigations']),
      records: recs,
    );
  }
}

/// Service to execute clinical analytics queries
class AnalyticsService {
  /// Main entry point to fetch analytics data
  static Future<ClinicalAnalyticsResult> fetchAnalytics(ClinicalAnalyticsFilter filter) async {
    // Normalise start / end dates to start and end of day
    final start = DateTime(filter.startDate.year, filter.startDate.month, filter.startDate.day, 0, 0, 0);
    final end = DateTime(filter.endDate.year, filter.endDate.month, filter.endDate.day, 23, 59, 59, 999);

    final String? hospitalParam = (filter.hospital == "All Hospitals" || filter.hospital.trim().isEmpty) ? null : filter.hospital.trim();

    try {
      // 1. Try High-Performance Postgres RPC function
      final rpcParams = {
        'p_start_date': start.toUtc().toIso8601String(),
        'p_end_date': end.toUtc().toIso8601String(),
        'p_hospital': hospitalParam,
        'p_medicines': filter.medicines.isEmpty ? null : filter.medicines,
        'p_symptoms': filter.symptoms.isEmpty ? null : filter.symptoms,
        'p_diagnoses': filter.diagnoses.isEmpty ? null : filter.diagnoses,
        'p_investigations': filter.investigations.isEmpty ? null : filter.investigations,
        'p_advices': filter.advices.isEmpty ? null : filter.advices,
        'p_limit': filter.limit,
      };

      final response = await SupabaseHandler.client.rpc('get_clinical_analytics', params: rpcParams);
      if (response != null && response is Map) {
        return ClinicalAnalyticsResult.fromJson(Map<String, dynamic>.from(response));
      }
    } catch (e) {
      debugPrint("RPC get_clinical_analytics failed or not yet deployed: $e. Falling back to Supabase REST query engine.");
    }

    // 2. Fallback: Supabase REST query engine + Dart in-memory aggregation
    return await _fetchAnalyticsFallback(start, end, hospitalParam, filter);
  }

  static Future<ClinicalAnalyticsResult> _fetchAnalyticsFallback(
    DateTime start,
    DateTime end,
    String? hospital,
    ClinicalAnalyticsFilter filter,
  ) async {
    try {
      var baseQuery = SupabaseHandler.client
          .from('opd_registration')
          .select('id, uhid, created_at, hospital_name, visit_type, visit_status, is_finalized, treating_doctor_id, clinical_data, patient_detail!inner(*)')
          .eq('is_Deleted', false)
          .gte('created_at', start.toUtc().toIso8601String())
          .lte('created_at', end.toUtc().toIso8601String());

      if (hospital != null) {
        baseQuery = baseQuery.eq('hospital_name', hospital);
      }

      dynamic orderedQuery = baseQuery.order('created_at', ascending: false);
      if (filter.limit != null && filter.limit! > 0) {
        orderedQuery = orderedQuery.limit(filter.limit!);
      }

      final opdRows = await orderedQuery;

      if (opdRows.isEmpty) {
        return ClinicalAnalyticsResult.empty();
      }

      final opdIds = opdRows.map((r) => r['id'] as int).toList();

      // Batch in chunks of 500 to handle unlimited records reliably
      List<dynamic> symRows = [];
      List<dynamic> diagRows = [];
      List<dynamic> rxRows = [];
      List<dynamic> repRows = [];

      const int chunkSize = 500;
      for (int i = 0; i < opdIds.length; i += chunkSize) {
        final chunk = opdIds.sublist(i, (i + chunkSize > opdIds.length) ? opdIds.length : i + chunkSize);
        final results = await Future.wait([
          SupabaseHandler.client.from('opd_reg_symptoms').select('opd_id, name, note, duration, severity').inFilter('opd_id', chunk),
          SupabaseHandler.client.from('opd_reg_diagnosis').select('opd_id, name, note').inFilter('opd_id', chunk),
          SupabaseHandler.client.from('opd_reg_rx').select('opd_id, medicine_name, medicine_type, unit, dosage, duration, timing_json, note').inFilter('opd_id', chunk),
          SupabaseHandler.client.from('opd_reg_reports').select('opd_id, item_name, report_type').inFilter('opd_id', chunk),
        ]);

        symRows.addAll(results[0]);
        diagRows.addAll(results[1]);
        rxRows.addAll(results[2]);
        repRows.addAll(results[3]);
      }

      // Group by opd_id
      Map<int, List<Map<String, dynamic>>> symptomsByOpd = {};
      for (var s in symRows) {
        final id = s['opd_id'] as int;
        symptomsByOpd.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(s));
      }

      Map<int, List<Map<String, dynamic>>> diagnosesByOpd = {};
      for (var d in diagRows) {
        final id = d['opd_id'] as int;
        diagnosesByOpd.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(d));
      }

      Map<int, List<Map<String, dynamic>>> rxByOpd = {};
      for (var r in rxRows) {
        final id = r['opd_id'] as int;
        rxByOpd.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(r));
      }

      Map<int, List<Map<String, dynamic>>> reportsByOpd = {};
      for (var rep in repRows) {
        final id = rep['opd_id'] as int;
        reportsByOpd.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(rep));
      }

      // Build matched records and filter by user selected items
      List<AnalyticsPatientRecord> records = [];

      for (var row in opdRows) {
        final int id = row['id'];
        final pDetail = row['patient_detail'] ?? {};

        final syms = symptomsByOpd[id] ?? [];
        final diags = diagnosesByOpd[id] ?? [];
        final rxs = rxByOpd[id] ?? [];
        final reps = reportsByOpd[id] ?? [];

        final symNames = syms.map((s) => s['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        final diagNames = diags.map((d) => d['name']?.toString() ?? '').where((d) => d.isNotEmpty).toList();
        final rxNames = rxs.map((r) => r['medicine_name']?.toString() ?? '').where((r) => r.isNotEmpty).toList();
        final invNames = reps.where((r) => r['report_type'] == 'investigation').map((r) => r['item_name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
        final advNames = reps.where((r) => r['report_type'] != 'investigation').map((r) => r['item_name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();

        // Check multi-filter matches
        if (filter.medicines.isNotEmpty) {
          bool matched = filter.medicines.any((m) => rxNames.any((r) => r.toLowerCase().contains(m.toLowerCase())));
          if (!matched) continue;
        }
        if (filter.symptoms.isNotEmpty) {
          bool matched = filter.symptoms.any((s) => symNames.any((sn) => sn.toLowerCase().contains(s.toLowerCase())));
          if (!matched) continue;
        }
        if (filter.diagnoses.isNotEmpty) {
          bool matched = filter.diagnoses.any((d) => diagNames.any((dn) => dn.toLowerCase().contains(d.toLowerCase())));
          if (!matched) continue;
        }
        if (filter.investigations.isNotEmpty) {
          bool matched = filter.investigations.any((inv) => invNames.any((inName) => inName.toLowerCase().contains(inv.toLowerCase())));
          if (!matched) continue;
        }
        if (filter.advices.isNotEmpty) {
          bool matched = filter.advices.any((adv) => advNames.any((an) => an.toLowerCase().contains(adv.toLowerCase())));
          if (!matched) continue;
        }

        DateTime visitDate;
        try {
          visitDate = DateTime.parse(row['created_at'].toString()).toLocal();
        } catch (_) {
          visitDate = DateTime.now();
        }

        records.add(AnalyticsPatientRecord(
          opdId: id,
          uhid: row['uhid']?.toString() ?? '',
          createdAt: visitDate,
          hospitalName: row['hospital_name']?.toString() ?? '',
          visitType: row['visit_type']?.toString() ?? '',
          visitStatus: row['visit_status']?.toString() ?? '',
          isFinalized: row['is_finalized'] == true,
          patientName: pDetail['name']?.toString() ?? 'Unknown',
          gender: pDetail['gender']?.toString() ?? 'U',
          ageInfo: "${pDetail['age'] ?? '0'} ${pDetail['age_unit'] ?? 'Y'}",
          phone: pDetail['number']?.toString() ?? 'N/A',
          address: pDetail['address']?.toString() ?? '',
          symptoms: symNames,
          diagnoses: diagNames,
          medicines: rxs.map((r) => {
            'name': r['medicine_name'],
            'type': r['medicine_type'],
            'unit': r['unit'],
            'dosage': r['dosage'],
            'duration': r['duration'],
            'timing': r['timing_json'],
            'note': r['note'],
          }).toList(),
          investigations: invNames,
          advices: advNames,
          rawData: row,
        ));
      }

      // Compute in-memory stats
      Map<String, int> dailyMap = {};
      Map<String, int> diagCounts = {};
      Map<String, int> rxCounts = {};
      Map<String, int> symCounts = {};
      Map<String, int> invCounts = {};

      int maleCount = 0;
      int femaleCount = 0;
      int otherCount = 0;
      double totalAge = 0;
      int ageCount = 0;

      for (var r in records) {
        // Daily
        final dayStr = DateFormat('yyyy-MM-dd').format(r.createdAt);
        dailyMap[dayStr] = (dailyMap[dayStr] ?? 0) + 1;

        // Gender
        final g = r.gender.toUpperCase().trim();
        if (g == 'M' || g == 'MALE') {
          maleCount++;
        } else if (g == 'F' || g == 'FEMALE') {
          femaleCount++;
        } else {
          otherCount++;
        }

        // Age
        final ageNum = double.tryParse(r.ageInfo.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (ageNum != null && ageNum > 0) {
          totalAge += ageNum;
          ageCount++;
        }

        // Diagnoses
        for (var d in r.diagnoses) {
          if (d.trim().isNotEmpty) diagCounts[d] = (diagCounts[d] ?? 0) + 1;
        }
        // Medicines
        for (var m in r.medicines) {
          final n = m['name']?.toString().trim() ?? '';
          if (n.isNotEmpty) rxCounts[n] = (rxCounts[n] ?? 0) + 1;
        }
        // Symptoms
        for (var s in r.symptoms) {
          if (s.trim().isNotEmpty) symCounts[s] = (symCounts[s] ?? 0) + 1;
        }
        // Investigations
        for (var inv in r.investigations) {
          if (inv.trim().isNotEmpty) invCounts[inv] = (invCounts[inv] ?? 0) + 1;
        }
      }

      List<Map<String, dynamic>> toSortedList(Map<String, int> map, {int limit = 10}) {
        final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return entries.take(limit).map((e) => {'name': e.key, 'count': e.value}).toList();
      }

      final dailyTrends = dailyMap.entries.map((e) => {'visit_day': e.key, 'count': e.value}).toList()
        ..sort((a, b) => a['visit_day'].toString().compareTo(b['visit_day'].toString()));

      return ClinicalAnalyticsResult(
        totalVisits: records.length,
        uniquePatients: records.map((r) => r.uhid).toSet().length,
        avgAge: ageCount > 0 ? double.parse((totalAge / ageCount).toStringAsFixed(1)) : 0.0,
        maleCount: maleCount,
        femaleCount: femaleCount,
        otherCount: otherCount,
        dailyTrends: dailyTrends,
        topDiagnoses: toSortedList(diagCounts),
        topMedicines: toSortedList(rxCounts),
        topSymptoms: toSortedList(symCounts),
        topInvestigations: toSortedList(invCounts),
        records: records,
      );
    } catch (e) {
      debugPrint("Error in _fetchAnalyticsFallback: $e");
      return ClinicalAnalyticsResult.empty();
    }
  }

  /// Generate CSV String for Excel export
  static String generateCsvData(List<AnalyticsPatientRecord> records) {
    final StringBuffer csv = StringBuffer();

    // CSV Header
    csv.writeln(
      [
        '"OPD ID"',
        '"UHID"',
        '"Visit Date"',
        '"Patient Name"',
        '"Age"',
        '"Gender"',
        '"Phone"',
        '"Hospital"',
        '"Visit Type"',
        '"Status"',
        '"Diagnoses"',
        '"Symptoms"',
        '"Prescriptions / Medicines"',
        '"Investigations / Blood Tests"',
        '"Instructions & Advices"',
        '"Address"',
      ].join(','),
    );

    for (var r in records) {
      String escape(String text) => '"${text.replaceAll('"', '""')}"';

      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(r.createdAt);
      final rxStr = r.medicines.map((m) {
        final name = m['name'] ?? '';
        final dose = m['dosage'] ?? '';
        final dur = m['duration'] ?? '';
        return "$name ($dose $dur)".trim();
      }).join('; ');

      csv.writeln(
        [
          escape(r.opdId.toString()),
          escape(r.uhid),
          escape(dateStr),
          escape(r.patientName),
          escape(r.ageInfo),
          escape(r.gender),
          escape(r.phone),
          escape(r.hospitalName),
          escape(r.visitType),
          escape(r.isFinalized ? "Finalized" : (r.visitStatus.isNotEmpty ? r.visitStatus : "Waiting")),
          escape(r.diagnoses.join('; ')),
          escape(r.symptoms.join('; ')),
          escape(rxStr),
          escape(r.investigations.join('; ')),
          escape(r.advices.join('; ')),
          escape(r.address),
        ].join(','),
      );
    }

    return csv.toString();
  }

  /// Exports data as Excel-compatible CSV via Printing / Share
  static Future<void> exportCsv({
    required List<AnalyticsPatientRecord> records,
    required String fileName,
  }) async {
    final csvContent = generateCsvData(records);
    final bytes = Uint8List.fromList(utf8.encode(csvContent));

    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName.endsWith('.csv') ? fileName : '$fileName.csv',
    );
  }
}
