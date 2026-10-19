import 'package:flutter/foundation.dart';
import '../supabase_handler.dart';
import 'offline_sync_service.dart';

class ServerDataService {
  static final ValueNotifier<int> refreshNotifier = _initRefreshNotifier();

  static ValueNotifier<int> _initRefreshNotifier() {
    final notifier = ValueNotifier(0);
    OfflineSyncService().syncEventNotifier.addListener(() {
      notifier.value++;
    });
    return notifier;
  }

  // Directly fetch data based on the specific key with offline disk fallback
  static Future<dynamic> fetchData(int opdId, String key) async {
    // 1. If local disk has pending unsynced changes waiting in the queue,
    // NEVER fetch stale cloud data that would wipe out the doctor's offline edits!
    if (OfflineSyncService().hasPendingSync(opdId, key)) {
      debugPrint("⏳ Pending sync found for $key (OPD $opdId). Returning local disk data and triggering queue sync.");
      OfflineSyncService().syncPendingQueue();
      return OfflineSyncService().getLocalClinicalData(opdId, key);
    }

    // 2. Check local on-disk cache first (0ms response)
    final localData = OfflineSyncService().getLocalClinicalData(opdId, key);

    try {
      dynamic result;
      if (key == 'symptoms') {
        final res = await SupabaseHandler.client
            .from('opd_reg_symptoms')
            .select()
            .eq('opd_id', opdId)
            .timeout(const Duration(seconds: 4));
        result = res is List ? res : [];
      } else if (key == 'diagnosis_data') {
        final res = await SupabaseHandler.client
            .from('opd_reg_diagnosis')
            .select()
            .eq('opd_id', opdId)
            .timeout(const Duration(seconds: 4));
        result = res is List ? res : [];
      } else if (key == 'treatment_data') {
        final res = await SupabaseHandler.client
            .from('opd_reg_rx')
            .select()
            .eq('opd_id', opdId)
            .timeout(const Duration(seconds: 4));
        if (res is List) {
          result = res.map((r) => {
            'id': r['id'].toString(),
            'name': r['medicine_name'],
            'type': r['medicine_type'],
            'unit': r['unit'],
            'dosage': r['dosage'],
            'duration': r['duration'],
            'timing': r['timing_json'],
            'note': r['note'],
          }).toList();
        } else {
          result = [];
        }
      } else if (key == 'instructions_data') {
        final res = await SupabaseHandler.client
            .from('opd_reg_reports')
            .select()
            .eq('opd_id', opdId)
            .timeout(const Duration(seconds: 4));
        if (res is List) {
          Map<String, List<String>> combined = {'instructions': [], 'investigations': [], 'procedures': []};
          for (var r in res) {
            String type = r['report_type'];
            String name = r['item_name'];
            if (type == 'instruction') combined['instructions']!.add(name);
            else if (type == 'investigation') combined['investigations']!.add(name);
            else if (type == 'procedure') combined['procedures']!.add(name);
          }
          result = combined;
        } else {
          result = {};
        }
      } else {
        // Generic keys go to clinical_data in opd_registration table
        final res = await SupabaseHandler.client
            .from('opd_registration')
            .select('clinical_data, clinical_notes')
            .eq('id', opdId)
            .maybeSingle()
            .timeout(const Duration(seconds: 4));
        if (res != null) {
          if (key == 'clinical_notes') {
            result = res['clinical_notes'];
          } else if (res['clinical_data'] != null) {
            result = res['clinical_data'][key];
          }
        }
      }

      // If online fetch succeeded, save to local disk cache (without polluting sync queue)
      if (result != null) {
        await OfflineSyncService().cacheServerData(opdId, key, result);
        return result;
      }
    } catch (e) {
      debugPrint("ServerFetch Error/Offline for $key: $e (loading local disk data)");
    }

    // Return local on-disk cached data if online fetch fails or times out
    return localData;
  }

