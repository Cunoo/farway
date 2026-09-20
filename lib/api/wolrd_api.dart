import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> callAddNumbers(LatLng? currentCoords) async {
  final supabase = Supabase.instance.client;
  try {
    // Zavolanie SQL funkcie "get_closest_road_info"
    final int result = await supabase.rpc(
      'get_closest_road_info',
      params: {
        'input_lon': currentCoords?.longitude ?? 10,
        'input_lat': currentCoords?.latitude ?? 10,
      },
    );

    print('Výsledok: $result'); // Vytlačí: Výsledok: 15
  } catch (error) {
    print('Chyba pri volaní RPC: $error');
  }
}