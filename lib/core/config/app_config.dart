/// Build-time configuration.  Pass values with `--dart-define` for release
/// builds; the public Supabase anon key is intentionally not treated as a
/// secret.  The ESP AES key is never present in this application.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lqzazbejzpxjndoegoly.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxxemF6YmVqenB4am5kb2Vnb2x5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2Mzc1MzUsImV4cCI6MjA5NTIxMzUzNX0.ytHROXhLa972Ay1NLRE_N2KcGvP8a5cOLUkBkfhn8Vo',
  );

  /// The domain without an `@`; configure this per campus at build time.
  static const collegeEmailDomain = String.fromEnvironment(
    'COLLEGE_EMAIL_DOMAIN',
    defaultValue: 'sliet.ac.in',
  );

  static bool isCollegeEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized) &&
        normalized.endsWith('@${collegeEmailDomain.toLowerCase()}');
  }
}
