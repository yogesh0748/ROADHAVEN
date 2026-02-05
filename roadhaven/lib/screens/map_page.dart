import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:roadhaven/services/roadhaven_api.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _sourceCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _apiClient = RoadHavenApiClient();
  final _mapController = MapController();

  Future<Position?>? _positionFuture;
  LatLng? _start;
  LatLng? _end;
  List<OsmRoute> _routes = const [];
  int _selectedRouteIndex = 0;
  bool _loading = false;
  String? _error;

  static const _fallbackCenter = LatLng(20.5937, 78.9629); // India approx

  @override
  void initState() {
    super.initState();
    _positionFuture = _determinePosition();
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  Future<Position?> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchRoute() async {
    final src = _sourceCtrl.text.trim();
    final dst = _destCtrl.text.trim();
    if (src.isEmpty || dst.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both source and destination')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _routes = const [];
      _selectedRouteIndex = 0;
    });

    LatLng? start = _parseLatLng(src);
    LatLng? end = _parseLatLng(dst);
    String? geocodeError;

    if (start == null) {
      try {
        start = await _apiClient.geocodeLatLng(src);
      } catch (e) {
        geocodeError = 'Source lookup failed: $e';
      }
    }
    if (end == null) {
      try {
        end = await _apiClient.geocodeLatLng(dst);
      } catch (e) {
        geocodeError = geocodeError ?? 'Destination lookup failed: $e';
      }
    }

    if (!mounted) return;

    if (start == null || end == null) {
      setState(() {
        _loading = false;
        _error = geocodeError ?? 'Could not resolve both locations.';
      });
      return;
    }

    try {
      final routes = await _apiClient.openStreetMapRoutes(start, end, alternatives: 3);
      if (!mounted) return;
      setState(() {
        _start = start;
        _end = end;
        _routes = routes;
        _selectedRouteIndex = 0;
        _error = null;
      });
      _mapController.move(start, 12);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Routing failed: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Map & Routes')),
      body: SafeArea(
        child: FutureBuilder<Position?>(
          future: _positionFuture,
          builder: (context, snapshot) {
            final userPos = snapshot.data;
            final center = _start ??
                _end ??
                (userPos != null ? LatLng(userPos.latitude, userPos.longitude) : _fallbackCenter);

            final markers = <Marker>[];
            if (_start != null) {
              markers.add(
                Marker(
                  point: _start!,
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.radio_button_checked, color: Colors.green, size: 24),
                ),
              );
            }
            if (_end != null) {
              markers.add(
                Marker(
                  point: _end!,
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 26),
                ),
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 12,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              minZoom: 2,
                              maxZoom: 19,
                              userAgentPackageName: 'com.roadhaven.app',
                              tileBuilder: (context, widget, tile) => DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: colorScheme.outlineVariant.withOpacity(0.15),
                                    width: 0.3,
                                  ),
                                ),
                                child: widget,
                              ),
                              // userAgentPackageName left out on web to avoid tile blocking
                            ),
                            if (markers.isNotEmpty) MarkerLayer(markers: markers),
                            if (_routes.isNotEmpty)
                              PolylineLayer(
                                polylines: List.generate(_routes.length, (i) {
                                  final r = _routes[i];
                                  final selected = i == _selectedRouteIndex;
                                  final baseColor = selected
                                      ? colorScheme.primary
                                      : colorScheme.primary.withOpacity(0.45);
                                  return Polyline(
                                    points: r.points,
                                    color: baseColor,
                                    strokeWidth: selected ? 6 : 4,
                                  );
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _TopCard(
                    sourceCtrl: _sourceCtrl,
                    destCtrl: _destCtrl,
                    loading: _loading,
                    error: _error,
                    onSubmit: _fetchRoute,
                    routes: _routes,
                    selectedRouteIndex: _selectedRouteIndex,
                    onSelectRoute: (i) {
                      setState(() => _selectedRouteIndex = i);
                      final points = _routes[i].points;
                      if (points.isNotEmpty) {
                        _mapController.move(points.first, 12);
                      }
                    },
                  ),
                ),

                Positioned(
                  top: 12,
                  right: 16,
                  child: _CircleOverlayButton(
                    icon: Icons.fullscreen,
                    tooltip: 'Full screen map',
                    onTap: () {
                      final center = _start ??
                          _end ??
                          (userPos != null
                              ? LatLng(userPos.latitude, userPos.longitude)
                              : _fallbackCenter);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _FullScreenMap(
                            start: _start,
                            end: _end,
                            routes: _routes,
                            selectedRouteIndex: _selectedRouteIndex,
                            center: center,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                if (_routes.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _RouteSummaryCard(
                      route: _routes[_selectedRouteIndex],
                      index: _selectedRouteIndex,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                  ),

                Positioned(
                  right: 24,
                  bottom: _routes.isNotEmpty ? 140 : 24,
                  child: _RecenterButtons(
                    onToStart: _start != null ? () => _mapController.move(_start!, 13) : null,
                    onToEnd: _end != null ? () => _mapController.move(_end!, 13) : null,
                    onToUser: userPos != null
                        ? () => _mapController.move(LatLng(userPos.latitude, userPos.longitude), 13)
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  LatLng? _parseLatLng(String text) {
    final parts = text.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.sourceCtrl,
    required this.destCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.routes,
    required this.selectedRouteIndex,
    required this.onSelectRoute,
  });

  final TextEditingController sourceCtrl;
  final TextEditingController destCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;
  final List<OsmRoute> routes;
  final int selectedRouteIndex;
  final ValueChanged<int> onSelectRoute;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Plan your drive',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sourceCtrl,
              decoration: const InputDecoration(
                labelText: 'Source (address or lat,lng)',
                prefixIcon: Icon(Icons.radio_button_checked, color: Colors.green),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: destCtrl,
              decoration: const InputDecoration(
                labelText: 'Destination (address or lat,lng)',
                prefixIcon: Icon(Icons.location_pin, color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.alt_route),
                label: const Text('Show route on map'),
                onPressed: loading ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                ),
              ),
            if (routes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Routes (${routes.length})',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  children: List.generate(routes.length, (i) {
                    final r = routes[i];
                    final selected = i == selectedRouteIndex;
                    final label = String.fromCharCode(65 + i);
                    final subtitle = [
                      if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(1)} km',
                      if (r.durationMinutes != null) '${r.durationMinutes!.toStringAsFixed(0)} min',
                    ].where((e) => e.isNotEmpty).join(' • ');
                    return ChoiceChip(
                      label: Text('$label  $subtitle'),
                      selected: selected,
                      showCheckmark: false,
                      onSelected: (_) => onSelectRoute(i),
                    );
                  }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({
    required this.route,
    required this.index,
    required this.colorScheme,
    required this.textTheme,
  });

  final OsmRoute route;
  final int index;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final label = String.fromCharCode(65 + index);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primary.withOpacity(0.15),
              child: Text(
                label,
                style: textTheme.titleMedium?.copyWith(color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Primary route',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buildMeta(route),
                    style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  if (route.summary?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      route.summary!,
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    route.distanceKm != null
                        ? '${route.distanceKm!.toStringAsFixed(1)} km'
                        : '-- km',
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    route.durationMinutes != null
                        ? '${route.durationMinutes!.toStringAsFixed(0)} min'
                        : '-- min',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildMeta(OsmRoute r) {
    final parts = <String>[];
    if (r.distanceKm != null) parts.add('${r.distanceKm!.toStringAsFixed(1)} km');
    if (r.durationMinutes != null) parts.add('${r.durationMinutes!.toStringAsFixed(0)} min');
    return parts.isEmpty ? 'Route ready' : parts.join(' • ');
  }
}

class _RecenterButtons extends StatelessWidget {
  const _RecenterButtons({
    this.onToStart,
    this.onToEnd,
    this.onToUser,
  });

  final VoidCallback? onToStart;
  final VoidCallback? onToEnd;
  final VoidCallback? onToUser;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToStart != null)
          _circleButton(
            icon: Icons.radio_button_checked,
            color: Colors.green,
            onTap: onToStart!,
            colorScheme: colorScheme,
          ),
        if (onToUser != null) ...[
          const SizedBox(height: 8),
          _circleButton(
            icon: Icons.my_location,
            color: colorScheme.primary,
            onTap: onToUser!,
            colorScheme: colorScheme,
          ),
        ],
        if (onToEnd != null) ...[
          const SizedBox(height: 8),
          _circleButton(
            icon: Icons.location_pin,
            color: Colors.redAccent,
            onTap: onToEnd!,
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Material(
      color: colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _CircleOverlayButton extends StatelessWidget {
  const _CircleOverlayButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Tooltip(
            message: tooltip ?? '',
            child: Icon(icon, size: 22, color: colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _FullScreenMap extends StatelessWidget {
  const _FullScreenMap({
    required this.start,
    required this.end,
    required this.routes,
    required this.selectedRouteIndex,
    required this.center,
  });

  final LatLng? start;
  final LatLng? end;
  final List<OsmRoute> routes;
  final int selectedRouteIndex;
  final LatLng center;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mapController = MapController();

    final markers = <Marker>[];
    if (start != null) {
      markers.add(
        Marker(
          point: start!,
          width: 30,
          height: 30,
          child: const Icon(Icons.radio_button_checked, color: Colors.green, size: 24),
        ),
      );
    }
    if (end != null) {
      markers.add(
        Marker(
          point: end!,
          width: 30,
          height: 30,
          child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 26),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Full Screen Map')),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 13,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            minZoom: 2,
            maxZoom: 19,
            userAgentPackageName: 'com.roadhaven.app',
          ),
          if (markers.isNotEmpty) MarkerLayer(markers: markers),
          if (routes.isNotEmpty)
            PolylineLayer(
              polylines: List.generate(routes.length, (i) {
                final r = routes[i];
                final selected = i == selectedRouteIndex;
                final baseColor = selected
                    ? colorScheme.primary
                    : colorScheme.primary.withOpacity(0.45);
                return Polyline(
                  points: r.points,
                  color: baseColor,
                  strokeWidth: selected ? 6 : 4,
                );
              }),
            ),
        ],
      ),
    );
  }
}
