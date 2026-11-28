class SupabaseConstants {
  // Supabase publishable keys are intended for public web/mobile clients.
  // Authorization is enforced through Supabase Row Level Security.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mepulcdlighuiwgbutnx.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_YkKoJyA9EkPblXn_9t8Rjg_ogNqjKKV',
  );
}
