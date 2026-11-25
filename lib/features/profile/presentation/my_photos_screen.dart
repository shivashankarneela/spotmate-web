import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyPhotosScreen extends StatefulWidget {
  const MyPhotosScreen({super.key, this.ownerId});


  final String? ownerId;

  @override
  State<MyPhotosScreen> createState() => _MyPhotosScreenState();
}

class _MyPhotosScreenState extends State<MyPhotosScreen> {
  final _client = Supabase.instance.client;
  final _picker = ImagePicker();
  late final String _owner = widget.ownerId ?? _client.auth.currentUser!.id;
  bool get _isOwner => _owner == _client.auth.currentUser?.id;
  late Future<_Gallery> _gallery = _load();
  bool _busy = false;

  Future<_Gallery> _load() async {
    final rows = await _client.from('profile_gallery_photos')
        .select('object_path,for_matchmaker').eq('user_id', _owner).order('created_at');
    final settings = _isOwner
        ? await _client.from('profile_photo_audiences')
            .select('audience,allowed_users').eq('user_id', _owner).maybeSingle()
        : null;
    return _Gallery(
      settings?['audience'] as String? ?? 'connections',
      Set<String>.from(settings?['allowed_users'] as List? ?? const []),
      [for (final row in rows) row['object_path'] as String],
      rows.where((row) => row['for_matchmaker'] == true)
          .map((row) => row['object_path'] as String).firstOrNull,
    );
  }

