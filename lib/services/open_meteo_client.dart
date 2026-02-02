import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;

import '../models/geo_location.dart';
import '../models/weather_models.dart';

class OpenMeteoClient {
  OpenMeteoClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<http.Response> _get(Uri uri, {String? label}) async {
    final response = await _client.get(uri);
    if (response.statusCode == 429) {
      final retry = response.headers['retry-after'];
      final retryText = retry != null ? ' Retry-After: $retry' : '';
      throw Exception('Too many requests (429).$retryText');
    }
    if (response.statusCode != 200) {
      final preview = response.body.isNotEmpty
          ? response.body.substring(0, response.body.length.clamp(0, 200))
          : '';
      final tag = label != null ? ' for $label' : '';
      throw Exception('Request$tag failed (${response.statusCode}) [${uri.toString()}]. $preview');
    }
    return response;
  }

  Future<List<GeoLocation>> searchLocations(String query) async {
    final languageCode = PlatformDispatcher.instance.locale.languageCode.isNotEmpty
        ? PlatformDispatcher.instance.locale.languageCode
        : 'en';
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '5',
      'language': languageCode,
      'format': 'json',
    });
    final response = await _get(uri, label: 'location search');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(GeoLocation.fromJson)
        .toList(growable: false);
  }

  Future<GeoLocation> reverseGeocode({required double latitude, required double longitude}) async {
    final languageCode = PlatformDispatcher.instance.locale.languageCode.isNotEmpty
        ? PlatformDispatcher.instance.locale.languageCode
        : 'en';
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/reverse', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'count': '1',
      'language': languageCode,
      'format': 'json',
    });
    try {
      final response = await _get(uri, label: 'reverse geocoding');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];
      if (results.isNotEmpty && results.first is Map<String, dynamic>) {
        return GeoLocation.fromJson(results.first as Map<String, dynamic>);
      }
    } catch (_) {
      // Fall through to Nominatim fallback below.
    }

    final fallback = await _reverseGeocodeWithNominatim(latitude: latitude, longitude: longitude, languageCode: languageCode);
    if (fallback != null) return fallback;

    return GeoLocation(name: 'Current location', country: '', latitude: latitude, longitude: longitude);
  }

  Future<GeoLocation?> _reverseGeocodeWithNominatim({required double latitude, required double longitude, required String languageCode}) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'zoom': '10',
      'accept-language': languageCode,
    });
    final response = await _client.get(uri, headers: {
      'User-Agent': 'histoweather-app/1.0 (reverse-geocode)'
    });
    if (response.statusCode != 200) {
      return null;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final displayName = body['display_name'] as String?;
    final address = body['address'] as Map<String, dynamic>?;
    final country = address?['country'] as String? ?? '';
    final name = displayName ?? address?['city'] as String? ?? address?['town'] as String? ?? address?['village'] as String? ?? 'Current location';
    return GeoLocation(
      name: name,
      country: country,
      latitude: latitude,
      longitude: longitude,
      admin1: address?['state'] as String?,
    );
  }

  Future<TodayForecast> fetchTodayForecast({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'daily': 'temperature_2m_max,temperature_2m_min',
      'forecast_days': '1',
      'timezone': 'auto',
    });
    final response = await _get(uri, label: 'forecast');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = body['daily'] as Map<String, dynamic>?;
    final tMax = _firstDouble(daily?['temperature_2m_max']);
    final tMin = _firstDouble(daily?['temperature_2m_min']);
    final mean = _avgNullable(tMax, tMin);
    return TodayForecast(tMaxC: tMax, tMinC: tMin, tMeanC: mean);
  }

  Future<List<DailyWeatherSample>> fetchArchive({
    required double latitude,
    required double longitude,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final end = endDate ?? DateTime.now();
    final start = startDate ?? DateTime(1979, 1, 1);
    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'start_date': _fmtDate(start),
      'end_date': _fmtDate(end),
      'timezone': 'auto',
      'daily': 'temperature_2m_mean,temperature_2m_max,temperature_2m_min',
    });
    final response = await _get(uri, label: 'archive');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = body['daily'] as Map<String, dynamic>?;
    final times = (daily?['time'] as List?)?.cast<String>() ?? [];
    final meanTemps = (daily?['temperature_2m_mean'] as List?)?.cast<num?>();
    final maxTemps = (daily?['temperature_2m_max'] as List?)?.cast<num?>();
    final minTemps = (daily?['temperature_2m_min'] as List?)?.cast<num?>();

    return List<DailyWeatherSample>.generate(times.length, (index) {
      final date = DateTime.parse(times[index]);
      final tMean = meanTemps != null && index < meanTemps.length
          ? (meanTemps[index])?.toDouble()
          : null;
      final tMax = maxTemps != null && index < maxTemps.length
          ? (maxTemps[index])?.toDouble()
          : null;
      final tMin = minTemps != null && index < minTemps.length
          ? (minTemps[index])?.toDouble()
          : null;
      return DailyWeatherSample(
        date: date,
        tMeanC: tMean,
        tMaxC: tMax,
        tMinC: tMin,
      );
    }, growable: false);
  }

  static String _fmtDate(DateTime dt) => '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static double? _firstDouble(dynamic list) {
    final values = (list as List?)?.cast<num?>();
    if (values == null || values.isEmpty) return null;
    return values.first?.toDouble();
  }

  static double? _avgNullable(double? a, double? b) {
    if (a == null && b == null) return null;
    if (a != null && b != null) return (a + b) / 2;
    return a ?? b;
  }
}
