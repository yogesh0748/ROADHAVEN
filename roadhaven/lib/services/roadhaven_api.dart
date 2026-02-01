import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoadHavenApiClient {
  RoadHavenApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = _resolveBaseUrl(baseUrl);

  static const String _defaultBaseUrl = 'http://localhost:8002';
  static const String _envBase = String.fromEnvironment('ROADHAVEN_API_BASE', defaultValue: '');
  final http.Client _client;
  final String baseUrl;
  final Duration _timeout = const Duration(seconds: 15);

  static String _resolveBaseUrl(String? input) {
    final candidate = (input ?? _envBase).trim();
    return candidate.isNotEmpty ? candidate : _defaultBaseUrl;
  }

  Future<ShortestPathResult?> shortestPath(
    String start,
    String end, {
    String algorithm = 'dijkstra',
  }) async {
    final uri = _buildUri('/shortest-path/$start/$end', {'algorithm': algorithm});
    final res = await _client.get(uri).timeout(_timeout);
    final decoded = _decode(res);
    final data = _unwrapMap(decoded);
    return ShortestPathResult.fromJson(data);
  }

  Future<TripQueryResult?> queryTrip(String start, String end) async {
    final uri = _buildUri('/query');
    final payload = {
      'query': 'Plan trip from $start to $end',
      'start_loc': start,
      'end_loc': end,
    };
    final res = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final decoded = _decode(res);
    final data = _unwrapMap(decoded);
    return TripQueryResult.fromJson(data);
  }

  Future<TrafficResult?> trafficAnalysis(LatLng start, LatLng end) async {
    final uri = _buildUri('/traffic-analysis');
    final payload = {
      'start_coords': [start.latitude, start.longitude],
      'end_coords': [end.latitude, end.longitude],
    };
    final res = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final decoded = _decode(res);
    final data = _unwrapMap(decoded);
    return TrafficResult.fromJson(data);
  }

  Future<List<FuelStation>> fuelStations(
    double lat,
    double lng, {
    int radiusKm = 10,
  }) async {
    final uri = _buildUri('/fuel-stations', {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius': radiusKm.toString(),
    });
    final res = await _client.get(uri).timeout(_timeout);
    final decoded = _decode(res);
    final data = _unwrap(decoded);
    final list = data is List ? data : (data is Map && data['stations'] is List ? data['stations'] as List : <dynamic>[]);
    return list
        .whereType<Map>()
        .map((m) => FuelStation.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse(baseUrl + normalized).replace(queryParameters: query);
  }

  dynamic _decode(http.Response res) {
    final status = res.statusCode;
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (status >= 200 && status < 300) {
      return body;
    }
    final message = body is Map && body['detail'] != null ? body['detail'].toString() : res.reasonPhrase ?? 'HTTP $status';
    throw Exception('HTTP $status: $message');
  }

  dynamic _unwrap(dynamic decoded) {
    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Map<String, dynamic> _unwrapMap(dynamic decoded) {
    final unwrapped = _unwrap(decoded);
    if (unwrapped is Map<String, dynamic>) return unwrapped;
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }
}

class ShortestPathResult {
  const ShortestPathResult({
    required this.path,
    this.distanceKm,
    this.algorithm,
    this.durationMs,
    this.response,
    this.coords = const [],
  });

  final List<String> path;
  final double? distanceKm;
  final String? algorithm;
  final int? durationMs;
  final String? response;
  final List<LatLng> coords;

  factory ShortestPathResult.fromJson(Map<String, dynamic> json) {
    final rawPath = json['path'] ?? json['route'] ?? json['nodes'];
    final path = rawPath is List ? rawPath.map((e) => e.toString()).toList() : const <String>[];
    final distanceRaw = json['distance_km'] ?? json['distance'] ?? json['total_distance'];
    final durationRaw = json['duration_ms'] ?? json['duration'];
    final coords = _extractCoords(json['path_coords'] ?? json['coordinates'] ?? json['points']);
    return ShortestPathResult(
      path: path,
      distanceKm: _toDouble(distanceRaw),
      algorithm: json['algorithm']?.toString(),
      durationMs: _toInt(durationRaw),
      response: json['response']?.toString(),
      coords: coords,
    );
  }
}

class TripQueryResult {
  const TripQueryResult({
    this.response,
    this.routeId,
    this.markers = const [],
    this.mlInsights,
  });

  final String? response;
  final String? routeId;
  final List<LatLng> markers;
  final Map<String, dynamic>? mlInsights;

  factory TripQueryResult.fromJson(Map<String, dynamic> json) {
    final markers = _extractCoords(json['markers'] ?? json['points'] ?? json['route_points']);
    return TripQueryResult(
      response: json['response']?.toString(),
      routeId: json['route_id']?.toString(),
      markers: markers,
      mlInsights: json['ml_insights'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['ml_insights'] as Map)
          : null,
    );
  }
}

class TrafficResult {
  const TrafficResult({
    this.summary,
    this.delayMinutes,
    this.incidents = const [],
  });

  final String? summary;
  final double? delayMinutes;
  final List<String> incidents;

  factory TrafficResult.fromJson(Map<String, dynamic> json) {
    final incidentsRaw = json['incidents'] ?? json['issues'] ?? [];
    final incidents = incidentsRaw is List
        ? incidentsRaw.map((e) => e.toString()).toList()
        : const <String>[];
    final summary = json['summary'] ?? json['recommendation'] ?? json['message'];
    final delay = json['delay_minutes'] ?? json['delay'] ?? json['eta_delta_minutes'];
    return TrafficResult(
      summary: summary?.toString(),
      delayMinutes: _toDouble(delay),
      incidents: incidents,
    );
  }
}

class FuelStation {
  const FuelStation({
    required this.name,
    this.brand,
    this.distanceKm,
    this.pricePerLiter,
    this.rating,
    this.open24h,
    this.amenities = const [],
    this.point,
  });

  final String name;
  final String? brand;
  final double? distanceKm;
  final double? pricePerLiter;
  final double? rating;
  final bool? open24h;
  final List<String> amenities;
  final LatLng? point;

  factory FuelStation.fromJson(Map<String, dynamic> json) {
    final point = _extractCoords(json['coords'] ?? json['location']).firstOrNull;
    return FuelStation(
      name: json['name']?.toString() ?? 'Fuel station',
      brand: json['brand']?.toString(),
      distanceKm: _toDouble(json['distance_km'] ?? json['distance']),
      pricePerLiter: _toDouble(json['price_per_liter'] ?? json['price']),
      rating: _toDouble(json['rating'] ?? json['score']),
      open24h: json['open_24hrs'] as bool? ?? json['open_24h'] as bool?,
      amenities: json['amenities'] is List
          ? (json['amenities'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      point: point,
    );
  }
}

List<LatLng> _extractCoords(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) {
          if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
            return LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble());
          }
          if (e is Map && e['lat'] is num && e['lng'] is num) {
            return LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble());
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }
  return const <LatLng>[];
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