  // Directly save data with local on-disk persistence and background sync queue
  static Future<void> saveData(int opdId, String key, dynamic data, {bool silent = false}) async {
    // 1. Immediately save to physical disk & enqueue for zero data loss
    await OfflineSyncService().saveClinicalData(opdId, key, data);
    if (!silent) refreshNotifier.value++;

    // 2. Try online sync immediately
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

      // If online save succeeded, drain queue
      OfflineSyncService().syncPendingQueue();
    } catch (e) {
      debugPrint("ServerSave Offline/Pending for $key: $e (stored safely on disk)");
    }
  }

  /// Auto-picks symptoms, diagnosis, and instructions from previous visit (1-back report date)
  /// for the given patient UHID if current OPD has none. Strictly does NOT pick investigations.
  static Future<bool> autoPickFromPreviousVisit({
    required String uhid,
    required int currentOpdId,
  }) async {
    try {
      // 1. Check what the current OPD record currently has
      final currentDiagRes = await SupabaseHandler.client
          .from('opd_reg_diagnosis')
          .select()
          .eq('opd_id', currentOpdId);
      final hasCurrentDiag = currentDiagRes.isNotEmpty;

      final currentSymptomsRes = await SupabaseHandler.client
          .from('opd_reg_symptoms')
          .select()
          .eq('opd_id', currentOpdId);
      final hasCurrentSymptoms = currentSymptomsRes.isNotEmpty;

      final currentInstructionsRes = await SupabaseHandler.client
          .from('opd_reg_reports')
          .select()
          .eq('opd_id', currentOpdId)
          .eq('report_type', 'instruction');
      final hasCurrentInstructions = currentInstructionsRes.isNotEmpty;

      // If symptoms, diagnosis, and instructions are all already present, nothing to auto-pick
      if (hasCurrentDiag && hasCurrentSymptoms && hasCurrentInstructions) {
        return false;
      }

      // 2. Fetch previous visit records for this patient (1 back report date check)
      final prevVisits = await SupabaseHandler.client
          .from('opd_registration')
          .select('id, created_at')
          .eq('uhid', uhid)
          .neq('id', currentOpdId)
          .order('created_at', ascending: false);

      final prevVisitsList = prevVisits as List;
      if (prevVisitsList.isEmpty) {
        return false;
      }

      bool updated = false;

      // 3. Auto-pick Symptoms if current has none
      if (!hasCurrentSymptoms) {
        for (var visit in prevVisitsList) {
          final int prevOpdId = visit['id'];
          final prevSymptomsRes = await SupabaseHandler.client
              .from('opd_reg_symptoms')
              .select()
              .eq('opd_id', prevOpdId);

          final symptomsList = prevSymptomsRes as List;
          if (symptomsList.isNotEmpty) {
            final insertSymptoms = symptomsList.map((r) => {
              'opd_id': currentOpdId,
              'name': r['name']?.toString() ?? '',
              'note': r['note']?.toString() ?? '',
              'duration': r['duration']?.toString() ?? '',
              'severity': r['severity']?.toString() ?? '',
              'custom_groups': r['custom_groups'] ?? [],
              'selected_options': r['selected_options'] ?? [],
            }).where((s) => (s['name'] as String).isNotEmpty).toList();

            if (insertSymptoms.isNotEmpty) {
              await SupabaseHandler.client.from('opd_reg_symptoms').insert(insertSymptoms);
              updated = true;
            }
            break; // Picked from 1-back report
          }
        }
      }

      // 4. Auto-pick Diagnosis if current has none
      if (!hasCurrentDiag) {
        for (var visit in prevVisitsList) {
          final int prevOpdId = visit['id'];
          final prevDiagRes = await SupabaseHandler.client
              .from('opd_reg_diagnosis')
              .select()
              .eq('opd_id', prevOpdId);

          final diagList = prevDiagRes as List;
          if (diagList.isNotEmpty) {
            final insertDiag = diagList.map((r) => {
              'opd_id': currentOpdId,
              'name': r['name']?.toString() ?? '',
              'note': r['note']?.toString() ?? '',
            }).where((d) => (d['name'] as String).isNotEmpty).toList();

            if (insertDiag.isNotEmpty) {
              await SupabaseHandler.client.from('opd_reg_diagnosis').insert(insertDiag);
              updated = true;
            }
            break; // Picked from 1-back report
          }
        }
      }

      // 5. Auto-pick Instructions if current has none (strictly instructions only, NO investigations)
      if (!hasCurrentInstructions) {
        for (var visit in prevVisitsList) {
          final int prevOpdId = visit['id'];
          final prevInstructionsRes = await SupabaseHandler.client
              .from('opd_reg_reports')
              .select()
              .eq('opd_id', prevOpdId)
              .eq('report_type', 'instruction');

          final instructionsList = prevInstructionsRes as List;
          if (instructionsList.isNotEmpty) {
            final insertInstructions = instructionsList.map((r) => {
              'opd_id': currentOpdId,
              'item_name': r['item_name']?.toString() ?? '',
              'report_type': 'instruction',
            }).where((i) => (i['item_name'] as String).isNotEmpty).toList();

            if (insertInstructions.isNotEmpty) {
              await SupabaseHandler.client.from('opd_reg_reports').insert(insertInstructions);
              updated = true;
            }
            break; // Picked from 1-back report
          }
        }
      }

      if (updated) {
        refreshNotifier.value++;
      }
      return updated;
    } catch (e) {
      debugPrint("AutoPick Error: $e");
      return false;
    }
  }
}

