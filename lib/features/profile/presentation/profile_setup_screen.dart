import 'email_verification_tile.dart';
import 'package:spotmate/core/account_validation.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:spotmate/core/utils/spotmate_image_upload.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';

class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback onProfileCompleted;
  const ProfileSetupScreen({super.key, required this.onProfileCompleted});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _bioController = TextEditingController();
  final _usernameController = TextEditingController();
  final _supabase = Supabase.instance.client;

  String? _gender = 'Male';
  String? _lookingFor = 'Everyone';
  DateTime? _dateOfBirth;
  String? _selectedCityId;
  List<Map<String, dynamic>> _cities = [];

  String _avatarType='emoticon';
  String _avatarEmoticon='boy_01';
  Uint8List? _imageBytes;
  String? _imageExtension;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCitiesAndExistingProfile();
  }

  Future<void> _loadCitiesAndExistingProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase.from('cities').select('id, name, state').eq('is_active', true);
      final profile = await _supabase.from('user_profiles').select('*').eq('id', user.id).maybeSingle();

      if (mounted) {
        setState(() {
          _cities = List<Map<String, dynamic>>.from(response);
          if (_cities.isNotEmpty) {
            _selectedCityId = profile?['city_id'] ?? _cities.first['id'];
          }
          if (profile != null) {
            _gender = profile['gender'] ?? _gender;
            _avatarType = profile['avatar_type'] ?? _avatarType;
            _avatarEmoticon = profile['avatar_emoticon'] ?? _avatarEmoticon;
            _lookingFor = profile['looking_for'] ?? _lookingFor;
            _bioController.text = profile['bio'] ?? '';
            _usernameController.text = profile['username'] as String? ?? '';
            if (profile['date_of_birth'] != null) {
              _dateOfBirth = DateTime.tryParse(profile['date_of_birth']);
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (pickedFile != null) {
      final image = await prepareSpotmateImage(
          await pickedFile.readAsBytes(), maxBytes: 5 * 1024 * 1024);
      if (!mounted) return;
      setState(() {
        _imageBytes = image.bytes;
        _imageExtension = image.extension;
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (_dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth.')),
      );
      return;
    }

    if (_selectedCityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose your city.')),
      );
      return;
    }
    final username = _usernameController.text.trim();
    if (!isValidUsername(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(usernameRequirements)),
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      String? photoUrl;

      if (_imageBytes != null && _imageExtension != null) {
        final filePath = '${user.id}/avatar.$_imageExtension';
        await _supabase.storage.from('profile_photos').uploadBinary(
          filePath,
          _imageBytes!,
          fileOptions: FileOptions(upsert: true, contentType: mimeTypeForSpotmateExtension(_imageExtension!)),
        );
        photoUrl = '${_supabase.storage.from('profile_photos').getPublicUrl(filePath)}?v=${DateTime.now().millisecondsSinceEpoch}';
      }

      await _supabase.from('user_profiles').upsert({
        'id': user.id,
        'username': username,
        'gender': _gender,
        'avatar_type': _avatarType,
        'avatar_emoticon': _avatarEmoticon,
        'looking_for': _lookingFor,
        'date_of_birth': DateFormat('yyyy-MM-dd').format(_dateOfBirth!),
        'bio': _bioController.text.trim(),
        'city_id': _selectedCityId,
        'name': user.userMetadata?['name'] ?? user.email?.split('@').first ?? 'Spotmate User',
        if (photoUrl != null) 'profile_photo': photoUrl,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      widget.onProfileCompleted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is PostgrestException && e.code == '23505' && (e.message.contains('username') || e.details.toString().contains('username')) ? 'That username is already taken.' : 'Failed to save profile: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account'), actions: [
        IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout),
          onPressed: () => _supabase.auth.signOut(scope: SignOutScope.local)),
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EmailVerificationTile(),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _avatarType=='photo' && _imageBytes != null ? MemoryImage(_imageBytes!) : null,
                    child: _avatarType=='emoticon'
                        ? SpotmateAvatar(size:100,avatarType:'emoticon',emoticon:_avatarEmoticon)
                        : _imageBytes==null ? const Icon(Icons.person, size: 54, color: Colors.grey) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SpotmateAvatarPicker(
              avatarType:_avatarType,emoticon:_avatarEmoticon,
              onChoice:(type,emoticon)=>setState((){
                _avatarType=type;_avatarEmoticon=emoticon;
              }),
              onPickPhoto:_pickImage,
            ),
            const SizedBox(height: 24),
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.cake_outlined),
              title: Text(
                _dateOfBirth == null
                    ? 'Select Date of Birth'
                    : 'DOB: ${DateFormat('dd MMM yyyy').format(_dateOfBirth!)}',
              ),
              trailing: const Icon(Icons.calendar_today, size: 20),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                );
                if (date != null) setState(() => _dateOfBirth = date);
              },
            ),
            const SizedBox(height: 16),

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
              onChanged: (val) => setState(() => _gender = val),
            ),
            const SizedBox(height: 16),

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
              onChanged: (val) => setState(() => _lookingFor = val),
            ),
            const SizedBox(height: 16),

            if (_cities.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedCityId,
                decoration: const InputDecoration(
                  labelText: 'Primary City',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                items: _cities.map((city) {
                  return DropdownMenuItem<String>(
                    value: city['id'] as String,
                    child: Text('${city['name']}, ${city['state']}'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCityId = val),
              ),
            const SizedBox(height: 16),

            TextField(
              controller: _usernameController,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                helperText: usernameRequirements,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Short Bio',
                hintText: 'What kind of places do you love hanging out at?',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
            const SizedBox(height: 28),

            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save & Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

