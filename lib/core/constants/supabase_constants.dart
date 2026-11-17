class SupabaseConstants {
  // Only publishable configuration belongs in a client application.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mepulcdlighuiwgbutnx.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
}
