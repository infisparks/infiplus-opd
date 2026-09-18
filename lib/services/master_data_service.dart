import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../supabase_handler.dart';

/// MasterDataService: A high-performance singleton for clinical data.
/// Loads clinical datasets (Symptoms, Diagnoses, Medicines, etc.) into memory session-only.
class MasterDataService {
  static final MasterDataService _instance = MasterDataService._internal();
  factory MasterDataService() => _instance;
  MasterDataService._internal();

  // --- SESSION MEMORY CACHE ---
  List<String> symptoms = [];
  List<String> findings = [];
  List<String> diagnoses = [];
  List<Map<String, dynamic>> medicines = [];
  List<String> instructions = [];
  List<String> investigations = [];
  List<String> procedures = [];

  bool isLoaded = false;
  final ValueNotifier<bool> loadStatus = ValueNotifier(false);

  /// Fetch all master data from Cloud on startup.
  Future<void> initialize() async {
    // Always refetch if requested (Load every time from server policy)
    await syncWithCloud();
    
    isLoaded = true;
    loadStatus.value = true;
  }

  /// Refetches latest datasets from Supabase and updates in-memory cache.
  Future<void> syncWithCloud() async {
    try {
      debugPrint("📡 Syncing Master Data from Cloud...");

      // Fetch both in parallel to reduce startup time
      await Future.wait([
        _syncMedicines(),
        _syncDatasets(),
      ]);
      
      debugPrint("✅ Master Data Sync Complete");
    } catch (e) {
      debugPrint("❌ MasterData Sync Error: $e");
    }
  }

  static Map<String, dynamic>? parseMetadata(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _syncMedicines() async {
    try {
      final medResponse = await SupabaseHandler.client
          .from('opd_medicine')
          .select('medicine_name, type, unit, default_note, metadata');
      if (medResponse is List) {
        medicines = medResponse.map((row) => {
          'name': row['medicine_name']?.toString() ?? '',
          'type': row['type']?.toString() ?? '', 
          'unit': row['unit']?.toString() ?? '', 
          'default_note': row['default_note']?.toString() ?? '', 
          'metadata': parseMetadata(row['metadata']),
        }).toList();
        debugPrint("✅ Medicines Synced: ${medicines.length}");
      }
    } catch (e) {
      debugPrint("❌ MasterData Sync Error (_syncMedicines): $e");
    }
  }

  /// Helper to lookup medicine case-insensitively with trimmed name
  Map<String, dynamic>? findMedicine(String name) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final idx = medicines.indexWhere(
      (m) => (m['name']?.toString().trim().toLowerCase() ?? '') == clean,
    );
    if (idx != -1) return medicines[idx];
    return null;
  }

  Future<void> _syncDatasets() async {
    final response = await SupabaseHandler.client.from('opd_datasets').select('dataname, datajson');
    if (response is List) {
      for (var row in response) {
        final name = row['dataname']?.toString().trim().toLowerCase();
        final rawJson = row['datajson'];
        List<String> list = _parseJsonList(rawJson);

        if (name == 'symptoms') symptoms = list;
        else if (name == 'diagnosis') diagnoses = list;
        else if (name == 'findings') findings = list;
        else if (name == 'instructions') instructions = list;
        else if (name == 'investigations') investigations = list;
        else if (name == 'procedures') procedures = list;
      }
      debugPrint("✅ Datasets Synced");
    }
  }

