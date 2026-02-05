import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:roadhaven/services/auth_service.dart';
import 'package:roadhaven/screens/map_page.dart';
import 'package:roadhaven/services/roadhaven_api.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<Position> _positionFuture;
  bool _showMap = true;
  bool _showWeather = true;
  final _sourceCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _apiClient = RoadHavenApiClient();
  List<_RouteSuggestion> _routes = const [];
  bool _routesLoading = false;
  String? _routesError;
  String? _preferredVehicle;
  LatLng? _currentLatLng;
  LatLng? _inputSourceLatLng;
  LatLng? _inputDestLatLng;
  ShortestPathResult? _shortestPath;
  TripQueryResult? _tripQuery;
  TrafficResult? _trafficResult;
  List<FuelStation> _fuelStations = const [];
  String? _backendError;
  List<LatLng> _backendMarkers = const [];
  OsmRoute? _osmRoute;
  String? _osmRouteError;

  @override
  void initState() {
    super.initState();
    _positionFuture = _determinePosition();
    _loadPreferredVehicle();
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  Future<Position> _determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied. Enable them in settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _loadPreferredVehicle() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _firestore
          .collection('profiles')
          .doc(uid)
          .collection('vehicles')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final make = (data['make'] ?? '').toString().trim();
        final model = (data['model'] ?? '').toString().trim();
        setState(() {
          _preferredVehicle = [make, model].where((e) => e.isNotEmpty).join(' ');
        });
      }
    } catch (e) {
      debugPrint('load vehicle failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RoadHaven'),
        actions: const [],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const ListTile(
                leading: Icon(Icons.menu),
                title: Text('Menu'),
              ),
              ExpansionTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('Widgets'),
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.map),
                    title: const Text('Map (current location)'),
                    value: _showMap,
                    onChanged: (val) {
                      setState(() => _showMap = val);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_queue),
                    title: const Text('Weather (hourly)'),
                    value: _showWeather,
                    onChanged: (val) {
                      setState(() => _showWeather = val);
                    },
                  ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  await AuthService().signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_showMap) ...[
            Text(
              'Your Current Location',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 220,
                color: colorScheme.surfaceContainerHighest,
                child: FutureBuilder<Position>(
                  future: _positionFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: colorScheme.primary,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    final position = snapshot.data;
                    if (position == null) {
                      return Center(
                        child: Text(
                          'Unable to fetch location.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    final latLng = LatLng(position.latitude, position.longitude);
                    if (_currentLatLng == null) {
                      // Store once so we can draw polylines to route markers.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _currentLatLng = latLng);
                      });
                    }
                    return FlutterMap(
                      options: MapOptions(
                        initialCenter: latLng,
                        initialZoom: 15,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.roadhaven',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: latLng,
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.location_on,
                                color: colorScheme.primary,
                                size: 36,
                              ),
                            ),
                            if (_inputSourceLatLng != null)
                              Marker(
                                point: _inputSourceLatLng!,
                                width: 32,
                                height: 32,
                                child: Tooltip(
                                  message: 'Source',
                                  child: const Icon(
                                    Icons.radio_button_checked,
                                    color: Colors.greenAccent,
                                    size: 24,
                                  ),
                                ),
                              ),
                            if (_inputDestLatLng != null)
                              Marker(
                                point: _inputDestLatLng!,
                                width: 32,
                                height: 32,
                                child: Tooltip(
                                  message: 'Destination',
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: Colors.redAccent,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ..._routes
                                .where((r) => r.point != null)
                                .map(
                                  (r) => Marker(
                                    point: r.point!,
                                    width: 34,
                                    height: 34,
                                    child: Tooltip(
                                      message: r.title,
                                      child: Icon(
                                        Icons.flag,
                                        color: colorScheme.secondary,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            ..._backendMarkers
                                .map(
                                  (p) => Marker(
                                    point: p,
                                    width: 30,
                                    height: 30,
                                    child: Tooltip(
                                      message: 'API marker',
                                      child: Icon(
                                        Icons.location_history,
                                        color: colorScheme.tertiary,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ],
                        ),
                        if (_osmRoute?.points.isNotEmpty == true)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _osmRoute!.points,
                                color: colorScheme.primary.withOpacity(0.9),
                                strokeWidth: 5,
                              ),
                            ],
                          ),
                        if (_currentLatLng != null &&
                            _routes.any((r) => r.point != null))
                          PolylineLayer(
                            polylines: _routes
                                .where((r) => r.point != null)
                                .map(
                                  (r) => Polyline(
                                    points: [_currentLatLng!, r.point!],
                                    color: colorScheme.secondary.withOpacity(0.65),
                                    strokeWidth: 4,
                                  ),
                                )
                                .toList(),
                          ),
                        if (_inputSourceLatLng != null && _inputDestLatLng != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: [_inputSourceLatLng!, _inputDestLatLng!],
                                color: colorScheme.primary.withOpacity(0.8),
                                strokeWidth: 4,
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_showWeather) ...[
            Text(
              'Weather forecast (hourly)',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Position>(
              future: _positionFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  );
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Weather unavailable: ${snapshot.error ?? 'location missing'}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                final pos = snapshot.data!;
                final mock = _buildMockForecast();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lat ${pos.latitude.toStringAsFixed(4)}, Lon ${pos.longitude.toStringAsFixed(4)}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...mock.map((item) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.cloud_queue),
                              title: Text('${item['time']}  •  ${item['temp']}°C'),
                              subtitle: Text(item['note'] ?? ''),
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open map page'),
              onPressed: () => _openMapPage(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Plan a trip',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _sourceCtrl,
                    decoration: const InputDecoration(labelText: 'Source'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _destCtrl,
                    decoration: const InputDecoration(labelText: 'Destination'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.alt_route),
                      label: const Text('Fetch best 3 routes'),
                      onPressed: _routesLoading ? null : _buildSuggestions,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_routesLoading)
                    Row(
                      children: const [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Fetching community routes...'),
                      ],
                    ),
                  if (_routesError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _routesError!,
                        style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                      ),
                    ),
                  if (!_routesLoading && _routes.isNotEmpty) ...[
                    Text(
                      'Suggested routes from community:',
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      children: _routes
                          .map(
                            (r) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(child: Text(r.label)),
                              title: Text(r.title),
                              subtitle: Text(r.summary),
                              trailing: r.rating != null
                                  ? Chip(label: Text('★ ${r.rating!.toStringAsFixed(1)}'))
                                  : null,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (!_routesLoading && _routes.isEmpty && _routesError == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'No community suggestions for this route yet.',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_backendError != null)
                    Text(
                      'Backend: $_backendError',
                      style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                    ),
                  if (_osmRouteError != null)
                    Text(
                      'OpenStreetMap: $_osmRouteError',
                      style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                    ),
                  if (_osmRoute != null && _osmRoute!.points.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.route),
                      title: const Text('OpenStreetMap route'),
                      subtitle: Text(
                        [
                          if (_osmRoute!.distanceKm != null)
                            '${_osmRoute!.distanceKm!.toStringAsFixed(1)} km',
                          if (_osmRoute!.durationMinutes != null)
                            '${_osmRoute!.durationMinutes!.toStringAsFixed(0)} min est.',
                        ].whereType<String>().join(' • '),
                      ),
                    ),
                  if (_shortestPath != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.alt_route),
                      title: const Text('Shortest path (API)'),
                      subtitle: Text(
                        _shortestPath!.path.isNotEmpty
                            ? _shortestPath!.path.join(' -> ')
                            : (_shortestPath!.response ?? 'Result received'),
                      ),
                      trailing: _shortestPath!.distanceKm != null
                          ? Chip(
                              label: Text(
                                '${_shortestPath!.distanceKm!.toStringAsFixed(1)} km',
                              ),
                            )
                          : null,
                    ),
                  if (_tripQuery != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.map_outlined),
                      title: const Text('Trip plan (API)'),
                      subtitle: Text(_tripQuery!.response ?? 'Trip planned'),
                      trailing: _tripQuery!.routeId != null
                          ? Chip(label: Text('Route ${_tripQuery!.routeId}'))
                          : null,
                    ),
                  if (_trafficResult != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.traffic),
                      title: const Text('Traffic analysis'),
                      subtitle: Text(
                        [
                          _trafficResult!.summary,
                          _trafficResult!.delayMinutes != null
                              ? '${_trafficResult!.delayMinutes!.toStringAsFixed(1)} min delay'
                              : null,
                          if (_trafficResult!.incidents.isNotEmpty)
                            _trafficResult!.incidents.take(2).join(' | '),
                        ].whereType<String>().join(' | '),
                      ),
                    ),
                  if (_fuelStations.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Nearby fuel stations (API):',
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    ..._fuelStations.take(3).map(
                          (s) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.local_gas_station),
                            title: Text(s.name),
                            subtitle: Text([
                              if (s.brand != null && s.brand!.isNotEmpty) s.brand,
                              if (s.distanceKm != null)
                                '${s.distanceKm!.toStringAsFixed(1)} km',
                              if (s.pricePerLiter != null)
                                'INR ${s.pricePerLiter!.toStringAsFixed(2)}/L',
                            ].whereType<String>().join(' | ')),
                            trailing: s.rating != null ? Text('★ ${s.rating!.toStringAsFixed(1)}') : null,
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_tripTipsForVehicle().isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip suggestions${_preferredVehicle != null ? ' for $_preferredVehicle' : ''}',
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ..._tripTipsForVehicle().map(
                      (tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(tip)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openMapPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MapPage()),
    );
  }

  Future<void> _buildSuggestions() async {
    final src = _sourceCtrl.text.trim();
    final dst = _destCtrl.text.trim();
    if (src.isEmpty || dst.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both source and destination')),
      );
      return;
    }

    setState(() {
      _routesLoading = true;
      _routesError = null;
      _backendError = null;
      _osmRouteError = null;
      _osmRoute = null;
      _backendMarkers = const [];
    });

    // Try to parse coordinates from input (format: "lat,lng"), otherwise geocode.
    LatLng? resolvedSrc = _parseLatLng(src);
    LatLng? resolvedDst = _parseLatLng(dst);
    String? geocodeError;

    if (resolvedSrc == null) {
      try {
        resolvedSrc = await _apiClient.geocodeLatLng(src);
      } catch (e) {
        geocodeError = 'Source lookup failed: $e';
      }
    }
    if (resolvedDst == null) {
      try {
        resolvedDst = await _apiClient.geocodeLatLng(dst);
      } catch (e) {
        geocodeError = geocodeError ?? 'Destination lookup failed: $e';
      }
    }

    if (!mounted) return;

    if (resolvedSrc == null || resolvedDst == null) {
      setState(() {
        _routesLoading = false;
        _routesError = geocodeError ?? 'Could not resolve both locations on map.';
      });
      return;
    }

    setState(() {
      _inputSourceLatLng = resolvedSrc;
      _inputDestLatLng = resolvedDst;
    });

    try {
      await Future.wait([
        _fetchCommunityRoutes(src, dst),
        _fetchBackendInsights(src, dst, start: resolvedSrc, end: resolvedDst),
        _fetchOsmRoute(resolvedSrc, resolvedDst),
      ]);
    } finally {
      if (mounted) {
        setState(() => _routesLoading = false);
      }
    }
  }

  Future<void> _fetchCommunityRoutes(String src, String dst) async {
    try {
      final snap = await _firestore
          .collection('community_reviews')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final matches = snap.docs
          .map((d) => d.data())
          .where((data) {
            final srcLower = src.toLowerCase();
            final dstLower = dst.toLowerCase();
            final location = data['location'];
            final locationLabel = location is Map
                ? [location['label'], location['landmark']]
                    .whereType<String>()
                    .map((e) => e.toLowerCase())
                    .join(' ')
                : '';
            final haystack = [
              data['route'],
              data['tripTitle'],
              locationLabel,
            ].whereType<String>().map((e) => e.toLowerCase()).join(' ');
            return haystack.contains(srcLower) && haystack.contains(dstLower);
          })
          .toList();

      if (matches.isEmpty) {
        setState(() {
          _routes = const [];
        });
        return;
      }

      matches.sort((a, b) {
        final ar = (a['overallRating'] ?? 0).toString();
        final br = (b['overallRating'] ?? 0).toString();
        final ai = double.tryParse(ar) ?? 0;
        final bi = double.tryParse(br) ?? 0;
        return bi.compareTo(ai);
      });

      final best = matches.take(3).toList();

      final suggestions = <_RouteSuggestion>[];
      int label = 65; // 'A'
      for (final d in best) {
        final loc = d['location'] as Map<String, dynamic>?;
        final lat = loc?['lat'];
        final lng = loc?['lng'];
        suggestions.add(
          _RouteSuggestion(
            label: String.fromCharCode(label++),
            title: (d['route'] ?? d['tripTitle'] ?? 'Community route').toString(),
            summary: (d['description'] ?? 'Popular with riders').toString(),
            rating: double.tryParse(d['overallRating']?.toString() ?? ''),
            vehicle: (d['vehicle'] ?? d['vehicleType'] ?? '').toString(),
            tags: (d['tags'] is Map)
                ? (d['tags'] as Map)
                    .values
                    .expand((e) => (e as List).map((x) => x.toString()))
                    .toList()
                : const [],
            point: (lat is num && lng is num) ? LatLng(lat.toDouble(), lng.toDouble()) : null,
          ),
        );
      }

      setState(() {
        _routes = suggestions;
      });
    } catch (e) {
      setState(() {
        _routesError = 'Could not fetch routes: $e';
      });
    }
  }

  Future<void> _fetchBackendInsights(String src, String dst, {LatLng? start, LatLng? end}) async {
    final errors = <String>[];
    ShortestPathResult? shortest;
    TripQueryResult? trip;
    TrafficResult? traffic;
    List<FuelStation> fuel = const [];
    List<LatLng> apiMarkers = const [];

    try {
      shortest = await _apiClient.shortestPath(src, dst);
    } catch (e) {
      errors.add('shortest-path: $e');
    }

    try {
      trip = await _apiClient.queryTrip(src, dst);
      apiMarkers = trip?.markers ?? const [];
    } catch (e) {
      errors.add('query: $e');
    }

    final startCoords = start ?? _inputSourceLatLng ?? _currentLatLng;
    final endCoords = end ?? _inputDestLatLng ?? _currentLatLng;
    if (startCoords != null && endCoords != null) {
      try {
        traffic = await _apiClient.trafficAnalysis(startCoords, endCoords);
      } catch (e) {
        errors.add('traffic: $e');
      }
    }

    if (startCoords != null) {
      try {
        fuel = await _apiClient.fuelStations(startCoords.latitude, startCoords.longitude, radiusKm: 5);
      } catch (e) {
        errors.add('fuel: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _shortestPath = shortest;
      _tripQuery = trip;
      _trafficResult = traffic;
      _fuelStations = fuel;
      _backendMarkers = apiMarkers;
      _backendError = errors.isEmpty ? null : errors.join(' | ');
    });
  }

  Future<void> _fetchOsmRoute(LatLng start, LatLng end) async {
    try {
      final route = await _apiClient.openStreetMapRoute(start, end);
      if (!mounted) return;
      setState(() {
        _osmRoute = route;
        _osmRouteError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _osmRouteError = 'Route failed: $e';
      });
    }
  }

  LatLng? _parseLatLng(String text) {
    final parts = text.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  List<Map<String, String>> _buildMockForecast() {
    final now = DateTime.now();
    final hours = List.generate(6, (i) => now.add(Duration(hours: i + 1)));
    return hours
        .map((dt) => {
              'time': '${dt.hour.toString().padLeft(2, '0')}:00',
              'temp': (22 + (dt.hour % 3) * 2).toString(),
              'note': 'Clear to partly cloudy',
            })
        .toList();
  }

  List<String> _tripTipsForVehicle() {
    final v = _preferredVehicle?.toLowerCase() ?? '';
    final tips = <String>[];
    if (v.contains('bike') || v.contains('motor') || v.contains('duke') || v.contains('pulsar')) {
      tips.addAll([
        'Check chain tension and lube before starting.',
        'Carry rain gear and a compact tool kit for roadside fixes.',
        'Prefer routes with fuel stops every 80-100 km.',
      ]);
    } else {
      tips.addAll([
        'Verify tire pressure and coolant levels.',
        'Keep a power bank and offline maps downloaded.',
        'Plan hydration stops every 60-90 minutes.',
      ]);
    }
    if (_routes.isNotEmpty && _routes.first.tags.isNotEmpty) {
      tips.add('Community tags: ${_routes.first.tags.take(4).join(', ')}');
    }
    return tips;
  }
}

class _RouteSuggestion {
  const _RouteSuggestion({
    required this.label,
    required this.title,
    required this.summary,
    this.rating,
    this.vehicle,
    this.tags = const [],
    this.point,
  });

  final String label;
  final String title;
  final String summary;
  final double? rating;
  final String? vehicle;
  final List<String> tags;
  final LatLng? point;
}