  Future<void> _edit(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) setState(() => _gallery = _load());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your photos or settings. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() => _edit(() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final png = bytes.length >= 8 &&
        bytes[0] == 137 && String.fromCharCodes(bytes.sublist(1, 4)) == 'PNG';
    final jpeg = bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    final webp = bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    if (bytes.length > 5 * 1024 * 1024 || !(png || jpeg || webp)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a JPEG, PNG, or WebP photo under 5 MB.')),
      );
      return;
    }
    final extension = png ? 'png' : (jpeg ? 'jpg' : 'webp');
    final type = jpeg ? 'image/jpeg' : 'image/$extension';
    final path = '$_owner/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final bucket = _client.storage.from('my-photos');
    await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type, cacheControl: '0'));
    try {
      await _client.from('profile_gallery_photos').insert({
        'user_id': _owner, 'object_path': path,
      });
    } catch (_) {
      await bucket.remove([path]);
      rethrow;
    }
  });

  Future<void> _changeAudience(_Gallery gallery) => _edit(() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Who can view your photos?'),
        children: [
          for (final option in const {
            'everyone': 'Everyone on SpotMate',
            'connections': 'Connections',
            'custom': 'Custom · Choose connections',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, option.key),
              child: Text(option.value),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    var allowed = gallery.allowed;
    if (selected == 'custom') {
      final friends = await _client.rpc('spotmate_friends') as List;
      if (!mounted) return;
      final picked = Set<String>.of(allowed)
        ..retainAll(friends.map((friend) => friend['friend_id'] as String));
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (_, update) => AlertDialog(
            title: const Text('Choose who can view your photos'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (friends.isEmpty) const Text('You have no connections to select.'),
                for (final friend in friends)
                  CheckboxListTile(
                    title: Text(friend['name'] as String? ?? 'Connection'),
                    value: picked.contains(friend['friend_id']),
                    onChanged: (value) => update(() {
                      final id = friend['friend_id'] as String;
                      if (value == true) { picked.add(id); } else { picked.remove(id); }
                    }),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save')),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      allowed = picked;
    }
    await _client.from('profile_photo_audiences').upsert({
      'user_id': _owner, 'audience': selected, 'allowed_users': allowed.toList(),
    });
  });

  Future<void> _remove(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove this photo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _edit(() async {
      await _client.from('profile_gallery_photos').delete().eq('object_path', path);
      await _client.storage.from('my-photos').remove([path]);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_isOwner ? 'My Photos' : 'Photos')),
    body: FutureBuilder<_Gallery>(
      future: _gallery,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton(
            onPressed: () => setState(() => _gallery = _load()),
            child: const Text('Could not load photos. Retry'),
          ));
        }
        final gallery = snapshot.data;
        if (gallery == null) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isOwner) ...[
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Who can view my photos'),
                subtitle: Text(switch (gallery.audience) {
                  'everyone' => 'Everyone on SpotMate',
                  'custom' => 'Custom · ${gallery.allowed.length} selected',
                  _ => 'Connections',
                }),
                onTap: _busy ? null : () => _changeAudience(gallery),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Upload photo'),
              ),
            ],
            if (gallery.photos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No photos to show'),
              ),
            for (final path in gallery.photos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _GalleryThumbnail(key: ValueKey((gallery, path)), path: path),
                    if (_isOwner)
                      TextButton(
                        onPressed: _busy || path == gallery.selected ? null : () =>
                          _edit(() async {
                            await _client.rpc('select_matchmaker_photo',
                              params: {'p_path': path});
                          }),
                        child: Text(path == gallery.selected
                            ? 'Matchmaking photo' : 'Use for matchmaking'),
                      ),
                    if (_isOwner)
                      TextButton(
                        onPressed: _busy ? null : () => _remove(path),
                        child: const Text('Remove photo'),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _Gallery {
  const _Gallery(this.audience, this.allowed, this.photos, this.selected);
  final String audience;
  final Set<String> allowed;
  final List<String> photos;
  final String? selected;
}

class _GalleryThumbnail extends StatefulWidget {
  const _GalleryThumbnail({super.key, required this.path});
  final String path;

  @override
  State<_GalleryThumbnail> createState() => _GalleryThumbnailState();
}

class _GalleryThumbnailState extends State<_GalleryThumbnail> {
  late final _image = Supabase.instance.client.storage
      .from('my-photos').download(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, image) {
      if (image.hasError) return const Text('Photo unavailable');
      final bytes = image.data;
      if (bytes == null) return const LinearProgressIndicator();
      return Image.memory(
        bytes,
        height: 240,
        fit: BoxFit.contain,
        semanticLabel: 'Profile gallery photo',
        errorBuilder: (_, error, stack) => const Text('Photo unavailable'),
      );
    },
  );
}

class AccountPhotoStrip extends StatefulWidget {
  const AccountPhotoStrip({super.key});

  @override
  State<AccountPhotoStrip> createState() => _AccountPhotoStripState();
}

class _AccountPhotoStripState extends State<AccountPhotoStrip> {
  late Future<List<Map<String, dynamic>>> _photos = _load();
  final _preferences = SharedPreferencesAsync();
  late final _reminderKey =
      'spotmate.photo-reminder-dismissed.${Supabase.instance.client.auth.currentUser?.id}';
  bool _hideReminder = true;

  @override
  void initState() {
    super.initState();
    _readReminder();
  }

  Future<void> _readReminder() async {
    try {
      final dismissed = await _preferences.getBool(_reminderKey);
      if (mounted) setState(() => _hideReminder = dismissed == true);
    } catch (_) {
      if (mounted) setState(() => _hideReminder = false);
    }
  }

  Future<void> _dismissReminder() async {
    setState(() => _hideReminder = true);
    try {
      await _preferences.setBool(_reminderKey, true);
    } catch (_) {
      // Keep the reminder dismissed for this session.
    }
  }


  Future<List<Map<String, dynamic>>> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return [];
    return client.from('profile_gallery_photos')
        .select('object_path,for_matchmaker')
        .eq('user_id', uid)
        .order('for_matchmaker', ascending: false)
        .order('created_at')
        .limit(2);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const MyPhotosScreen(),
    ));
    if (mounted) setState(() => _photos = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('My Photos', style: Theme.of(context).textTheme.titleLarge)),
          TextButton(onPressed: _open, child: const Text('Manage')),
        ]),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _photos,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(onPressed: () => setState(() => _photos = _load()),
                child: const Text('Retry loading photos'));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            if (snapshot.data!.isEmpty) {
              if (_hideReminder) return const SizedBox.shrink();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Add a profile photo'),
                onTap: _open,
                trailing: IconButton(tooltip: 'Dismiss photo reminder',
                  icon: const Icon(Icons.close), onPressed: _dismissReminder),
              );
            }
            return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final photo in snapshot.data ?? const <Map<String, dynamic>>[])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _GalleryThumbnail(
                          key: ValueKey(photo['object_path']),
                          path: photo['object_path'] as String,
                        ),
                      ),
                    ),
                    if (photo['for_matchmaker'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Matchmaking photo', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11)),
                      ),
                  ]),
                )),
              Expanded(child: OutlinedButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add photo'),
              )),
            ],
            );
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('Photo visibility'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _open,
        ),
      ],
    );
  }
}
