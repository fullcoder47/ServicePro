/// Browser sandboxes cannot perform raw DNS lookups.
/// Let real Supabase requests report network failures instead of blocking the UI.
Future<bool> probeInternet() async => true;
