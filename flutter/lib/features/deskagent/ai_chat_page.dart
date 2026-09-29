import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_config.dart';

const double _kIconSize = 72;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _kAccentColor = MyTheme.accent;
const Duration _kPollInterval = Duration(seconds: 3);
const Duration _kRequestTimeout = Duration(seconds: 10);

// One chat entry shown as a bubble. Sender is 'user', 'bot' or 'admin'
// (local messages use 'user', polled Manager messages use the server value).
class _ChatMessage {
  final String sender;
  final String text;
  _ChatMessage(this.sender, this.text);
}

// AI chat page for DeskAgent: talks to the local Manager REST API with the
// bare dart:io HttpClient (no extra pub dependency).
//
// Flow: the first sent message creates a conversation via
// POST kApiBase/conversations, subsequent messages go to
// POST kApiBase/conversations/{id}/messages with {"text": ...}, and a 3s
// poll on GET kApiBase/conversations/{id}/messages?after={lastId} picks up
// Bot/Admin replies.
class AiChatPage extends StatefulWidget {
  const AiChatPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final HttpClient _client = HttpClient();
  final TextEditingController _controller = TextEditingController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  Timer? _pollTimer;
  String? _conversationId;
  String _lastMessageId = '';
  bool _sending = false;
  bool _polling = false;
  String? _error;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client.close();
    _controller.dispose();
    super.dispose();
  }

  // POST kApiBase/conversations on first use, then reuse the returned id.
  Future<String> _ensureConversation() async {
    if (_conversationId != null) {
      return _conversationId!;
    }
    final data = await _requestJson(
        'POST', Uri.parse('$kApiBase/conversations'),
        body: '{}');
    final id = data is Map ? (data['id'] ?? data['conversation_id']) : null;
    if (id == null) {
      throw const FormatException('no conversation id in Manager response');
    }
    _conversationId = '$id';
    _startPolling();
    return _conversationId!;
  }

  // POST kApiBase/conversations/{id}/messages with {"text": ...}.
  Future<void> _postMessage(String conversationId, String text) async {
    await _requestJson(
      'POST',
      Uri.parse('$kApiBase/conversations/$conversationId/messages'),
      body: jsonEncode({'text': text}),
    );
  }

  // GET kApiBase/conversations/{id}/messages?after={lastId}: appends new
  // Bot/Admin messages and advances the cursor past everything returned.
  Future<void> _poll() async {
    final conversationId = _conversationId;
    if (conversationId == null || _polling) {
      return;
    }
    _polling = true;
    try {
      final data = await _requestJson(
        'GET',
        Uri.parse(
            '$kApiBase/conversations/$conversationId/messages?after=$_lastMessageId'),
      );
      if (data is List && mounted) {
        final incoming = <_ChatMessage>[];
        for (final m in data) {
          if (m is Map) {
            final sender =
                '${m['sender'] ?? m['role'] ?? ''}'.trim().toLowerCase();
            // Local user messages are already shown when sent.
            if (sender.isNotEmpty && sender != 'user') {
              incoming.add(_ChatMessage(
                sender,
                '${m['text'] ?? m['reply'] ?? m['content'] ?? ''}',
              ));
            }
            final id = m['id'];
            if (id != null) {
              _lastMessageId = '$id';
            }
          }
        }
        setState(() {
          _messages.addAll(incoming);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
        });
      }
    } finally {
      _polling = false;
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(_kPollInterval, (_) => _poll());
  }

  // Minimal JSON request helper on top of dart:io HttpClient.
  Future<dynamic> _requestJson(String method, Uri url, {String? body}) async {
    final request = await _client.openUrl(method, url).timeout(_kRequestTimeout);
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(body);
    }
    final response = await request.close().timeout(_kRequestTimeout);
    final text =
        await response.transform(utf8.decoder).join().timeout(_kRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $text', uri: url);
    }
    if (text.isEmpty) {
      return null;
    }
    return jsonDecode(text);
  }

  String _friendlyError(Object e) {
    if (e is SocketException || e is TimeoutException) {
      return 'Cannot reach the Manager at $kManagerUrl. '
          'Please make sure the DeskAgent Manager is running.';
    }
    return e.toString();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    _messages.add(_ChatMessage('user', text));
    _controller.clear();
    setState(() {});
    try {
      final conversationId = await _ensureConversation();
      await _postMessage(conversationId, text);
      // Poll right away so replies do not wait for the next 3s tick.
      await _poll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('AI Chat')),
      ),
      body: Column(
        children: [
          Expanded(child: _messageList()),
          if (_error != null) _errorBanner(),
          const Divider(height: 1),
          _inputRow(),
        ],
      ),
    );
  }

  // Reversed list so the newest message stays at the bottom.
  Widget _messageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_outlined,
              size: _kIconSize,
              color: _kAccentColor,
            ),
            const SizedBox(height: 8),
            Text(
              translate('No messages yet'),
              style: TextStyle(fontSize: _kTitleFontSize),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(15),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[_messages.length - 1 - index];
        return _bubble(message);
      },
    );
  }

  Widget _bubble(_ChatMessage message) {
    final isUser = message.sender.toLowerCase() == 'user';
    final isBot = message.sender.toLowerCase() == 'bot';
    final bubbleColor =
        isUser ? _kAccentColor : Theme.of(context).colorScheme.surfaceVariant;
    final textColor =
        isUser ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sender badge; the Bot badge uses the accent color.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isBot
                      ? _kAccentColor
                      : (isUser ? Colors.white24 : Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _senderLabel(message.sender),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                message.text,
                style: TextStyle(fontSize: _kContentFontSize, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _senderLabel(String sender) {
    switch (sender.toLowerCase()) {
      case 'user':
        return 'User';
      case 'admin':
        return 'Admin';
      default:
        return 'Bot';
    }
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.withOpacity(0.15),
      padding: const EdgeInsets.all(8),
      child: Text(
        _error!,
        style: TextStyle(fontSize: _kContentFontSize, color: Colors.red),
      ),
    );
  }

  Widget _inputRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: translate('Type a message'),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          _sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  color: _kAccentColor,
                  tooltip: translate('Send'),
                ),
        ],
      ),
    );
  }
}