  List<String> _parseJsonList(dynamic rawJson) {
    if (rawJson is List) {
      return rawJson.map((e) {
        if (e is Map) return (e['name'] ?? '').toString();
        return e.toString();
      }).toList();
    }
    if (rawJson is String) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          return decoded.map((e) {
            if (e is Map) return (e['name'] ?? '').toString();
            return e.toString();
          }).toList();
        }
      } catch (e) {}
    }
    return [];
  }

  /// Saves a dataset back to Supabase (opd_datasets table).
  /// This ensures new symptoms, diagnoses, etc., are permanent.
  Future<void> saveDataset(String dataname, List<String> data) async {
    try {
      final name = dataname.trim().toLowerCase();
      // Update local memory cache first for instant UI response
      if (name == 'symptoms') symptoms = data;
      else if (name == 'diagnosis') diagnoses = data;
      else if (name == 'findings') findings = data;
      else if (name == 'instructions') instructions = data;
      else if (name == 'investigations') investigations = data;
      else if (name == 'procedures') procedures = data;

      // Sync to Supabase using upsert
      await SupabaseHandler.client.from('opd_datasets').upsert({
        'dataname': dataname,
        'datajson': data,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'dataname');

      debugPrint("✅ MasterDataService: Dataset '$dataname' saved to Cloud.");
    } catch (e) {
      debugPrint("❌ MasterDataService: Save error for '$dataname': $e");
    }
  }

  // --- 4. RANKING & USAGE LOGIC ---
  Map<String, int> _usageRanks = {}; // Key: "type_name", Value: count

  /// Loads usage rankings for instructions, investigations, etc.
  Future<void> loadUsageRanks() async {
    try {
      final response = await SupabaseHandler.client
          .from('opd_report_item_usage_rank')
          .select('item_type, item_name, usage_count');
      
      if (response is List) {
        _usageRanks.clear();
        for (var row in response) {
          final key = "${row['item_type']}_${row['item_name']}";
          _usageRanks[key] = row['usage_count'] ?? 0;
        }
      }
    } catch (e) {
      debugPrint("❌ MasterDataService: Error loading ranks: $e");
    }
  }

  /// Increments usage count for an item to move it to the top.
  Future<void> trackUsage(String type, String name) async {
    try {
      // 1. Update local cache for instant sorting
      final key = "${type}_$name";
      _usageRanks[key] = (_usageRanks[key] ?? 0) + 1;

      // 2. Update Cloud (using the RPC function we created)
      await SupabaseHandler.client.rpc('increment_opd_item_usage', params: {
        'p_item_type': type,
        'p_item_name': name,
      });
    } catch (e) {
      // Fallback if RPC is not installed: simple upsert (won't increment but updates last_used)
      try {
        await SupabaseHandler.client.from('opd_report_item_usage_rank').upsert({
          'item_type': type,
          'item_name': name,
          'last_used_at': DateTime.now().toIso8601String(),
        }, onConflict: 'item_type, item_name');
      } catch (_) {}
    }
  }

  /// Helper to get usage count for sorting
  int getUsageCount(String type, String name) {
    return _usageRanks["${type}_$name"] ?? 0;
  }

  /// Saves or Updates a medicine in the opd_medicine table.
  /// This ensures that type, unit, default note, and metadata (dosage, timing, duration) preferences are remembered.
  Future<void> saveMedicine(
    String name, 
    String type, 
    String unit, {
    String? defaultNote,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final nameClean = name.trim();
      if (nameClean.isEmpty) return;

      final index = medicines.indexWhere(
        (m) => (m['name']?.toString().trim().toLowerCase() ?? '') == nameClean.toLowerCase(),
      );

      // Preserve existing values if not passed
      String finalType = type;
      String finalUnit = unit;
      String? finalNote = defaultNote;
      Map<String, dynamic>? finalMeta = metadata;

      if (index != -1) {
        final existingItem = medicines[index];
        if (finalType.isEmpty && existingItem['type'] != null) {
          finalType = existingItem['type'].toString();
        }
        if (finalUnit.isEmpty && existingItem['unit'] != null) {
          finalUnit = existingItem['unit'].toString();
        }
        if (finalNote == null && existingItem['default_note'] != null) {
          finalNote = existingItem['default_note'].toString();
        }
        if (finalMeta == null && existingItem['metadata'] != null) {
          finalMeta = parseMetadata(existingItem['metadata']);
        }
      }

      final Map<String, dynamic> updatedMap = {
        'name': nameClean,
        'type': finalType,
        'unit': finalUnit,
        if (finalNote != null) 'default_note': finalNote,
        if (finalMeta != null) 'metadata': finalMeta,
      };

      if (index != -1) {
        medicines[index] = {...medicines[index], ...updatedMap};
      } else {
        medicines.add(updatedMap);
      }

      // 2. Check Cloud for existing record by name
      final existing = await SupabaseHandler.client
          .from('opd_medicine')
          .select('id')
          .ilike('medicine_name', nameClean)
          .maybeSingle();

      final Map<String, dynamic> updateFields = {
        'type': finalType,
        'unit': finalUnit,
        if (finalNote != null) 'default_note': finalNote,
        if (finalMeta != null) 'metadata': finalMeta,
      };

      if (existing != null) {
        // Update existing medicine preference
        await SupabaseHandler.client
            .from('opd_medicine')
            .update(updateFields)
            .eq('id', existing['id']);
        debugPrint("✅ MasterDataService: Medicine '$nameClean' preferences updated.");
      } else {
        // Insert as new master record
        await SupabaseHandler.client.from('opd_medicine').insert({
          'medicine_name': nameClean,
          ...updateFields,
        });
        debugPrint("✅ MasterDataService: Medicine '$nameClean' created in master list.");
      }
    } catch (e) {
      debugPrint("❌ MasterDataService: Save preference error: $e");
    }
  }
}
