import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum Role { user, bot }

enum Language { english, spanish }

class ChatMessage {
  final String id;
  final Role role;
  final String text;
  final DateTime createdAt;

  ChatMessage({required this.id, required this.role, required this.text, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();
}

class ApiService {
  ApiService._();
  static final instance = ApiService._();

  /// Point this to your FastAPI/Flask host. For emulator or physical device testing,
  /// use a reachable URL (e.g., http://10.0.2.2:8000 for Android emulator).
  String baseUrl = const String.fromEnvironment('WATERBOT_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// The website routes used EN: '/', ES: '/spanish'. We mimic this by setting a path prefix.
  String get langPrefix => _language == Language.english ? '' : '/spanish';
  Language _language = Language.english;

  void setLanguage(Language lang) => _language = lang;

  Future<({String resp, String msgID})?> chat(String userQuery) async {
    final uri = Uri.parse('$baseUrl$langPrefix/chat_api');
    final req = http.MultipartRequest('POST', uri)
      ..fields['user_query'] = userQuery;
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode ~/ 100 == 2) {
      final jsonMap = json.decode(body) as Map<String, dynamic>;
      return (resp: jsonMap['resp'] as String, msgID: jsonMap['msgID'].toString());
    }
    return null;
  }

  Future<bool> submitReaction({required String messageId, required int reaction, String? comment}) async {
    final uri = Uri.parse('$baseUrl/submit_rating_api');
    final resp = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: {
      'reaction': reaction.toString(),
      'message_id': messageId,
      if (comment != null && comment.isNotEmpty) 'userComment': comment,
    });
    return resp.statusCode ~/ 100 == 2;
  }

  Future<String?> fetchTranscriptUrl() async {
    final uri = Uri.parse('$baseUrl/session-transcript');
    final resp = await http.post(uri, headers: {"Accept": "application/json"});
    if (resp.statusCode ~/ 100 == 2) {
      try {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['presigned_url'] as String?;
      } catch (_) {}
    }
    return null;
  }
}
class ChatModel extends ChangeNotifier {
  final _api = ApiService.instance;
  final List<ChatMessage> messages = [];
  bool isTyping = false;

  void setLanguage(Language lang) {
    _api.setLanguage(lang);
    notifyListeners();
  }

  Future<void> send(String text) async {
    messages.add(ChatMessage(id: UniqueKey().toString(), role: Role.user, text: text));
    isTyping = true;
    notifyListeners();

    final res = await _api.chat(text);

    if (res != null) {
      messages.add(ChatMessage(id: res.msgID, role: Role.bot, text: res.resp));
    } else {
      messages.add(ChatMessage(id: UniqueKey().toString(), role: Role.bot, text: 'Sorry, something went wrong.'));
    }

    isTyping = false;
    notifyListeners();
  }

  Future<void> react(String messageId, int reaction, {String? comment}) async {
    await _api.submitReaction(messageId: messageId, reaction: reaction, comment: comment);
  }
}