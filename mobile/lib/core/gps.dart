import 'package:geolocator/geolocator.dart';

class Gps {
  /// One reading, only at the moment of a scan or photo. No background tracking.
  static Future<Position?> read() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 12)),
      );
    } catch (_) {
      return null; // inspection is still saved; the server flags it "no_gps"
    }
  }
}
