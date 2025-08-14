import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const WaterBotApp());
}

class WaterBotApp extends StatelessWidget {
  const WaterBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatModel()),
      ],
      child: MaterialApp(
        title: 'Arizona Water Chatbot',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8C1D40),
            primary: const Color(0xFF8C1D40),
            secondary: const Color(0xFFFFC627),
          ),
          useMaterial3: true,
        ),
        home: ChatScreen(),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Language _lang = Language.english;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arizona Water Chatbot'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: SegmentedButton<Language>(
              segments: const [
                ButtonSegment(value: Language.english, label: Text('ENGLISH')),
                ButtonSegment(value: Language.spanish, label: Text('ESPAÑOL')),
              ],
              selected: {_lang},
              onSelectionChanged: (s) async {
                setState(() => _lang = s.first);
                chat.setLanguage(_lang);
                // If your backend expects routes "/" vs "/spanish", ApiService will read it.
              },
            ),
          ),
          IconButton(
            tooltip: 'Download Transcript',
            icon: const Icon(Icons.download),
            onPressed: () async {
              final url = await ApiService.instance.fetchTranscriptUrl();
              if (url == null) return;
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: chat.messages.length,
              itemBuilder: (context, index) {
                final m = chat.messages[index];
                return MessageBubble(message: m);
              },
            ),
          ),
          if (chat.isTyping) const TypingIndicator(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: 'Type your question here',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF8C1D40),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final chat = context.read<ChatModel>();
    _controller.clear();
    _focusNode.requestFocus();

    await chat.send(text);

    // scroll to bottom
    await Future.delayed(const Duration(milliseconds: 100));
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }
}
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == Role.user;
    final bg = isUser
        ? const LinearGradient(colors: [Color(0xFF2B79C2), Color(0xFF215F9C), Color(0xFF184B79)])
        : const LinearGradient(colors: [Color(0xFFEEEEEE), Color(0xFFEEEEEE)]);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(isUser ? 4 : 12),
      bottomRight: Radius.circular(isUser ? 12 : 4),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _Drop(size: 20, asset: 'assets/images/WaterDrop1.png'),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                gradient: bg,
                color: isUser ? null : const Color(0xFFEEEEEE),
                borderRadius: radius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: isUser
                  ? Text(
                message.text,
                style: const TextStyle(color: Colors.white),
              )
                  : MarkdownBody(
                data: message.text,
                onTapLink: (t, href, title) async {
                  if (href == null) return;
                  final uri = Uri.parse(href);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _Reactions(message: message),
        ],
      ),
    );
  }
}
class _Reactions extends StatelessWidget {
  const _Reactions({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatModel>();
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF8C1D40)),
          ),
          onPressed: () => chat.react(message.id, 1),
          icon: const Icon(Icons.thumb_up, color: Color(0xFF8C1D40)),
        ),
        const SizedBox(width: 4),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF8C1D40)),
          ),
          onPressed: () async {
            final reason = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => _FeedbackSheet(),
            );
            chat.react(message.id, 0, comment: reason);
          },
          icon: const Icon(Icons.thumb_down, color: Color(0xFF8C1D40)),
        ),
      ],
    );
  }
}
class _FeedbackSheet extends StatefulWidget {
  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  String? selected;
  final controller = TextEditingController();
  final options = const ['Factually incorrect', 'Generic response', 'Refused to answer', 'Other'];
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: options
                .map((o) => ChoiceChip(
              label: Text(o),
              selected: selected == o,
              onSelected: (v) => setState(() => selected = o),
              color: WidgetStateProperty.resolveWith((states) => Colors.amber.shade400),
            ))
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Provide additional feedback',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, [selected, controller.text].where((e) => (e ?? '').isNotEmpty).join(', ')),
              child: const Text('Submit'),
            ),
          )
        ],
      ),
    );
  }
}
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Dot(),
          SizedBox(width: 4),
          _Dot(delay: 150),
          SizedBox(width: 4),
          _Dot(delay: 300),
        ],
      ),
    );
  }
}
class _Dot extends StatefulWidget {
  const _Dot({this.delay = 0});
  final int delay;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () => _c.repeat(reverse: true));
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.7, end: 1.0).animate(_c),
      child: const CircleAvatar(radius: 4, backgroundColor: Color(0xFF8C1D40)),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

class _Drop extends StatelessWidget {
  const _Drop({required this.size, required this.asset});
  final double size;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(asset, height: size);
  }
}