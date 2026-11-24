import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart';
import 'active_call_screen.dart';

class CallSession {
  const CallSession({required this.id, required this.name, required this.isVideo,
    required this.isCaller, required this.media, this.photo});
  final String id;
  final String name;
  final String? photo;
  final bool isVideo;
  final bool isCaller;
  final MediaStream media;
}

class ActiveCallManager {
  static final session = ValueNotifier<CallSession?>(null);
  static final minimized = ValueNotifier<bool>(false);
  static bool start(CallSession call) {
    if (session.value != null) return false;
    minimized.value = false;
    session.value = call;
    return true;
  }
  static void minimize() { if (session.value != null) minimized.value = true; }
  static void restore() { if (session.value != null) minimized.value = false; }
  static void close(String id) {
    if (session.value?.id != id) return;
    session.value = null;
    minimized.value = false;
  }
}

class CallHost extends StatefulWidget {
  const CallHost({super.key, required this.child});
  final Widget child;
  @override
  State<CallHost> createState() => _CallHostState();
}

class _CallHostState extends State<CallHost> with WidgetsBindingObserver {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Future<bool> didPopRoute() async {
    if (ActiveCallManager.session.value != null && !ActiveCallManager.minimized.value) {
      ActiveCallManager.minimize();
      return true;
    }
    return false;
  }
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CallSession?>(
    valueListenable: ActiveCallManager.session,
    builder: (context, call, _) {
      if (call == null) return widget.child;
      return ValueListenableBuilder<bool>(
        valueListenable: ActiveCallManager.minimized,
        builder: (context, minimized, _) => Stack(fit: StackFit.expand, children: [
            widget.child,
            Offstage(offstage: minimized, child: ActiveCallScreen(
              key: ValueKey(call.id), callId: call.id, otherUserName: call.name,
              otherUserPhoto: call.photo, isVideo: call.isVideo, isCaller: call.isCaller,
              minimized: ActiveCallManager.minimized, media: call.media,
              onClosed: () => ActiveCallManager.close(call.id),
            )),
            if (minimized) Positioned(
              top: MediaQuery.paddingOf(context).top + 8, left: 12, right: 12,
              child: Material(color: const Color(0xFF075E54), elevation: 8,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(onTap: ActiveCallManager.restore,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.call, color: Colors.white, size: 21),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Ongoing call · ${call.name}', maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      const Text('Tap to return', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]))))),
          ]),
      );
    },
  );
}
