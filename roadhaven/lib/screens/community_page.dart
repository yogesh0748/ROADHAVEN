import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _routeCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  DateTime _travelDate = DateTime.now();
  String _vehicleType = 'Car';
  final _vehicleTypes = ['Car', 'Bike', 'Truck', 'Bus'];
  int _overallRating = 3;
  int _roadQualityRating = 3;
  int _trafficRating = 3;
  int _safetyRating = 3;
  final _tagOptions = <String, List<String>>{
    'Road': ['Smooth', 'Pothole', 'Construction', 'Excellent', 'Poor'],
    'Traffic': ['Light', 'Heavy', 'Jam', 'Fast-moving', 'Slow'],
    'Fuel': ['Available', 'Expensive', 'Cheap', 'Queue', 'Shortage'],
    'Weather': ['Clear', 'Rain', 'Fog', 'Storm', 'Perfect'],
    'Amenities': ['Good Food', 'Clean Restrooms', 'Parking', 'ATM', 'Mechanic'],
  };
  final _selectedTags = <String, Set<String>>{};
  bool _hasFuelStations = false;
  bool _hasGoodFood = false;
  bool _hasCleanRestrooms = false;
  bool _safeAtNight = false;
  bool _goodNetwork = false;
  bool _policeCheckpost = false;
  late final AnimationController _heroController;
  late final Animation<double> _heroTilt;
  Position? _position;
  String? _positionText;
  bool _locating = false;
  bool _posting = false;
  bool _loadingVehicles = false;
  String? _selectedVehicle;
  List<String> _vehicles = [];
  final _picker = ImagePicker();
  final List<XFile> _pickedPhotos = [];
  List<String> _photoUrls = [];
  bool _uploadingPhotos = false;
  bool _markEmergency = false;
  final _alertTypes = ['Accident', 'Breakdown', 'Road Block', 'Weather'];
  String _alertType = 'Accident';
  final _urgencies = ['Low', 'Medium', 'High', 'Critical'];
  String _urgency = 'Low';
  final _shareOptions = ['Public', 'Community Only', 'Anonymous'];
  String _shareAs = 'Public';
  bool _allowContact = true;
  String? _voiceNoteUrl;
  final _routePresets = <String>[
    'From City to City',
    'From Office to Home',
    'From Airport to Downtown',
    'From Station to Hotel',
    'From Campus to City Center',
  ];
  String? _editingDocId;

  Query<Map<String, dynamic>> get _allPostsQuery => FirebaseFirestore.instance
      .collection('community_reviews')
      .orderBy('createdAt', descending: true);

  Query<Map<String, dynamic>> get _myPostsQuery {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance
        .collection('community_reviews')
      .where('userId', isEqualTo: uid);
  }

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _heroTilt = Tween<double>(begin: -0.09, end: 0.09)
        .animate(CurvedAnimation(parent: _heroController, curve: Curves.easeInOutSine));
    for (final entry in _tagOptions.entries) {
      _selectedTags[entry.key] = <String>{};
    }
    _loadVehicles();
  }

  @override
  void dispose() {
    _heroController.dispose();
    _routeCtrl.dispose();
    _descriptionCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loadingVehicles = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(uid)
          .collection('vehicles')
          .get();
      final items = snap.docs
          .map((d) {
            final data = d.data();
            final make = (data['make'] ?? '').toString();
            final model = (data['model'] ?? '').toString();
            final plate = (data['plate'] ?? '').toString();
            return [make, model, plate]
                .where((p) => p.trim().isNotEmpty)
                .join(' • ');
          })
          .where((s) => s.trim().isNotEmpty)
          .toList();
      setState(() {
        _vehicles = items;
        if (_vehicles.isNotEmpty && _selectedVehicle == null) {
          _selectedVehicle = _vehicles.first;
        }
      });
    } catch (e) {
      debugPrint('Failed to load vehicles: $e');
    } finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  void _resetSelections() {
    for (final key in _selectedTags.keys) {
      _selectedTags[key]?.clear();
    }
    _hasFuelStations = false;
    _hasGoodFood = false;
    _hasCleanRestrooms = false;
    _safeAtNight = false;
    _goodNetwork = false;
    _policeCheckpost = false;
  }

  String _formatDate(DateTime date) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = names[date.weekday - 1];
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$weekday, $day-$month-${date.year}';
  }

  Future<void> _selectTravelDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _travelDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      setState(() => _travelDate = picked);
    }
  }

  Future<void> _detectLocation() async {
    setState(() {
      _locating = true;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() {
        _position = pos;
        _positionText = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location unavailable: $e')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickPhotos() async {
    final remaining = 3 - (_pickedPhotos.length + _photoUrls.length);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo limit reached (max 3).')),
      );
      return;
    }
    try {
      final files = await _picker.pickMultiImage(imageQuality: 75);
      if (files.isNotEmpty) {
        setState(() {
          _pickedPhotos.addAll(files.take(remaining));
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to pick photos: $e')),
      );
    }
  }

  Future<List<String>> _uploadPhotos(String uid) async {
    if (_pickedPhotos.isEmpty) return [..._photoUrls];
    setState(() => _uploadingPhotos = true);
    final urls = [..._photoUrls];
    try {
      for (final photo in _pickedPhotos) {
        final file = File(photo.path);
        final name = '${DateTime.now().millisecondsSinceEpoch}-${photo.name}';
        final ref = FirebaseStorage.instance
            .ref()
            .child('community_uploads')
            .child(uid)
            .child(name);
        await ref.putFile(file);
        final url = await ref.getDownloadURL();
        urls.add(url);
      }
      return urls;
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhotos = false;
          _pickedPhotos.clear();
          _photoUrls = urls;
        });
      }
    }
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildRouteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Route: From [City] to [City]', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Autocomplete<String>(
          optionsBuilder: (text) {
            final query = text.text.toLowerCase();
            return _routePresets.where((r) => r.toLowerCase().contains(query));
          },
          onSelected: (val) => _routeCtrl.text = val,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: _routeCtrl,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Route',
                hintText: 'From Jaipur to Delhi',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter route' : null,
              onFieldSubmitted: (_) => onFieldSubmitted(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDateVehicleRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _selectTravelDate(context),
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text('Travel: ${_formatDate(_travelDate)}'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _vehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle type'),
            items: _vehicleTypes
                .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                .toList(),
            onChanged: (val) => setState(() => _vehicleType = val ?? _vehicleType),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Experience rating', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            _buildStarSelector('Overall experience', _overallRating, (v) => setState(() => _overallRating = v)),
            _buildStarSelector('Road quality', _roadQualityRating, (v) => setState(() => _roadQualityRating = v)),
            _buildStarSelector('Traffic', _trafficRating, (v) => setState(() => _trafficRating = v)),
            _buildStarSelector('Safety', _safetyRating, (v) => setState(() => _safetyRating = v)),
          ],
        ),
      ),
    );
  }

  Widget _buildStarSelector(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Wrap(
            spacing: 2,
            children: List.generate(5, (index) {
              final active = index < value;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _posting ? null : () => onChanged(index + 1),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    active ? Icons.star : Icons.star_border,
                    color: active ? Colors.orange : Colors.grey,
                    size: 26,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick tags', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8),
        ..._tagOptions.entries.map((entry) => _buildTagWrap(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildTagWrap(String category, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: options.map((opt) {
              final selected = _selectedTags[category]?.contains(opt) == true;
              return ChoiceChip(
                label: Text(opt),
                selected: selected,
                onSelected: _posting
                    ? null
                    : (_) {
                        setState(() {
                          if (selected) {
                            _selectedTags[category]?.remove(opt);
                          } else {
                            _selectedTags[category]?.add(opt);
                          }
                        });
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    final locationLabel = _positionText ?? 'Tap to auto-fill current location';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _detectLocation,
                icon: _locating
                    ? const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(locationLabel, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _landmarkCtrl,
                decoration: const InputDecoration(labelText: 'Landmark (optional)'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHelpfulDetails() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Helpful details', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ...[
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _hasFuelStations,
                onChanged: (v) => setState(() => _hasFuelStations = v ?? false),
                title: const Text('Fuel stations available'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _hasGoodFood,
                onChanged: (v) => setState(() => _hasGoodFood = v ?? false),
                title: const Text('Good food options'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _hasCleanRestrooms,
                onChanged: (v) => setState(() => _hasCleanRestrooms = v ?? false),
                title: const Text('Clean restrooms'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _safeAtNight,
                onChanged: (v) => setState(() => _safeAtNight = v ?? false),
                title: const Text('Safe for night travel'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _goodNetwork,
                onChanged: (v) => setState(() => _goodNetwork = v ?? false),
                title: const Text('Mobile network good'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _policeCheckpost,
                onChanged: (v) => setState(() => _policeCheckpost = v ?? false),
                title: const Text('Police checkpost present'),
              ),
            ].map((tile) => Theme(
                  data: Theme.of(context).copyWith(unselectedWidgetColor: Colors.white70),
                  child: tile,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildUploads() {
    final totalPhotos = _photoUrls.length + _pickedPhotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Uploads (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ElevatedButton.icon(
              onPressed: _uploadingPhotos || _posting ? null : _pickPhotos,
              icon: const Icon(Icons.photo_library),
              label: Text('Add photos ($totalPhotos/3)'),
            ),
            ElevatedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice note capture coming soon.')),
              ),
              icon: const Icon(Icons.mic),
              label: const Text('Record 30-sec voice note'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (totalPhotos > 0)
          Wrap(
            spacing: 6,
            children: [
              ..._photoUrls.map((url) => Chip(label: Text('Uploaded photo'))),
              ..._pickedPhotos.map((file) => Chip(label: Text(file.name))),
            ],
          ),
      ],
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF050505), Color(0xFF0C1A2F)],
            ),
          ),
        ),
        Positioned(
          left: -140,
          top: 100,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Colors.blue.withOpacity(0.22), Colors.transparent],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x332D6BFF), blurRadius: 120, spreadRadius: 18),
              ],
            ),
          ),
        ),
        Positioned(
          right: -120,
          bottom: 60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Colors.purple.withOpacity(0.18), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBanner() {
    return AnimatedBuilder(
      animation: _heroController,
      builder: (context, child) {
        final tilt = _heroTilt.value;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(tilt)
            ..rotateY(-tilt * 0.6),
          child: child,
        );
      },
      child: _glassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Roadhaven Community',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.2,
                        )),
                    SizedBox(height: 6),
                    Text(
                      'Share live ride stories, safety tips, and hidden stops. Your ratings power the map.',
                      style: TextStyle(color: Color(0xFFCED8EE), height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildRoadTile(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoadTile() {
    return Transform.translate(
      offset: const Offset(0, -4),
      child: Container(
        width: 140,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2233), Color(0xFF0F1320)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: const [
            BoxShadow(color: Color(0x442D6BFF), blurRadius: 24, offset: Offset(0, 14)),
          ],
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  6,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      width: 22,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 32,
              child: Transform.rotate(
                angle: -0.15,
                child: const Icon(Icons.local_shipping, color: Color(0xFF7FB7FF), size: 22),
              ),
            ),
            Positioned(
              top: 16,
              right: 24,
              child: Transform.rotate(
                angle: 0.12,
                child: const Icon(Icons.directions_car, color: Color(0xFFFBC02D), size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencySection() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mark as emergency / alert'),
              value: _markEmergency,
              onChanged: (v) => setState(() => _markEmergency = v),
            ),
            if (_markEmergency) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _alertType,
                      decoration: const InputDecoration(labelText: 'Alert type'),
                      items: _alertTypes
                          .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _alertType = v ?? _alertType),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _urgency,
                      decoration: const InputDecoration(labelText: 'Urgency'),
                      items: _urgencies
                          .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _urgency = v ?? _urgency),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySection() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Privacy settings', style: TextStyle(fontWeight: FontWeight.w700)),
            DropdownButtonFormField<String>(
              initialValue: _shareAs,
              decoration: const InputDecoration(labelText: 'Share as'),
              items: _shareOptions
                  .map((opt) => DropdownMenuItem<String>(value: opt, child: Text(opt)))
                  .toList(),
              onChanged: (v) => setState(() => _shareAs = v ?? _shareAs),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow contact from other travelers'),
              value: _allowContact,
              onChanged: (v) => setState(() => _allowContact = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingDisplayRow(String label, int value) {
    if (value <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
          Wrap(
            spacing: 2,
            children: List.generate(5, (index) {
              final active = index < value;
              return Icon(active ? Icons.star : Icons.star_border, size: 16, color: active ? Colors.orange : Colors.grey);
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReview(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to be signed in to post.')),
      );
      return;
    }
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _posting = true);
    try {
      final photoUrls = await _uploadPhotos(user.uid);
      final payload = {
        'tripTitle': _routeCtrl.text.trim(),
        'route': _routeCtrl.text.trim(),
        'travelDate': Timestamp.fromDate(_travelDate),
        'vehicleType': _vehicleType,
        'vehicle': _selectedVehicle ?? _vehicleType,
        'overallRating': _overallRating,
        'roadQualityRating': _roadQualityRating,
        'trafficRating': _trafficRating,
        'safetyRating': _safetyRating,
        'tags': _selectedTags.map((k, v) => MapEntry(k, v.toList())),
        'description': _descriptionCtrl.text.trim(),
        'location': {
          'lat': _position?.latitude,
          'lng': _position?.longitude,
          'label': _positionText,
          'landmark': _landmarkCtrl.text.trim(),
        },
        'helpful': {
          'fuelStations': _hasFuelStations,
          'goodFood': _hasGoodFood,
          'cleanRestrooms': _hasCleanRestrooms,
          'safeAtNight': _safeAtNight,
          'goodNetwork': _goodNetwork,
          'policeCheckpost': _policeCheckpost,
        },
        'markEmergency': _markEmergency,
        'alertType': _markEmergency ? _alertType : null,
        'urgency': _markEmergency ? _urgency : null,
        'shareAs': _shareAs,
        'allowContact': _allowContact,
        'photoUrls': photoUrls,
        'voiceNoteUrl': _voiceNoteUrl,
        'userId': user.uid,
        'userEmail': user.email,
      };

      if (_editingDocId != null) {
        await FirebaseFirestore.instance
            .collection('community_reviews')
            .doc(_editingDocId)
            .set({
          ...payload,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance.collection('community_reviews').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (!mounted) return;
      final wasEditing = _editingDocId != null;
      Navigator.pop(context);
      _routeCtrl.clear();
      _descriptionCtrl.clear();
      _landmarkCtrl.clear();
      _pickedPhotos.clear();
      _photoUrls.clear();
      _resetSelections();
      _editingDocId = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEditing ? 'Review updated.' : 'Review posted for the community.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _openComposer({String? docId, Map<String, dynamic>? initialData}) async {
    // Ensure controls are interactive when composer opens
    if (_posting) {
      setState(() => _posting = false);
    }
    _pickedPhotos.clear();
    _photoUrls = [];
    _voiceNoteUrl = null;
    if (docId == null) {
      _editingDocId = null;
      _routeCtrl.clear();
      _descriptionCtrl.clear();
      _landmarkCtrl.clear();
      _travelDate = DateTime.now();
      _vehicleType = _vehicleTypes.first;
      _selectedVehicle = _vehicles.isNotEmpty ? _vehicles.first : _vehicleType;
      _overallRating = 3;
      _roadQualityRating = 3;
      _trafficRating = 3;
      _safetyRating = 3;
      _markEmergency = false;
      _alertType = _alertTypes.first;
      _urgency = _urgencies.first;
      _shareAs = _shareOptions.first;
      _allowContact = true;
      _position = null;
      _positionText = null;
      _resetSelections();
    } else {
      _editingDocId = docId;
      _routeCtrl.text = (initialData?['route'] ?? initialData?['tripTitle'] ?? '').toString();
      final ts = initialData?['travelDate'];
      if (ts is Timestamp) {
        _travelDate = ts.toDate();
      } else {
        _travelDate = DateTime.now();
      }
      _vehicleType = (initialData?['vehicleType'] ?? _vehicleTypes.first).toString();
      _selectedVehicle = (initialData?['vehicle'] ?? _vehicleType).toString();
      _overallRating = (initialData?['overallRating'] as num?)?.round() ?? 3;
      _roadQualityRating = (initialData?['roadQualityRating'] as num?)?.round() ?? 3;
      _trafficRating = (initialData?['trafficRating'] as num?)?.round() ?? 3;
      _safetyRating = (initialData?['safetyRating'] as num?)?.round() ?? 3;
      _descriptionCtrl.text = (initialData?['description'] ?? initialData?['issues'] ?? '').toString();
      final tags = initialData?['tags'];
      _resetSelections();
      if (tags is Map) {
        for (final entry in tags.entries) {
          final value = entry.value;
          if (value is List) {
            _selectedTags[entry.key]?.addAll(value.map((e) => e.toString()));
          }
        }
      }
      final location = initialData?['location'];
      if (location is Map<String, dynamic>) {
        final lat = location['lat'] as num?;
        final lng = location['lng'] as num?;
        if (lat != null && lng != null) {
          _positionText = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        }
        _landmarkCtrl.text = (location['landmark'] ?? '').toString();
      }
      final helpful = initialData?['helpful'];
      if (helpful is Map<String, dynamic>) {
        _hasFuelStations = helpful['fuelStations'] == true;
        _hasGoodFood = helpful['goodFood'] == true;
        _hasCleanRestrooms = helpful['cleanRestrooms'] == true;
        _safeAtNight = helpful['safeAtNight'] == true;
        _goodNetwork = helpful['goodNetwork'] == true;
        _policeCheckpost = helpful['policeCheckpost'] == true;
      }
      _markEmergency = initialData?['markEmergency'] == true;
      _alertType = (initialData?['alertType'] ?? _alertTypes.first).toString();
      _urgency = (initialData?['urgency'] ?? _urgencies.first).toString();
      _shareAs = (initialData?['shareAs'] ?? _shareOptions.first).toString();
      _allowContact = initialData?['allowContact'] != false;
      final storedPhotos = initialData?['photoUrls'];
      if (storedPhotos is List) {
        _photoUrls = storedPhotos.map((e) => e.toString()).toList();
      }
      _voiceNoteUrl = (initialData?['voiceNoteUrl'] ?? '') as String?;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _editingDocId == null ? 'Share trip review' : 'Edit your review',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _editingDocId = null;
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRouteField(),
                const SizedBox(height: 12),
                _buildDateVehicleRow(),
                const SizedBox(height: 12),
                if (_loadingVehicles)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_vehicles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedVehicle,
                    decoration: const InputDecoration(labelText: 'Saved vehicle (optional)'),
                    items: _vehicles
                        .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedVehicle = val ?? _vehicleType),
                  ),
                const SizedBox(height: 12),
                _buildRatingCard(),
                const SizedBox(height: 12),
                _buildTagsSection(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionCtrl,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Share your experience (optional)',
                    hintText:
                        'Share your experience... e.g., "Great scenic views but heavy traffic near toll plaza"',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                _buildLocationSection(),
                const SizedBox(height: 12),
                _buildHelpfulDetails(),
                const SizedBox(height: 12),
                _buildUploads(),
                const SizedBox(height: 12),
                _buildEmergencySection(),
                const SizedBox(height: 12),
                _buildPrivacySection(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _posting ? null : () => _submitReview(ctx),
                    child: _posting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_editingDocId == null ? 'Post review' : 'Save changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _editingDocId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Stack(
        children: [
          _buildBackground(),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('Community', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload vehicles',
                  onPressed: _loadVehicles,
                ),
              ],
              bottom: const TabBar(
                labelColor: Colors.white,
                indicatorColor: Color(0xFF4D8DFF),
                tabs: [
                  Tab(text: 'All posts'),
                  Tab(text: 'My posts'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF1F2633),
              onPressed: _posting ? null : _openComposer,
              icon: const Icon(Icons.post_add),
              label: const Text('Post review'),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _buildHeroBanner(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Latest posts from riders',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _posting ? null : () => _openComposer(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF242A35),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.add_comment),
                          label: const Text('Post'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPostsList(stream: _allPostsQuery.snapshots()),
                        _buildPostsList(
                          stream: _myPostsQuery.snapshots(),
                          emptyLabel: 'You have not posted yet.',
                          sortCreatedAtDesc: true,
                        ),
                      ],
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

  Widget _buildPostsList({
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    String? emptyLabel,
    bool sortCreatedAtDesc = false,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final err = snapshot.error;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'Failed to load reviews',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loadVehicles,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final rawDocs = snapshot.data?.docs ?? [];
        if (rawDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emptyLabel ?? 'No reviews yet. Share your first trip!'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _posting ? null : () => _openComposer(),
                  icon: const Icon(Icons.post_add),
                  label: const Text('Post review'),
                ),
              ],
            ),
          );
        }

        final docs = [...rawDocs];
        if (sortCreatedAtDesc) {
          docs.sort((a, b) {
            final ta = (a.data()['createdAt'] as Timestamp?)?.toDate();
            final tb = (b.data()['createdAt'] as Timestamp?)?.toDate();
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
            final header = data['route'] as String? ?? data['tripTitle'] as String? ?? 'Trip';
            final travelDate = (data['travelDate'] as Timestamp?)?.toDate();
            final vehicleType = data['vehicleType'] as String? ?? data['vehicle'] as String? ?? 'Vehicle';
            final tags = <String>[];
            final tagsMap = data['tags'];
            if (tagsMap is Map) {
              for (final entry in tagsMap.entries) {
                final value = entry.value;
                if (value is List) {
                  tags.addAll(value.map((e) => '${entry.key}: ${e.toString()}'));
                }
              }
            }
            final helpfulMap = data['helpful'];
            final helpfulTags = <String>[];
            if (helpfulMap is Map<String, dynamic>) {
              if (helpfulMap['fuelStations'] == true) helpfulTags.add('Fuel stations');
              if (helpfulMap['goodFood'] == true) helpfulTags.add('Good food');
              if (helpfulMap['cleanRestrooms'] == true) helpfulTags.add('Clean restrooms');
              if (helpfulMap['safeAtNight'] == true) helpfulTags.add('Safe at night');
              if (helpfulMap['goodNetwork'] == true) helpfulTags.add('Good network');
              if (helpfulMap['policeCheckpost'] == true) helpfulTags.add('Police checkpost');
            }
            final description = data['description'] as String? ?? '';
            final location = data['location'];
            String? locationLabel;
            if (location is Map<String, dynamic>) {
              final label = location['label'] ?? location['landmark'];
              if (label != null && label.toString().trim().isNotEmpty) {
                locationLabel = label.toString();
              }
            }
            final overall = (data['overallRating'] as num?)?.round() ?? 0;
            final road = (data['roadQualityRating'] as num?)?.round() ?? 0;
            final traffic = (data['trafficRating'] as num?)?.round() ?? 0;
            final safety = (data['safetyRating'] as num?)?.round() ?? 0;
            final isEmergency = data['markEmergency'] == true;
            final alertType = data['alertType'] as String?;
            final urgency = data['urgency'] as String?;
            final shareAs = data['shareAs'] as String? ?? 'Public';
            final photos = (data['photoUrls'] as List?)?.length ?? 0;
            final author = data['userEmail'] as String? ?? 'Anonymous rider';
            final isOwner =
                (data['userId'] != null) && data['userId'] == FirebaseAuth.instance.currentUser?.uid;

            return _glassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            header,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                          ),
                        ),
                        if (isOwner)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Colors.white70),
                                tooltip: 'Edit your post',
                                onPressed: () => _openComposer(
                                  docId: docs[index].id,
                                  initialData: data,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white70),
                                tooltip: 'Delete your post',
                                onPressed: () => _confirmDelete(docs[index].id),
                              ),
                            ],
                          ),
                        if (createdAt != null)
                          Text(
                            '${createdAt.toLocal()}'.split('.').first,
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(label: Text(vehicleType)),
                        if (travelDate != null) Chip(label: Text(_formatDate(travelDate))),
                        Chip(label: Text('Share: $shareAs')),
                        if (isEmergency)
                          Chip(
                            avatar: const Icon(Icons.warning, color: Colors.red, size: 16),
                            label: Text('${alertType ?? 'Emergency'} • ${urgency ?? 'Medium'}'),
                          ),
                        if (locationLabel != null && locationLabel.isNotEmpty)
                          Chip(label: Text(locationLabel)),
                        if (photos > 0) Chip(label: Text('$photos photo(s)')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ratingDisplayRow('Overall', overall),
                    _ratingDisplayRow('Road', road),
                    _ratingDisplayRow('Traffic', traffic),
                    _ratingDisplayRow('Safety', safety),
                    const SizedBox(height: 8),
                    if (tags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tags.map((t) => Chip(label: Text(t))).toList(),
                      ),
                    if (helpfulTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: helpfulTags.map((t) => Chip(label: Text(t))).toList(),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(description, style: const TextStyle(color: Colors.white70)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: Colors.white60),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            author,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(String docId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (shouldDelete != true) return;
    try {
      await FirebaseFirestore.instance.collection('community_reviews').doc(docId).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }
}
