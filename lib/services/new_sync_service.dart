import 'package:flutter/material.dart';

class NewLocalStorageService {
  static Future<void> init() async {}
}

class NewSyncService {
  static ValueNotifier<bool> isSyncingNotifier = ValueNotifier(false);

  static Future<void> createPage(Map<String, dynamic> row) async {}
  static Future<void> updatePage(String id, Map<String, dynamic> row) async {}
  static Future<void> syncPendingRows() async {}
}
