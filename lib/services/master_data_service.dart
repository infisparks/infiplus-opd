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
  List<Map<String, String>> medicines = [];
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

      // 1. Fetch Master Drug List (Map Format)
      final medResponse = await SupabaseHandler.client.from('opd_medicine').select('medicine_name, type, unit');
      if (medResponse is List) {
        medicines = medResponse.map((row) => {
          'name': row['medicine_name']?.toString() ?? '',
          'type': row['type']?.toString() ?? '', 
          'unit': row['unit']?.toString() ?? '', 
        }).toList();
        debugPrint("✅ Medicines Synced: ${medicines.length}");
      }

      // 2. Fetch Datasets (Symptoms, Diagnoses, etc.)
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
        debugPrint("✅ Dataset Sync Complete");
      }
    } catch (e) {
      debugPrint("❌ MasterData Sync Error: $e");
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
        if (decoded is Map && decoded['data'] is List) {
          return (decoded['data'] as List).map((e) {
            if (e is Map) return (e['name'] ?? '').toString();
            return e.toString();
          }).toList();
        }
      } catch (e) {}
    }
    return [];
  }
}
