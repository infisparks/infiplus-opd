import 'package:flutter/foundation.dart';
import '../supabase_handler.dart';

class ServerDataService {
  static final ValueNotifier<int> refreshNotifier = ValueNotifier(0);

  // Directly fetch data based on the specific key
  static Future<dynamic> fetchData(int opdId, String key) async {
    try {
      if (key == 'symptoms') {
        final res = await SupabaseHandler.client.from('opd_reg_symptoms').select().eq('opd_id', opdId);
        return res is List ? res : [];
      } else if (key == 'diagnosis_data') {
        final res = await SupabaseHandler.client.from('opd_reg_diagnosis').select().eq('opd_id', opdId);
        return res is List ? res : [];
      } else if (key == 'treatment_data') {
        final res = await SupabaseHandler.client.from('opd_reg_rx').select().eq('opd_id', opdId);
        if (res is List) {
          return res.map((r) => {
            'id': r['id'].toString(),
            'name': r['medicine_name'],
            'type': r['medicine_type'],
            'unit': r['unit'],
            'dosage': r['dosage'],
            'duration': r['duration'],
            'timing': r['timing_json'],
            'note': r['note'],
          }).toList();
        }
        return [];
      } else if (key == 'instructions_data') {
        final res = await SupabaseHandler.client.from('opd_reg_reports').select().eq('opd_id', opdId);
        if (res is List) {
          Map<String, List<String>> combined = {'instructions': [], 'investigations': [], 'procedures': []};
          for (var r in res) {
            String type = r['report_type'];
            String name = r['item_name'];
            if (type == 'instruction') combined['instructions']!.add(name);
            else if (type == 'investigation') combined['investigations']!.add(name);
            else if (type == 'procedure') combined['procedures']!.add(name);
          }
          return combined;
        }
        return {};
      } else {
        // Generic keys go to clinical_data in opd_registration table
        final res = await SupabaseHandler.client.from('opd_registration').select('clinical_data, clinical_notes').eq('id', opdId).maybeSingle();
        if (res != null) {
          if (key == 'clinical_notes') return res['clinical_notes'];
          if (res['clinical_data'] != null) {
            return res['clinical_data'][key];
          }
        }
      }
    } catch (e) {
      debugPrint("ServerFetch Error for $key: $e");
    }
    return null;
  }

  // Directly save data to server immediately
  static Future<void> saveData(int opdId, String key, dynamic data, {bool silent = false}) async {
    try {
      if (key == 'symptoms') {
        await SupabaseHandler.client.from('opd_reg_symptoms').delete().eq('opd_id', opdId);
        if (data is List && data.isNotEmpty) {
          final insertData = data.map((e) => {
            'opd_id': opdId,
            'name': e['name'],
            'note': e['note'] ?? '',
            'duration': e['duration'] ?? '',
            'severity': e['severity'] ?? '',
            'custom_groups': e['custom_groups'] ?? [],
            'selected_options': e['selected_options'] ?? [],
          }).toList();
          await SupabaseHandler.client.from('opd_reg_symptoms').insert(insertData);
        }
      } else if (key == 'diagnosis_data') {
        await SupabaseHandler.client.from('opd_reg_diagnosis').delete().eq('opd_id', opdId);
        if (data is List && data.isNotEmpty) {
          final insertData = data.map((e) {
            String name = (e is Map) ? (e['name'] ?? '') : e.toString();
            String note = (e is Map) ? (e['note'] ?? '') : '';
            return { 'opd_id': opdId, 'name': name, 'note': note };
          }).where((d) => (d['name'] as String).isNotEmpty).toList();
          await SupabaseHandler.client.from('opd_reg_diagnosis').insert(insertData);
        }
      } else if (key == 'treatment_data') {
        await SupabaseHandler.client.from('opd_reg_rx').delete().eq('opd_id', opdId);
        if (data is List && data.isNotEmpty) {
          final insertData = data.map((e) => {
            'opd_id': opdId,
            'medicine_name': e['name'],
            'medicine_type': e['type'],
            'unit': e['unit'] ?? '',
            'dosage': e['dosage'] ?? '',
            'duration': e['duration'] ?? '',
            'timing_json': e['timing'] ?? {},
            'note': e['note'] ?? '',
          }).toList();
          await SupabaseHandler.client.from('opd_reg_rx').insert(insertData);
        }
      } else if (key == 'instructions_data') {
        await SupabaseHandler.client.from('opd_reg_reports').delete().eq('opd_id', opdId);
        if (data is Map) {
          List<Map<String, dynamic>> combinedReports = [];
          if (data['instructions'] is List) {
            combinedReports.addAll((data['instructions'] as List).map((v) => {
              'opd_id': opdId, 'item_name': v, 'report_type': 'instruction'
            }));
          }
          if (data['investigations'] is List) {
            combinedReports.addAll((data['investigations'] as List).map((v) => {
              'opd_id': opdId, 'item_name': v, 'report_type': 'investigation'
            }));
          }
          if (data['procedures'] is List) {
            combinedReports.addAll((data['procedures'] as List).map((v) => {
              'opd_id': opdId, 'item_name': v, 'report_type': 'procedure'
            }));
          }
          if (combinedReports.isNotEmpty) {
            await SupabaseHandler.client.from('opd_reg_reports').insert(combinedReports);
          }
        }
      } else {
        // Generic json clinical data handling
        final currentFetch = await SupabaseHandler.client.from('opd_registration').select('clinical_data').eq('id', opdId).maybeSingle();
        Map<String, dynamic> existing = (currentFetch != null && currentFetch['clinical_data'] != null) ? Map<String, dynamic>.from(currentFetch['clinical_data']) : {};
        if (key == 'clinical_notes') {
          await SupabaseHandler.client.from('opd_registration').update({'clinical_notes': data}).eq('id', opdId);
        } else {
          existing[key] = data;
          await SupabaseHandler.client.from('opd_registration').update({'clinical_data': existing}).eq('id', opdId);
        }
      }

      if (!silent) refreshNotifier.value++;
    } catch (e) {
      debugPrint("ServerSave Error for $key: $e");
    }
  }
}
