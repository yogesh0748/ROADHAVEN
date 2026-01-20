import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final _formKey = GlobalKey<FormState>();
  final _tripCtrl = TextEditingController();
  final _fuelCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _pathsCtrl = TextEditingController();
  final _issuesCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  String? _editingDocId;

  bool _posting = false;
  bool _loadingVehicles = false;
  String? _selectedVehicle;
  List<String> _vehicles = [];

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
    _loadVehicles();
  }

  @override
  void dispose() {
    _tripCtrl.dispose();
    _fuelCtrl.dispose();
    _kmCtrl.dispose();
    _pathsCtrl.dispose();
    _issuesCtrl.dispose();
    _sourceCtrl.dispose();
    _destCtrl.dispose();
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
      final payload = {
        'tripTitle': _tripCtrl.text.trim(),
        'vehicle': _selectedVehicle ?? _tripCtrl.text.trim(),
        'fuelUsed': double.tryParse(_fuelCtrl.text.trim()) ?? 0,
        'kilometers': double.tryParse(_kmCtrl.text.trim()) ?? 0,
        'bestPaths': _pathsCtrl.text.trim(),
        'issues': _issuesCtrl.text.trim(),
        'source': _sourceCtrl.text.trim(),
        'destination': _destCtrl.text.trim(),
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
      _tripCtrl.clear();
      _fuelCtrl.clear();
      _kmCtrl.clear();
      _pathsCtrl.clear();
      _issuesCtrl.clear();
      _sourceCtrl.clear();
      _destCtrl.clear();
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
    // Prep controllers for either new post or editing existing
    if (docId == null) {
      _editingDocId = null;
      _tripCtrl.clear();
      _fuelCtrl.clear();
      _kmCtrl.clear();
      _pathsCtrl.clear();
      _issuesCtrl.clear();
      if (_vehicles.isNotEmpty) {
        _selectedVehicle = _vehicles.first;
      }
    } else {
      _editingDocId = docId;
      _tripCtrl.text = (initialData?['tripTitle'] ?? '').toString();
      _fuelCtrl.text = (initialData?['fuelUsed'] ?? '').toString();
      _kmCtrl.text = (initialData?['kilometers'] ?? '').toString();
      _pathsCtrl.text = (initialData?['bestPaths'] ?? '').toString();
      _issuesCtrl.text = (initialData?['issues'] ?? '').toString();
      _sourceCtrl.text = (initialData?['source'] ?? '').toString();
      _destCtrl.text = (initialData?['destination'] ?? '').toString();
      _selectedVehicle = (initialData?['vehicle'] ?? '').toString();
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
                TextFormField(
                  controller: _tripCtrl,
                  decoration: const InputDecoration(labelText: 'Trip / Route name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter trip name' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _sourceCtrl,
                        decoration: const InputDecoration(labelText: 'Source'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter source' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _destCtrl,
                        decoration: const InputDecoration(labelText: 'Destination'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter destination' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loadingVehicles)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_vehicles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _selectedVehicle,
                    items: _vehicles
                        .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                        .toList(),
                    decoration: const InputDecoration(labelText: 'Vehicle used'),
                    onChanged: (val) => setState(() => _selectedVehicle = val),
                  )
                else
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Vehicle used'),
                    onChanged: (v) => _selectedVehicle = v,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter vehicle details' : null,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fuelCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Fuel used (L)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter fuel used' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _kmCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Distance (km)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter distance' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pathsCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Best paths / shortcuts',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Share at least one path note' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _issuesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'What went wrong? (road blocks, fuel stops, etc.)',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Describe issues or leave “None”.' : null,
                ),
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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload vehicles',
              onPressed: _loadVehicles,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All posts'),
              Tab(text: 'My posts'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _posting ? null : _openComposer,
          icon: const Icon(Icons.post_add),
          label: const Text('Post review'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Latest posts from riders',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _posting ? null : () => _openComposer(),
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
            final header = data['tripTitle'] as String? ?? 'Trip';
            final vehicle = data['vehicle'] as String? ?? 'Unknown vehicle';
            final fuel = (data['fuelUsed'] ?? 0).toString();
            final km = (data['kilometers'] ?? 0).toString();
            final bestPaths = data['bestPaths'] as String? ?? '';
            final issues = data['issues'] as String? ?? '';
            final source = data['source'] as String? ?? '';
            final dest = data['destination'] as String? ?? '';
            final author = data['userEmail'] as String? ?? 'Anonymous rider';
            final isOwner =
                (data['userId'] != null) && data['userId'] == FirebaseAuth.instance.currentUser?.uid;

            return Card(
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
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                        if (isOwner)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Edit your post',
                                onPressed: () => _openComposer(
                                  docId: docs[index].id,
                                  initialData: data,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'Delete your post',
                                onPressed: () => _confirmDelete(docs[index].id),
                              ),
                            ],
                          ),
                        if (createdAt != null)
                          Text(
                            '${createdAt.toLocal()}'.split('.').first,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(label: Text(vehicle)),
                        Chip(label: Text('$fuel L fuel')),
                        Chip(label: Text('$km km')),
                        if (source.isNotEmpty && dest.isNotEmpty)
                          Chip(label: Text('$source → $dest')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (bestPaths.isNotEmpty)
                      Text(
                        'Best paths: $bestPaths',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    if (bestPaths.isNotEmpty) const SizedBox(height: 8),
                    Text(
                      issues.isNotEmpty ? 'Issues: $issues' : 'Issues: None reported',
                      style: const TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            author,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
