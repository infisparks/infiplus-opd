import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseHandler {
  // Credentials provided by you
  static const String _url = 'https://sigma.infiplus.in';
  static const String _anonKey = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc2MzMxMTkyMCwiZXhwIjo0OTE4OTg1NTIwLCJyb2xlIjoiYW5vbiJ9.3uCC6yWwfwFR_pgsRoljVHTcWG6VLV4a3qxLOxbO1xI';

  // Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
    );
  }

  // Getter for the client to use throughout the app
  static SupabaseClient get client => Supabase.instance.client;
}