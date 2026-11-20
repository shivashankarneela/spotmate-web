import 'dart:math';
import 'package:flutter/material.dart';
import 'package:spotmate/core/utils/spotmate_image_upload.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';
import 'package:spotmate/features/wallet/presentation/recharge_screen.dart';

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
  String _avatarType='photo';
  String _avatarEmoticon='smile';
  int? _walletBalance;
  List<Map<String,dynamic>> _walletHistory=[];
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

  Future<void> _blockedUsers() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final blocks = await _supabase.from('user_blocks').select('blocked_id').eq('blocker_id',uid);
      final ids = blocks.map((row) => row['blocked_id'].toString()).toList();
      final names = <String,String>{};
      if (ids.isNotEmpty) {
        final profiles = await _supabase.from('user_profiles').select('id,name').inFilter('id',ids);
        for (final p in profiles) { names[p['id'].toString()] = p['name']?.toString() ?? 'Member'; }
      }
      if (!mounted) return;
      final pending = <String>{};
      await showModalBottomSheet<void>(context: context,showDragHandle:true,builder:(sheet) =>
        StatefulBuilder(builder:(context,refresh) => SafeArea(child:ListView(shrinkWrap:true,children:[
          const ListTile(title:Text('Blocked users')),
          if (ids.isEmpty) const ListTile(title: Text('No blocked users')),
          for (final id in ids) ListTile(title:Text(names[id] ?? 'Member'),subtitle: names[id]==null ? Text(id) : null,
            trailing: TextButton(onPressed: pending.contains(id) ? null : () async {
              refresh(()=>pending.add(id));
              try {
                await _supabase.from('user_blocks').delete().eq('blocker_id',uid).eq('blocked_id',id);
                if(context.mounted) refresh(()=>ids.remove(id));
              } catch (_) {
                if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not unblock user.')));
              } finally { if(context.mounted) refresh(()=>pending.remove(id)); }
            },child:const Text('Unblock'))),
        ]))));
    } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load blocked users.')));
    }
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

      try {
        final balanceRow=await _supabase.from('wallets').select('balance').eq('user_id',user.id).maybeSingle();
        final txRows=await _supabase.from('wallet_transactions')
            .select('amount,transaction_type,description,created_at').eq('user_id',user.id)
            .order('created_at',ascending:false).limit(10);
        _walletBalance=(balanceRow?['balance'] as num?)?.toInt();
        _walletHistory=List<Map<String,dynamic>>.from(txRows);
      } catch (_) {}
      if (profile != null && mounted) {
        _nameController.text = profile['name'] ?? '';
        _bioController.text = profile['bio'] ?? '';
        _emailController.text = user.email ?? '';
        _gender = profile['gender'];
        _lookingFor = profile['looking_for'];
        _selectedCityId = profile['city_id'];
        _photoUrl = profile['profile_photo'];
        _avatarType=profile['avatar_type'] ?? 'photo';
        _avatarEmoticon=profile['avatar_emoticon'] ?? 'smile';
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
      final image = await prepareSpotmateImage(
          await pickedFile.readAsBytes(), maxBytes: 5 * 1024 * 1024);
      if (!mounted) return;
      setState(() {
        _newImageBytes = image.bytes;
        _avatarType = 'photo';
        _isEditing = true;
        _newImageExt = image.extension;
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
          fileOptions: FileOptions(upsert: true, contentType: mimeTypeForSpotmateExtension(_newImageExt!)),
        );
        updatedPhotoUrl = '${_supabase.storage.from('profile_photos').getPublicUrl(filePath)}?v=${DateTime.now().millisecondsSinceEpoch}';
      }

      await _supabase.from('user_profiles').upsert({
        'id': user.id,
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'gender': _gender,
        'looking_for': _lookingFor,
        'city_id': _selectedCityId,
        'avatar_type': _avatarType,
        'avatar_emoticon': _avatarEmoticon,
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
        title: Text(_isEditing ? 'Edit profile' : 'Account'),
        actions: [
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 56),
              child: TextButton(
                onPressed: _isSaving ? null : () {
                  setState(() {
                    _isEditing = false;
                    _newImageBytes = null;
                    _newImageExt = null;
                  });
                  _loadProfile();
                },
                child: const Text('Cancel'),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _avatarType=='emoticon' ? null : _newImageBytes != null
                      ? MemoryImage(_newImageBytes!)
                      : (_photoUrl != null && _photoUrl!.isNotEmpty ? NetworkImage(_photoUrl!) as ImageProvider : null),
                  child: _avatarType=='emoticon'
                      ? SpotmateAvatar(size:86,avatarType:'emoticon',emoticon:_avatarEmoticon)
                      : (_photoUrl == null || _photoUrl!.isEmpty) && _newImageBytes == null
                          ? const Icon(Icons.person, size: 44, color: Colors.grey)
                          : null,
                ),
                Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary,
                      radius: 16,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                        tooltip: 'Change photo anytime',
                        onPressed: () {
                          _pickImage();
                        },
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isEditing) ...[
              Text(_nameController.text, style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(cityName.toString(), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit profile'),
              ),
              const SizedBox(height: 12),
            ],
            if (_isEditing) ...[
              SpotmateAvatarPicker(
                avatarType:_avatarType,emoticon:_avatarEmoticon,
                onChoice:(type,emoticon)=>setState((){
                  _avatarType=type; _avatarEmoticon=emoticon;
                }),
                onPickPhoto:_pickImage,
              ),
              const SizedBox(height: 16),
            ],
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
                    'User ID: ${_spotmateId ?? "SM-XXXXXX"}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF6C63FF)),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      if (_spotmateId != null) {
                        Clipboard.setData(ClipboardData(text: _spotmateId!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User ID copied to clipboard!')),
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
              Align(alignment: Alignment.centerLeft,
                child: Text('Profile details', style: theme.textTheme.titleMedium)),
              const SizedBox(height: 8),
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
              const SizedBox(height: 20),
              ListTile(leading:const Icon(Icons.block), title:const Text('Blocked users'), onTap:_blockedUsers),
              Card(
                color: const Color(0xFF162544),
                shape: RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
                child: Padding(
                  padding:const EdgeInsets.all(18),
                  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    const Row(children:[
                      Icon(Icons.account_balance_wallet_outlined,color:Color(0xFF35D6B4)),
                      SizedBox(width:10),
                      Text('Wallet',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.bold)),
                    ]),
                    const SizedBox(height:10),
                    Text('${_walletBalance ?? '—'} SC',
                      style: const TextStyle(color:Color(0xFF35D6B4),fontSize:30,fontWeight:FontWeight.w800)),
                    const SizedBox(height:14),
                    OutlinedButton.icon(
                      onPressed:()=>Navigator.push(context,MaterialPageRoute(
                        builder:(_)=>const SpotmateRechargeScreen())),
                      icon:const Icon(Icons.add_card,color:Color(0xFF35D6B4)),
                      label:const Text('Recharge options',style:TextStyle(color:Colors.white)),
                    ),
                    const SizedBox(height:14),
                    const Text('Recent activity',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),
                    if(_walletHistory.isEmpty) const Padding(
                      padding:EdgeInsets.only(top:6),child:Text('No transactions yet',
                      style:TextStyle(color:Colors.white70))),
                    ..._walletHistory.take(4).map((tx)=>Padding(
                      padding:const EdgeInsets.only(top:8),
                      child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                        Expanded(child:Text(tx['description']?.toString() ?? tx['transaction_type'].toString(),
                          style:const TextStyle(color:Colors.white70,fontSize:12),maxLines:1,overflow:TextOverflow.ellipsis)),
                        Text('${(tx['amount'] as num).toInt()>0?'+':''}${tx['amount']} SC',
                          style:const TextStyle(color:Color(0xFF35D6B4),fontWeight:FontWeight.bold)),
                      ]),
                    )),
                  ]),
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
            ),
          ],
        ),
          ),
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



