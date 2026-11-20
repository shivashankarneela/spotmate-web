import 'package:flutter/material.dart';
class ChatComposer extends StatelessWidget {
  const ChatComposer({super.key,required this.controller,required this.expressions,required this.sendMessage,required this.record,required this.busy,required this.accent,this.onChanged,this.attachment,this.maxLength});
  final TextEditingController controller;
  final VoidCallback expressions,sendMessage,record;
  final bool busy;
  final Color accent;
  final ValueChanged<String>? onChanged;
  final Widget? attachment;
  final int? maxLength;
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(children: [
              Expanded(child: DecoratedBox(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD6E3DE))),
                child: Row(children: [
                  IconButton(tooltip: 'Emoji, GIFs and stickers', visualDensity: VisualDensity.compact, onLongPress: busy ? null : expressions, onPressed: busy ? null : expressions, icon: const Icon(Icons.emoji_emotions_outlined,size:21)),
                  Expanded(child: TextField(controller: controller, onChanged: onChanged,
                    minLines: 1, maxLines: 3, maxLength: maxLength, textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Message',counterText: '',isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 9), border: InputBorder.none,
                      enabledBorder: InputBorder.none,focusedBorder: InputBorder.none),
                    onSubmitted: (_) { if (!busy) sendMessage(); })),
                  if (attachment != null) attachment!,
                ]),
              )),
              const SizedBox(width: 4),
              ValueListenableBuilder<TextEditingValue>(valueListenable: controller,
                builder: (_, value, child) {
                  final send = value.text.trim().isNotEmpty;
                  return IconButton.filled(tooltip: send ? 'Send message' : 'Record voice note',
                    style: IconButton.styleFrom(backgroundColor: accent,foregroundColor: Colors.white),
                    onPressed: busy ? null : send ? sendMessage : record,
                    icon: Icon(send ? Icons.send_rounded : Icons.mic_none));
                }),
            ]),
          ));
}
