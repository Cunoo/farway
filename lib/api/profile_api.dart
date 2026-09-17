import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileApi {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<String> getUserId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('User is not logged in or session has expired');
    }
    return user.id;
  }

  Future<Map<String, dynamic>?> getProfile() async {
    final userId = await getUserId();
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    return data;
  }
}