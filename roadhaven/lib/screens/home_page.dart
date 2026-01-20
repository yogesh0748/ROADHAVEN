import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:roadhaven/services/auth_service.dart';

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
  List<Map<String, String>> _routes = const [];

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
                color: colorScheme.surfaceVariant,
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
                      onPressed: _buildSuggestions,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_routes.isNotEmpty) ...[
                    Text(
                      'Suggested routes from community:',
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _routes
                          .map((r) => Chip(label: Text('${r['label']}: ${r['summary']}')))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 200,
                        color: colorScheme.surfaceVariant,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tap to highlight route'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: _routes
                                  .map((r) => OutlinedButton(
                                        onPressed: () {},
                                        child: Text('Route ${r['label']}'),
                                      ))
                                  .toList(),
                            ),
                            const Spacer(),
                            const Center(child: Icon(Icons.map, size: 48)),
                            const SizedBox(height: 8),
                            Text('Preview of routes A/B/C on map'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _buildSuggestions() {
    final src = _sourceCtrl.text.trim();
    final dst = _destCtrl.text.trim();
    if (src.isEmpty || dst.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both source and destination')),
      );
      return;
    }
    // Placeholder: in a real app, query community_reviews for bestPaths containing these areas.
    setState(() {
      _routes = [
        {
          'label': 'A',
          'summary': 'Fastest via highway (community pick)',
        },
        {
          'label': 'B',
          'summary': 'Scenic route with fewer tolls',
        },
        {
          'label': 'C',
          'summary': 'Fuel-efficient path with fewer stops',
        },
      ];
    });
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
}
