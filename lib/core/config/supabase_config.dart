class SupabaseConfig {
  static const String url = 'https://inbqjyypfpfqnpcjqkqn.supabase.co';

  static const String anonKey = 'sb_publishable_WoChgUSNH35UQzMEyyzrCQ_bjcELvEq';

  static bool get isConfigured {
    return url.isNotEmpty &&
        anonKey.isNotEmpty &&
        !url.contains('YOUR_PROJECT_ID') &&
        !anonKey.contains('YOUR_SUPABASE_ANON_KEY');
  }
}