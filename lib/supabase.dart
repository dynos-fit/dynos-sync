/// Supabase adapter for dynos_sync.
///
/// Provides [SupabaseRemoteStore] — a [RemoteStore] implementation
/// that pushes/pulls data via Supabase Postgrest.
///
/// ```dart
/// import 'package:dynos_sync/supabase.dart';
/// ```
library dynos_sync.supabase;

export 'src/adapters/supabase_remote_store.dart';
