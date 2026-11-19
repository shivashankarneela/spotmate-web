import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:spotmate/core/utils/spotmate_image_upload.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/features/chat/presentation/active_call_screen.dart';
import 'package:spotmate/features/profile/presentation/user_profile_detail_screen.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';
import 'package:spotmate/core/widgets/spotmate_chat_theme.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserPhoto;
  final String? otherUserAvatarType;
  final String? otherUserAvatarEmoticon;
  final String? otherUserId;
  final String? connectionId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserPhoto,
    this.otherUserAvatarType,
    this.otherUserAvatarEmoticon,
    this.otherUserId,
    this.connectionId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _subscription;
  RealtimeChannel? _profileSubscription;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _recordStream;
  final BytesBuilder _recordBytes = BytesBuilder(copy: false);
  Timer? _recordTimer;
  bool _recording = false;
  bool _searching = false;
  String _search = '';
  String? _playingMessage;
  String? _currentPhoto;
  String? _currentName;
  String? _currentAvatarType;
  String? _currentAvatarEmoticon;
  SpotmateChatTheme _chatTheme = SpotmateChatTheme.defaultTheme;
  RealtimeChannel? _themeChannel;
  final _searchController = TextEditingController();
  bool _isLoading = true;
  bool _showEmojiTray = false;
  bool _isUploadingImage = false;
  bool _otherUserOnline = false;
  DateTime? _otherUserLastSeen;
  Timer? _presenceRefreshTimer;

  final Map<String, Future<String>> _signedImageLinks = {};
  static const maxAttachmentSize = 1024 * 1024 - 1;
  static const _maxVoiceSeconds = 15;
  static const Map<String, String> _allowedFiles = {
    'pdf': 'application/pdf', 'txt': 'text/plain', 'csv': 'text/csv',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
  };

  Future<String> _getChatImageUrl(String imagePath) {
    if (imagePath.startsWith('https://')) return Future.value(imagePath);
    return _signedImageLinks.putIfAbsent(imagePath, () =>
      _supabase.storage.from('chat_media').createSignedUrl(imagePath, 3600));
  }

  final List<String> _quickEmojis = [
    '❤️', '😂', '😍', '🔥', '👋', '☕', '🍕', '🎉', '💯', '😎', '🥂', '✨', '💬', '🙌', '🥰', '👍'
  ];

  @override
  void initState() {
    super.initState();
    _fetchMessagesAndMarkRead();
    _subscribeToRealtime();
    _subscribeReactions();
    _fetchOtherUserPresence();
    _loadContact();
    _subscribeToProfile();
    _loadChatTheme();
    _subscribeTheme();

    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchOtherUserPresence(),
    );
  }
  Future<void> _loadContact() async {
    final id = widget.otherUserId;
    if (id == null || id.isEmpty) return;
    try {
      final row = await _supabase.from('user_profiles')
          .select('name,profile_photo,avatar_type,avatar_emoticon,last_seen_at').eq('id', id).maybeSingle();
      if (!mounted || row == null) return;
      final seen = DateTime.tryParse(row['last_seen_at']?.toString() ?? '')?.toLocal();
      setState(() {
        _currentPhoto = row['profile_photo']?.toString();
        _currentName = row['name']?.toString();
        _currentAvatarType = row['avatar_type']?.toString() ?? 'emoticon';
        _currentAvatarEmoticon = row['avatar_emoticon']?.toString() ?? 'boy_01';
        _otherUserLastSeen = seen;
        _otherUserOnline = seen != null &&
            DateTime.now().difference(seen).inSeconds < 60;
      });
    } catch (_) {}
  }

  void _subscribeToProfile() {
    final id = widget.otherUserId;
    if (id == null || id.isEmpty) return;
    _profileSubscription = _supabase.channel('chat-profile-$id-${widget.conversationId}')
      .onPostgresChanges(event: PostgresChangeEvent.update,
          schema: 'public', table: 'user_profiles',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
              column: 'id', value: id),
          callback: (_) => _loadContact())
      .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) _loadContact();
      });
  }


  Future<void> _loadChatTheme() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final row = await _supabase.from('chat_theme_preferences')
        .select('theme_key')
        .eq('conversation_id', widget.conversationId)
        .eq('user_id', user.id).maybeSingle();
      if (mounted) setState(() =>
        _chatTheme = SpotmateChatTheme.forKey(row?['theme_key']?.toString()));
    } catch (_) {
      // Keep the default palette without blocking messaging.
    }
  }

  void _subscribeTheme() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    _themeChannel = _supabase.channel('chat-theme-${widget.conversationId}-${user.id}')
      .onPostgresChanges(event:PostgresChangeEvent.all,
        schema:'public',table:'chat_theme_preferences',
        filter: PostgresChangeFilter(type:PostgresChangeFilterType.eq,
          column:'conversation_id',value:widget.conversationId),
        callback:(_)=>_loadChatTheme())
      .subscribe((status,error) {
        if (status==RealtimeSubscribeStatus.subscribed) _loadChatTheme();
      });
  }

  Future<void> _saveChatTheme(SpotmateChatTheme choice) async {
    final old = _chatTheme;
    setState(() => _chatTheme = choice);
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.from('chat_theme_preferences').upsert({
        'conversation_id':widget.conversationId,
        'user_id':user.id,
        'theme_key':choice.key,
        'updated_at':DateTime.now().toUtc().toIso8601String(),
      },onConflict:'conversation_id,user_id');
    } catch (error) {
      if (mounted) {
        setState(() => _chatTheme = old);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Theme was not saved: $error')));
      }
    }
  }

  void _chooseTheme() {
    showModalBottomSheet<void>(context:context,isScrollControlled:true,
      showDragHandle:true,builder:(sheet) => SafeArea(
        child:FractionallySizedBox(heightFactor:.78,child:Column(children:[
          const Padding(padding:EdgeInsets.all(16),child:Column(children:[
            Text('Choose a chat theme',style:TextStyle(
              fontSize:21,fontWeight:FontWeight.bold)),
            SizedBox(height:5),
            Text('Themes apply to your view of this conversation.',
              textAlign:TextAlign.center),
          ])),
          Expanded(child:GridView.builder(
            padding:const EdgeInsets.fromLTRB(12,4,12,24),
            gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:2,mainAxisSpacing:12,crossAxisSpacing:12,
              childAspectRatio:.82),
            itemCount:SpotmateChatTheme.choices.length,
            itemBuilder:(ctx,index) {
              final theme=SpotmateChatTheme.choices[index];
              final selected=_chatTheme.key==theme.key;
              return InkWell(borderRadius:BorderRadius.circular(16),
                onTap:() {Navigator.pop(sheet);_saveChatTheme(theme);},
                child:Container(
                  decoration:BoxDecoration(
                    color:theme.background,
                    border:Border.all(
                      color:selected ? Theme.of(context).colorScheme.primary
                        : theme.accent.withOpacity(.5),
                      width:selected?3:1),
                    borderRadius:BorderRadius.circular(16)),
                  child:Column(children:[
                    Container(height:24,decoration:BoxDecoration(
                      color:theme.header,
                      borderRadius:const BorderRadius.vertical(
                        top:Radius.circular(14))),
                      child:Center(child:Icon(Icons.more_horiz,
                        size:18,color:theme.text))),
                    Expanded(child:Padding(
                      padding:const EdgeInsets.all(10),
                      child:Column(mainAxisAlignment:MainAxisAlignment.center,
                        crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                        Align(alignment:Alignment.centerLeft,
                          child:Container(
                            padding:const EdgeInsets.all(7),
                            decoration:BoxDecoration(color:theme.incoming,
                              borderRadius:BorderRadius.circular(8)),
                            child:Text('Hello',style:TextStyle(
                              fontSize:11,color:theme.text)))),
                        const SizedBox(height:8),
                        Align(alignment:Alignment.centerRight,
                          child:Container(
                            padding:const EdgeInsets.all(7),
                            decoration:BoxDecoration(color:theme.outgoing,
                              borderRadius:BorderRadius.circular(8)),
                            child:Text('Hi there!',style:TextStyle(
                              fontSize:11,color:theme.outgoingText)))),
                      ]))),
                    Container(padding:const EdgeInsets.fromLTRB(7,6,7,10),
                      child:Column(children:[
                        Text(theme.name,style:TextStyle(
                          color:theme.text,fontSize:13,fontWeight:FontWeight.w700)),
                        const SizedBox(height:2),
                        Text(theme.subtitle,maxLines:2,textAlign:TextAlign.center,
                          style:TextStyle(color:theme.secondaryText,fontSize:9)),
                      ])),
                  ]),
                ));
            })),
        ]))));
  }

  void _openProfile() {
    final id = widget.otherUserId;
    if (id == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      UserProfileDetailScreen(userId: id, connectionId: widget.connectionId)))
      .then((_) => _loadContact());
  }

  Future<void> _fetchOtherUserPresence() async {
    final otherUserId = widget.otherUserId;
    if (otherUserId == null) return;

    try {
      final profile = await _supabase
          .from('user_profiles')
          .select('last_seen_at')
          .eq('id', otherUserId)
          .maybeSingle();

      if (!mounted) return;

      final rawLastSeen = profile?['last_seen_at'];
      final lastSeen = rawLastSeen != null
          ? DateTime.tryParse(rawLastSeen.toString())?.toLocal()
          : null;

      final isOnline = lastSeen != null &&
          DateTime.now().difference(lastSeen).inSeconds < 60;

      setState(() {
        _otherUserLastSeen = lastSeen;
        _otherUserOnline = isOnline;
      });
    } catch (_) {}
  }

  String _presenceText() {
    if (_otherUserOnline) return 'Online';

    final lastSeen = _otherUserLastSeen;
    if (lastSeen == null) return 'Offline';

    final difference = DateTime.now().difference(lastSeen);

    if (difference.inSeconds < 60) {
      return 'Last seen just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return 'Last seen $minutes min ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return 'Last seen $hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    if (difference.inDays == 1) {
      return 'Last seen yesterday';
    }

    return 'Last seen ${DateFormat('dd MMM').format(lastSeen)}';
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _fetchMessagesAndMarkRead() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      final response = await _supabase
          .from('messages')
          .select('id, sender_id, message, image_url, attachment_path, attachment_name, attachment_type, created_at, read_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(List<Map<String, dynamic>>.from(response));
          _isLoading = false;
        });
        _scrollToBottom();
      }

      await _supabase
          .from('messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', myId)
          .isFilter('read_at', null);

    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToRealtime() {
    final myId = _supabase.auth.currentUser?.id;

    _subscription = _supabase
        .channel('public:messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) async {
            if (!mounted) return;

            if (payload.eventType == PostgresChangeEvent.insert) {
              final newMsg = payload.newRecord;
              
              if (!_messages.any((m) => m['id'] == newMsg['id'])) {
                setState(() {
                  _messages.add(newMsg);
                });
                _scrollToBottom();
              }

              if (newMsg['sender_id'] != myId && newMsg['read_at'] == null) {
                await _supabase
                    .from('messages')
                    .update({'read_at': DateTime.now().toIso8601String()})
                    .eq('id', newMsg['id']);
              }
            } else if (payload.eventType == PostgresChangeEvent.update) {
              final updated = payload.newRecord;
              setState(() {
                final idx = _messages.indexWhere((m) => m['id'] == updated['id']);
                if (idx != -1) {
                  _messages[idx] = updated;
                }
              });
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final deletedId = payload.oldRecord['id'];
              setState(() {
                _messages.removeWhere((m) => m['id'] == deletedId);
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    final user = _supabase.auth.currentUser;
    if ((text.isEmpty && imageUrl == null) || user == null) return;

    _messageController.clear();

    try {
      await _supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'message': text.isNotEmpty ? text : (imageUrl != null ? '📷 Photo' : ''),
        if (imageUrl != null) 'image_url': imageUrl,
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  Future<void> _sendAttachment(Uint8List bytes, String extension,
      String mime, String name, {bool voice = false}) async {
    if (bytes.isEmpty || bytes.length >= 1024 * 1024) {
      throw const FormatException('Attachments must be smaller than 1 MB.');
    }
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    final path = '${widget.conversationId}/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _supabase.storage.from('chat_media').uploadBinary(path, bytes,
      fileOptions: FileOptions(contentType: mime, upsert: false));
    try {
      await _supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'message': voice ? 'Voice message' : name,
        'attachment_path': path,
        'attachment_name': name,
        'attachment_type': voice ? 'voice' : mime,
      });
    } catch (_) {
      await _supabase.storage.from('chat_media').remove([path]);
      rethrow;
    }
  }

  Future<void> _pickAttachment() async {
    if (_isUploadingImage || _recording) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: _allowedFiles.keys.toList(),
        withData: true);
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      final ext = file.extension?.toLowerCase() ?? '';
      final mime = _allowedFiles[ext];
      if (mime == null) throw const FormatException('Unsupported file type.');
      if (file.size >= 1024 * 1024) {
        throw const FormatException('Choose a file smaller than 1 MB.');
      }
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Unable to read the attachment.');
      if (!mounted) return;
      setState(() => _isUploadingImage = true);
      await _sendAttachment(bytes, ext, mime, file.name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attachment failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _startVoiceNote() async {
    if (_recording || _isUploadingImage) return;
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission was not granted.');
      }
      _recordBytes.clear();
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000, numChannels: 1));
      _recordStream = stream.listen((chunk) {
        _recordBytes.add(chunk);
        if (_recordBytes.length >= 850000) _finishVoiceNote();
      });
      if (!mounted) return;
      setState(() => _recording = true);
      _recordTimer = Timer(const Duration(seconds: _maxVoiceSeconds),
          () => _finishVoiceNote());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording unavailable: $e')));
    }
  }

  Uint8List _makeWav(Uint8List pcm) {
    final output = Uint8List(44 + pcm.length);
    final d = ByteData.sublistView(output);
    void ascii(int offset, String value) {
      for (var i=0; i<value.length; i++) output[offset+i]=value.codeUnitAt(i);
    }
    ascii(0,'RIFF'); d.setUint32(4,36+pcm.length,Endian.little);
    ascii(8,'WAVE'); ascii(12,'fmt ');
    d.setUint32(16,16,Endian.little);
    d.setUint16(20,1,Endian.little);
    d.setUint16(22,1,Endian.little);
    d.setUint32(24,16000,Endian.little);
    d.setUint32(28,32000,Endian.little);
    d.setUint16(32,2,Endian.little);
    d.setUint16(34,16,Endian.little);
    ascii(36,'data'); d.setUint32(40,pcm.length,Endian.little);
    output.setRange(44,output.length,pcm);
    return output;
  }

  Future<void> _finishVoiceNote({bool cancel = false}) async {
    if (!_recording) return;
    _recordTimer?.cancel();
    setState(() { _recording=false; _isUploadingImage=!cancel; });
    try {
      await _recorder.stop();
      await _recordStream?.cancel();
      _recordStream = null;
      final raw = _recordBytes.takeBytes();
      if (cancel) return;
      if (raw.length < 3200) throw const FormatException('Recording too short.');
      await _sendAttachment(_makeWav(raw), 'wav', 'audio/wav',
          'Voice note.wav', voice:true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice note failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingImage=false);
    }
  }

  Future<void> _openAttachment(String path, {bool voice=false, String? id}) async {
    try {
      final url = await _getChatImageUrl(path);
      if (voice) {
        if (_playingMessage == id) {
          await _player.stop();
          if (mounted) setState(() => _playingMessage=null);
        } else {
          await _player.play(UrlSource(url));
          if (mounted) setState(() => _playingMessage=id);
        }
      } else {
        final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('Unable to open the file.');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open attachment: $e')));
    }
  }

  void _showSharedMedia() {
    final shared = _messages.where((m) =>
      m['image_url'] != null || m['attachment_path'] != null).toList();
    showModalBottomSheet<void>(context: context, showDragHandle:true,
      builder: (ctx) => SafeArea(child: SizedBox(height: 400,
        child: Column(children:[
          const ListTile(title: Text('Shared media and files')),
          Expanded(child: shared.isEmpty
            ? const Center(child: Text('No shared media yet.'))
            : ListView.builder(itemCount: shared.length,
                itemBuilder: (ctx,i) {
                  final m=shared[i];
                  final path=(m['attachment_path'] ?? m['image_url']).toString();
                  return ListTile(
                    leading: Icon(m['attachment_type']=='voice'
                      ? Icons.mic : m['image_url']!=null ? Icons.image : Icons.insert_drive_file),
                    title: Text(m['attachment_name']?.toString() ??
                        m['message']?.toString() ?? 'Photo'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openAttachment(path,voice:m['attachment_type']=='voice',
                        id:m['id'].toString());
                    });
                })),
        ]))));
  }

  void _showCallHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CallHistorySheet(conversationId: widget.conversationId),
    );
  }

  RealtimeChannel? _reactionsChannel;
  List<Map<String, dynamic>> _reactions = [];
  int _reactionRequest = 0;
  bool _savingReaction = false;
  static const _reactionChoices = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  void _subscribeReactions() {
    _reactionsChannel = _supabase.channel('direct-reactions:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'direct_message_reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) => _loadReactions(),
        )
        .subscribe((state, _) {
          if (state == RealtimeSubscribeStatus.subscribed) _loadReactions();
        });
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    final version = ++_reactionRequest;
    try {
      final results = <Map<String, dynamic>>[];
      const pageSize = 500;
      for (var start = 0; mounted && version == _reactionRequest; start += pageSize) {
        final rows = await _supabase.from('direct_message_reactions')
            .select('message_id,user_id,reaction')
            .eq('conversation_id', widget.conversationId)
            .not('reaction', 'is', null)
            .order('message_id').order('user_id')
            .range(start, start + pageSize - 1);
        results.addAll(rows);
        if (rows.length < pageSize) break;
      }
      if (mounted && version == _reactionRequest) {
        setState(() => _reactions = results);
      }
    } catch (_) {
      // A later realtime event or manual refresh retries the read.
    }
  }

  Future<void> _pickReaction(String messageId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || _savingReaction) return;
    String? current;
    for (final row in _reactions) {
      if (row['message_id'] == messageId && row['user_id'] == userId) {
        current = row['reaction'] as String?;
        break;
      }
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final reaction in _reactionChoices)
            TextButton(
              onPressed: () => Navigator.pop(sheet, reaction),
              child: Text(reaction, style: const TextStyle(fontSize: 24)),
            ),
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(sheet, 'remove'),
              child: const Text('Remove reaction'),
            ),
        ],
      )),
    );
    if (!mounted || choice == null || _savingReaction) return;
    _savingReaction = true;
    try {
      await _supabase.from('direct_message_reactions').upsert({
        'message_id': messageId,
        'conversation_id': widget.conversationId,
        'user_id': userId,
        'reaction': choice == 'remove' || choice == current ? null : choice,
      }, onConflict: 'message_id,user_id');
      await _loadReactions();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save reaction. Try again.')),
      );
    } finally {
      _savingReaction = false;
    }
  }

  void _showMessageOptions(Map<String,dynamic> msg) {
    final own = msg['sender_id'] == _supabase.auth.currentUser?.id;
    showModalBottomSheet<void>(context:context,showDragHandle:true,
      builder:(sheet) => SafeArea(child: Wrap(children:[
        ListTile(leading: const Icon(Icons.add_reaction_outlined),
          title: const Text('React'),
          onTap: () { Navigator.pop(sheet); _pickReaction(msg['id'].toString()); }),
        if ((msg['message']?.toString() ?? '').isNotEmpty)
          ListTile(leading:const Icon(Icons.copy),title:const Text('Copy text'),
            onTap:(){
              Clipboard.setData(ClipboardData(text:msg['message'].toString()));
              Navigator.pop(sheet);
            }),
        if (own) ListTile(leading:const Icon(Icons.delete_outline,color:Colors.red),
          title:const Text('Delete for everyone'),
          onTap:(){Navigator.pop(sheet);_deleteSingleMessage(msg['id'].toString());}),
      ])));
  }

  Future<void> _pickAndSendPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 82);
    if (pickedFile == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final image = await prepareSpotmateImage(
          await pickedFile.readAsBytes(), maxBytes: maxAttachmentSize);
      final fileName = '${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}.${image.extension}';

      await _supabase.storage.from('chat_media').uploadBinary(
        fileName,
        image.bytes,
        fileOptions: FileOptions(upsert: false, contentType: image.mimeType),
      );

      await _sendMessage(imageUrl: fileName);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Chat History?'),
          ],
        ),
        content: const Text('Are you sure you want to clear all messages in this conversation? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('messages').delete().eq('conversation_id', widget.conversationId);
        setState(() => _messages.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat history cleared.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteSingleMessage(String msgId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('Do you want to delete this message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('messages').delete().eq('id', msgId);
      } catch (_) {}
    }
  }

  Future<void> _initiateCall(bool isVideo) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || widget.otherUserId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to identify the other user. Reopen this conversation and try again.')));
      return;
    }

    try {
      final callRes = await _supabase.from('calls').insert({
        'caller_id': myId,
        'receiver_id': widget.otherUserId,
        'conversation_id': widget.conversationId,
        'call_type': isVideo ? 'video' : 'audio',
        'status': 'ringing',
      }).select('id').single();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              callId: callRes['id'],
              otherUserName: widget.otherUserName,
              otherUserPhoto: widget.otherUserPhoto,
              isVideo: isVideo,
              isCaller: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _reactionsChannel?.unsubscribe();
    _profileSubscription?.unsubscribe();
    _themeChannel?.unsubscribe();
    _recordTimer?.cancel();
    _recordStream?.cancel();
    _recorder.stop();
    _recorder.dispose();
    _player.dispose();
    _searchController.dispose();
    _presenceRefreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _supabase.auth.currentUser?.id;

    final visibleMessages = _search.isEmpty ? _messages : _messages.where(
      (m) => (m['message']?.toString().toLowerCase() ?? '')
          .contains(_search.toLowerCase()) ||
          (m['attachment_name']?.toString().toLowerCase() ?? '')
          .contains(_search.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: _chatTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        foregroundColor: _chatTheme.text,
        backgroundColor: _chatTheme.header,
        elevation: 1,
        title: InkWell(
          onTap: () {
            if (widget.otherUserId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileDetailScreen(
                    userId: widget.otherUserId!,
                    connectionId: widget.connectionId,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('User profile unavailable. Reopen the chat and try again.')));
            }
          },
          child: Row(
            children: [
              ClipOval(child:SpotmateAvatar(size:38,
                photoUrl:_currentPhoto ?? widget.otherUserPhoto,
                avatarType:_currentAvatarType ?? widget.otherUserAvatarType ?? 'emoticon',
                emoticon:_currentAvatarEmoticon ?? widget.otherUserAvatarEmoticon ?? 'boy_01')),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_currentName ?? widget.otherUserName, style: TextStyle(fontSize:16,fontWeight:FontWeight.bold,color:_chatTheme.text)),
                    Text(_presenceText(), style: TextStyle(fontSize:11,color:_otherUserOnline ? Colors.green : _chatTheme.secondaryText,fontWeight:FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.call_rounded,color:_chatTheme.accent),
            tooltip: 'Audio Call',
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: Icon(Icons.videocam_rounded,color:_chatTheme.accent),
            tooltip: 'Video Call',
            onPressed: () => _initiateCall(true),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,color:_chatTheme.text),
            onSelected: (val) {
              switch(val) {
                case 'profile': _openProfile(); break;
                case 'calls': _showCallHistory(); break;
                case 'search': setState(() => _searching = !_searching); break;
                case 'theme': _chooseTheme(); break;
                case 'media': _showSharedMedia(); break;
                case 'refresh': _loadReactions(); _loadContact(); _fetchMessagesAndMarkRead(); break;
                case 'clear': _clearChat(); break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value:'calls',child:ListTile(
                dense:true,leading:Icon(Icons.history),title:Text('Call history'))),
              const PopupMenuItem(value:'profile',child:ListTile(
                dense:true,leading:Icon(Icons.person_outline),title:Text('View contact'))),
              const PopupMenuItem(value:'theme',child:ListTile(
                dense:true,leading:Icon(Icons.palette_outlined),title:Text('Chat theme'))),
              const PopupMenuItem(value:'search',child:ListTile(
                dense:true,leading:Icon(Icons.search),title:Text('Search chat'))),
              const PopupMenuItem(value:'media',child:ListTile(
                dense:true,leading:Icon(Icons.photo_library_outlined),title:Text('Media, files and voice notes'))),
              const PopupMenuItem(value:'refresh',child:ListTile(
                dense:true,leading:Icon(Icons.refresh),title:Text('Refresh chat'))),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Clear Chat History', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching) Padding(padding:const EdgeInsets.all(8),
            child:TextField(controller:_searchController,
              onChanged:(value)=>setState(()=>_search=value),
              decoration:InputDecoration(hintText:'Search messages',
                prefixIcon:const Icon(Icons.search),
                suffixIcon:IconButton(icon:const Icon(Icons.close),onPressed:(){
                  _searchController.clear();setState((){_searching=false;_search='';});
                })))),
          if (_recording) MaterialBanner(content:const Text('Recording voice note (max 15 seconds)'),actions:[
            TextButton(onPressed:()=>_finishVoiceNote(cancel:true),child:const Text('Discard')),
            FilledButton(onPressed:_finishVoiceNote,child:const Text('Send voice note'))]),
          if (_isUploadingImage)
            const LinearProgressIndicator(color: Color(0xFF6C63FF), minHeight: 3),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visibleMessages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.favorite_rounded, size: 40, color: Color(0xFF6C63FF)),
                            ),
                            const SizedBox(height: 12),
                            Text('You matched with ${widget.otherUserName}!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Say hi or share a photo to start talking.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, index) {
                          final msg = visibleMessages[index];
                          final isMe = msg['sender_id'] == myId;
                          final messageId = msg['id'].toString();
                          final reactions = <String, int>{};
                          for (final entry in _reactions.where((r) => r['message_id'] == messageId)) {
                            final reaction = entry['reaction'] as String;
                            reactions.update(reaction, (count) => count + 1, ifAbsent: () => 1);
                          }
                          final isRead = msg['read_at'] != null;
                          final imageUrl = msg['image_url'] as String?;
                          final text = msg['message'] ?? '';
                          final time = DateTime.tryParse(msg['created_at'] ?? '')?.toLocal();
                          final formattedTime = time != null ? DateFormat('hh:mm a').format(time) : '';

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _showMessageOptions(msg),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
                                decoration: BoxDecoration(
                                  color: isMe ? _chatTheme.outgoing : _chatTheme.incoming,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                                    bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                                        FutureBuilder<String>(
                                          future: _getChatImageUrl(imageUrl),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasError) {
                                              return const Text('Image unavailable');
                                            }
                                            if (!snapshot.hasData) {
                                              return const SizedBox(
                                                height: 140,
                                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                              );
                                            }
                                            final signedUrl = snapshot.data!;
                                            return GestureDetector(
                                              onTap: () => _showFullScreenImage(signedUrl),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: Image.network(signedUrl, fit: BoxFit.cover),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 6),
                                      ],

                                      if (msg['attachment_path'] != null)
                                        InkWell(
                                          onTap:()=>_openAttachment(
                                            msg['attachment_path'].toString(),
                                            voice:msg['attachment_type']=='voice',
                                            id:msg['id'].toString()),
                                          child: Padding(padding:const EdgeInsets.all(5),
                                            child:Row(mainAxisSize:MainAxisSize.min,children:[
                                              Icon(msg['attachment_type']=='voice'
                                                ? (_playingMessage==msg['id']?Icons.stop_circle:Icons.play_circle_fill)
                                                : Icons.insert_drive_file,
                                                color:isMe?_chatTheme.outgoingText:_chatTheme.accent),
                                              const SizedBox(width:7),
                                              Flexible(child:Text(
                                                msg['attachment_name']?.toString() ?? 'Attachment',
                                                overflow:TextOverflow.ellipsis,
                                                style:TextStyle(color:isMe?_chatTheme.outgoingText:_chatTheme.text))),
                                            ]))),
                                      if (text.isNotEmpty && text != '📷 Photo' &&
                                          msg['attachment_path'] == null)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              color: isMe ? _chatTheme.outgoingText : _chatTheme.text,
                                              fontSize: 15,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),

                                      if (reactions.isNotEmpty)
                                        Wrap(spacing: 4, children: [
                                          for (final entry in reactions.entries)
                                            ActionChip(
                                              label: Text('${entry.key} ${entry.value}'),
                                              onPressed: () => _pickReaction(messageId),
                                            ),
                                        ]),
                                      const SizedBox(height: 3),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            formattedTime,
                                            style: TextStyle(
                                              color: isMe ? _chatTheme.outgoingText.withOpacity(.72) : _chatTheme.secondaryText,
                                              fontSize: 10,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'React to message',
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                            padding: EdgeInsets.zero,
                                            icon: Icon(Icons.add_reaction_outlined, size: 16,
                                              color: isMe ? _chatTheme.outgoingText : _chatTheme.secondaryText),
                                            onPressed: () => _pickReaction(messageId),
                                          ),
                                          if (isMe) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              isRead ? Icons.done_all_rounded : Icons.done_rounded,
                                              size: 14,
                                              color: isRead ? _chatTheme.accent : _chatTheme.outgoingText.withOpacity(.72),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          if (_showEmojiTray)
            Container(
              height: 52,
              color: _chatTheme.composer,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickEmojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (ctx, idx) {
                  final em = _quickEmojis[idx];
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      _messageController.text += em;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text(em, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _chatTheme.composer,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showEmojiTray ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                      color: _chatTheme.accent,
                    ),
                    onPressed: () => setState(() => _showEmojiTray = !_showEmojiTray),
                  ),

                  IconButton(
                    icon: Icon(Icons.attach_file,color:_chatTheme.accent),
                    tooltip: 'Attach document (under 1 MB)',
                    onPressed: _isUploadingImage ? null : _pickAttachment,
                  ),
                  IconButton(
                    icon: Icon(Icons.photo_camera_rounded,color:_chatTheme.accent),
                    tooltip: 'Send Photo',
                    onPressed: _pickAndSendPhoto,
                  ),

                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style:TextStyle(color:_chatTheme.text),
                      decoration: InputDecoration(
                        hintText: 'Message...',hintStyle:TextStyle(color:_chatTheme.secondaryText),
                        fillColor:_chatTheme.composer,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),

                  IconButton(
                    tooltip: _recording ? 'Send voice note' : 'Record voice note',
                    icon: Icon(_recording ? Icons.stop_circle : Icons.mic,
                      color:_chatTheme.accent),
                    onPressed: _recording ? _finishVoiceNote : _startVoiceNote,
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color:_chatTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send_rounded,color:_chatTheme.background,size:20),
                      onPressed: () => _sendMessage(),
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
}







class _CallHistorySheet extends StatefulWidget {
  const _CallHistorySheet({required this.conversationId});

  final String conversationId;

  @override
  State<_CallHistorySheet> createState() => _CallHistorySheetState();
}

class _CallHistorySheetState extends State<_CallHistorySheet> {
  static const _pageSize = 30;
  final _client = Supabase.instance.client;
  final _calls = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await _client.from('calls')
          .select('id,caller_id,call_type,status,created_at,answered_at,ended_at,end_reason')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(_calls.length, _calls.length + _pageSize - 1);
      if (mounted) setState(() {
        _calls.addAll(rows);
        _hasMore = rows.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser?.id;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .65,
        child: Column(children: [
          Text('Call history', style: Theme.of(context).textTheme.titleLarge),
          Expanded(child: ListView.builder(
            itemCount: _calls.length + 1,
            itemBuilder: (context, index) {
              if (index == _calls.length) {
                if (_loading) return const Center(child: CircularProgressIndicator());
                if (_failed || _hasMore) return TextButton(
                  onPressed: _load,
                  child: Text(_failed ? 'Retry loading calls' : 'Load older calls'),
                );
                return _calls.isEmpty
                    ? const Center(child: Text('No calls yet'))
                    : const SizedBox.shrink();
              }
              final call = _calls[index];
              final video = call['call_type'] == 'video';
              final outgoing = call['caller_id'] == user;
              final created = DateTime.tryParse(call['created_at'] as String)?.toLocal();
              final answered = DateTime.tryParse(call['answered_at']?.toString() ?? '');
              final ended = DateTime.tryParse(call['ended_at']?.toString() ?? '');
              final duration = answered != null && ended != null
                  ? ended.difference(answered) : null;
              final outcome = switch (call['end_reason'] ?? call['status']) {
                'missed' => 'Missed',
                'cancelled' => 'Cancelled',
                'failed' => 'Connection failed',
                'completed' => 'Completed',
                'declined' => 'Declined',
                'ringing' => created != null &&
                    DateTime.now().difference(created).inSeconds >= 30
                    ? 'Outcome unavailable' : 'Ringing',
                'accepted' => 'Accepted',
                _ => 'Ended',
              };
              final timestamp = created == null ? '' : DateFormat.yMMMd().add_jm().format(created);
              final elapsed = duration == null || duration.isNegative ? '' :
                  ' · ${duration.inMinutes}m ${duration.inSeconds % 60}s';
              return ListTile(
                leading: Icon(video ? Icons.videocam_outlined : Icons.call_outlined),
                title: Text('${outgoing ? 'Outgoing' : 'Incoming'} ${video ? 'video' : 'audio'} call'),
                subtitle: Text('$outcome · $timestamp$elapsed'),
              );
            },
          )),
        ]),
      ),
    );
  }
}
