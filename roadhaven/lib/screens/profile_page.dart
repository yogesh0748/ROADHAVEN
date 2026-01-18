import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameCtrl = TextEditingController();
  final _avgCtrl = TextEditingController();
  final _photoUrlCtrl = TextEditingController();
  List<Map<String, dynamic>> _vehicles = [];
  bool _saving = false;
  bool _uploading = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _photoUrlCtrl.text = _user?.photoURL ?? '';
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _avgCtrl.dispose();
    _photoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('profiles').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _nameCtrl.text = data['name'] ?? '';
        _avgCtrl.text = (data['average'] ?? '').toString();
        _photoUrlCtrl.text = data['photoUrl'] ?? _photoUrlCtrl.text;
      }
      final vehiclesSnap = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(uid)
          .collection('vehicles')
          .get();
      _vehicles = vehiclesSnap.docs
          .map((d) => {
                'make': d.data()['make'] ?? '',
                'model': d.data()['model'] ?? '',
                'plate': d.data()['plate'] ?? '',
              })
          .toList();
      setState(() {});
    } catch (e) {
      debugPrint('Load profile error: $e');
    }
  }

  Future<void> _saveProfile() async {
    final uid = _user?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final photoUrl = _photoUrlCtrl.text.trim();
      if (_user != null && photoUrl.isNotEmpty) {
        await _user!.updatePhotoURL(photoUrl);
      }

      final batch = FirebaseFirestore.instance.batch();
      final profileRef = FirebaseFirestore.instance.collection('profiles').doc(uid);

      batch.set(profileRef, {
        'name': _nameCtrl.text.trim(),
        'average': double.tryParse(_avgCtrl.text.trim()) ?? _avgCtrl.text.trim(),
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final vehiclesRef = profileRef.collection('vehicles');
      final old = await vehiclesRef.get();
      for (final d in old.docs) {
        batch.delete(d.reference);
      }
      for (final v in _vehicles) {
        batch.set(vehiclesRef.doc(), {
          'make': v['make'] ?? '',
          'model': v['model'] ?? '',
          'plate': v['plate'] ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Firestore')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final uid = _user?.uid;
    if (uid == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
    if (picked == null) return;

    setState(() => _uploading = true);
    final file = File(picked.path);
    final ref = FirebaseStorage.instance.ref().child('profile_photos/$uid.jpg');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    setState(() {
      _photoUrlCtrl.text = url;
      _uploading = false;
    });
  }

  void _addVehicle() {
    final nameCtrl = TextEditingController(text: _nameCtrl.text);
    final avgCtrl = TextEditingController(text: _avgCtrl.text);
    final makeCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final plateCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                controller: avgCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Average (e.g., mileage)'),
              ),
              const SizedBox(height: 12),
              TextField(controller: makeCtrl, decoration: const InputDecoration(labelText: 'Make')),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
              TextField(controller: plateCtrl, decoration: const InputDecoration(labelText: 'Number / Plate')),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  // Save name/avg into profile controllers
                  _nameCtrl.text = nameCtrl.text.trim();
                  _avgCtrl.text = avgCtrl.text.trim();
                  // Add vehicle
                  setState(() {
                    _vehicles.add({
                      'make': makeCtrl.text.trim(),
                      'model': modelCtrl.text.trim(),
                      'plate': plateCtrl.text.trim(),
                    });
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Add vehicle & save info'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _photoUrlCtrl.text.trim();
    final initials = (_nameCtrl.text.isNotEmpty
            ? _nameCtrl.text.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
            : (_user?.email?.isNotEmpty ?? false)
                ? _user!.email![0].toUpperCase()
                : '?')
        .padRight(1);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header card with avatar and login info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty ? Text(initials, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)) : null,
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: IconButton(
                            iconSize: 22,
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(36, 36),
                            ),
                            icon: _uploading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.photo_camera),
                            onPressed: _uploading ? null : _pickAndUploadPhoto,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_user?.email ?? _user?.phoneNumber ?? 'Unknown user', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('UID: ${_user?.uid ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Vehicles', style: TextStyle(fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addVehicle, icon: const Icon(Icons.add), label: const Text('Add')),
              ],
            ),
            ..._vehicles.asMap().entries.map((entry) {
              final i = entry.key;
              final v = entry.value;
              return Card(
                child: ListTile(
                  title: Text('${v['make'] ?? ''} ${v['model'] ?? ''}'),
                  subtitle: Text(v['plate'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => setState(() => _vehicles.removeAt(i)),
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}