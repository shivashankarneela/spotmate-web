import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();

  String? _gender;
  String? _lookingFor;
  DateTime? _dateOfBirth;
  String? _selectedCityId;
  String? _photoUrl;
  String? _spotmateId;
  bool _isVerified = false;
  List<Map<String, dynamic>> _cities = [];

  Uint8List? _newImageBytes;
  String? _newImageExt;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final citiesRes = await _supabase.from('cities').select('id, name, state').eq('is_active', true);
      _cities = List<Map<String, dynamic>>.from(citiesRes);

      final profile = await _supabase.from('user_profiles').select('*').eq('id', user.id).maybeSingle();

      if (profile != null && mounted) {
        _nameController.text = profile['name'] ?? '';
        _bioController.text = profile['bio'] ?? '';
        _emailController.text = user.email ?? '';
        _gender = profile['gender'];
        _lookingFor = profile['looking_for'];
        _selectedCityId = profile['city_id'];
        _photoUrl = profile['profile_photo'];
        _spotmateId = profile['spotmate_id'] ?? 'SM-${Random().nextInt(900000) + 100000}';
        _isVerified = profile['is_verified'] == true;
        if (profile['date_of_birth'] != null) {
          _dateOfBirth = DateTime.tryParse(profile['date_of_birth']);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _newImageBytes = bytes;
        _newImageExt = pickedFile.name.split('.').last;
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? updatedPhotoUrl = _photoUrl;

      if (_newImageBytes != null && _newImageExt != null) {
        final filePath = '${user.id}/avatar.$_newImageExt';
        await _supabase.storage.from('profile_photos').uploadBinary(
          filePath,
          _newImageBytes!,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$_newImageExt'),
        );
        updatedPhotoUrl = _supabase.storage.from('profile_photos').getPublicUrl(filePath);
      }

      await _supabase.from('user_profiles').upsert({
        'id': user.id,
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'gender': _gender,
        'looking_for': _lookingFor,
        'city_id': _selectedCityId,
        'spotmate_id': _spotmateId,
        'is_verified': _isVerified,
        if (_dateOfBirth != null) 'date_of_birth': DateFormat('yyyy-MM-dd').format(_dateOfBirth!),
        if (updatedPhotoUrl != null) 'profile_photo': updatedPhotoUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      setState(() {
        _photoUrl = updatedPhotoUrl;
        _newImageBytes = null;
        _isEditing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _supabase.auth.currentUser;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cityName = _cities.firstWhere(
      (c) => c['id'] == _selectedCityId,
      orElse: () => {'name': 'Not set'},
    )['name'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 64,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _newImageBytes != null
                      ? MemoryImage(_newImageBytes!)
                      : (_photoUrl != null && _photoUrl!.isNotEmpty ? NetworkImage(_photoUrl!) as ImageProvider : null),
                  child: (_photoUrl == null || _photoUrl!.isEmpty) && _newImageBytes == null
                      ? const Icon(Icons.person, size: 64, color: Colors.grey)
                      : null,
                ),
                if (_isEditing)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge, size: 18, color: Color(0xFF6C63FF)),
                  const SizedBox(width: 6),
                  Text(
                    'Spotmate ID: ${_spotmateId ?? "SM-XXXXXX"}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF6C63FF)),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      if (_spotmateId != null) {
                        Clipboard.setData(ClipboardData(text: _spotmateId!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Spotmate ID copied to clipboard!')),
                        );
                      }
                    },
                    child: const Icon(Icons.copy, size: 16, color: Color(0xFF6C63FF)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_isVerified)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text('Verified Account', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            if (!_isEditing) ...[
              Text(_nameController.text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(user?.email ?? _emailController.text, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.location_city, size: 16),
                label: Text(cityName),
              ),
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInfoRow(Icons.email_outlined, 'Email', user?.email ?? _emailController.text),
                      const Divider(),
                      _buildInfoRow(Icons.person_outline, 'Gender', _gender ?? 'Not set'),
                      const Divider(),
                      _buildInfoRow(Icons.favorite_border, 'Looking For', _lookingFor ?? 'Everyone'),
                      const Divider(),
                      _buildInfoRow(Icons.cake_outlined, 'Birthday', _dateOfBirth != null ? DateFormat('dd MMM yyyy').format(_dateOfBirth!) : 'Not set'),
                      const Divider(),
                      _buildInfoRow(Icons.notes_rounded, 'Bio', _bioController.text.isEmpty ? 'No bio added yet.' : _bioController.text),
                    ],
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Valid Email Address',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Non-Binary', child: Text('Non-Binary')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _lookingFor,
                decoration: const InputDecoration(
                  labelText: 'Looking For',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                items: const [
                  DropdownMenuItem(value: 'Women', child: Text('Women')),
                  DropdownMenuItem(value: 'Men', child: Text('Men')),
                  DropdownMenuItem(value: 'Everyone', child: Text('Everyone')),
                ],
                onChanged: (v) => setState(() => _lookingFor = v),
              ),
              const SizedBox(height: 14),
              if (_cities.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedCityId,
                  decoration: const InputDecoration(
                    labelText: 'Primary City',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  items: _cities.map((c) => DropdownMenuItem<String>(value: c['id'], child: Text('${c['name']}, ${c['state']}'))).toList(),
                  onChanged: (v) => setState(() => _selectedCityId = v),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: _bioController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async => await _supabase.auth.signOut(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6C63FF),
                  side: const BorderSide(color: Color(0xFFDAD7F7)),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, style: TextStyle(color: Colors.grey[800]))),
        ],
      ),
    );
  }
}



