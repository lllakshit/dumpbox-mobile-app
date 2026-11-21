/// Build-time settings, passed with `--dart-define` or `--dart-define-from-file=config/<env>.json`.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Base URL of the DumpBox web app that serves /v1 (for example https://dumpbox.vercel.app).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty && apiBaseUrl.isNotEmpty;

  static String get apiBase => apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
}
