import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_config.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:pasteboard/pasteboard.dart';

const double _kIconSize = 72;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _kAccentColor = MyTheme.accent;
const Duration _kPollInterval = Duration(seconds: 3);
const Duration _kRequestTimeout = Duration(seconds: 10);

// Colors of the light client widget, copied from showcase/client-widget.html
// (`.chat-msg-row`, `.msg-bubble`, `.chat-input-row`). Used only when the page
// renders inside the docked widget (`widgetLight`); the Tools Window keeps the
// app theme.
const Color _kwText = Color(0xFF1C1C1C);
const Color _kwMuted = Color(0xFF5C5C5C);
const Color _kwSubtle = Color(0xFF8A8A8A);
const Color _kwBorder = Color(0x12000000); // rgba(0,0,0,.07)
const Color _kwBorderStrong = Color(0x24000000); // rgba(0,0,0,.14)
const Color _kwBlue = Color(0xFF0284C7);
const Color _kwBlueDark = Color(0xFF0369A1);
const Color _kwBlueLight = Color(0x140284C7);
const Color _kwOrange = Color(0xFFF97316);
const Color _kwOrangeLight = Color(0x1AF97316);

// One chat entry shown as a bubble. Sender is 'user', 'bot' or 'admin'
// (local messages use 'user', polled Manager messages use the server value).
// The timestamp is captured locally when the message shows up; it is a
// display-only hint (the polled API result does not carry one).
class _ChatMessage {
  final String sender;
  final String text;
  final DateTime time;
  _ChatMessage(this.sender, this.text) : time = DateTime.now();
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
  final bool embedded;

  /// Render the light `client-widget.html` chat inside the docked widget
  /// instead of the themed page used by the Tools Window.
  final bool widgetLight;

  const AiChatPage({Key? key, this.embedded = false, this.widgetLight = false})
      : super(key: key);

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
  // True between a successfully posted user message and the first reply
  // picked up by the poll; drives the "typing" indicator bubble.
  bool _waitingReply = false;
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
          if (incoming.isNotEmpty) {
            _waitingReply = false;
          }
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
    final request =
        await _client.openUrl(method, url).timeout(_kRequestTimeout);
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
      // Wait for the reply from now on; the poll below clears the flag as
      // soon as the first Bot/Admin message arrives.
      _waitingReply = true;
      // Poll right away so replies do not wait for the next 3s tick.
      await _poll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _waitingReply = false;
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

  /// Pick an image, upload it to the Manager (X-Device-Token), then send a
  /// chat message carrying the download link. Real upload, no local-only copy.
  Future<void> _uploadAndSendAttachment() async {
    if (_sending) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) {
      return;
    }
    final file = result.files.single;
    final token = bind.mainGetLocalOption(key: 'manager-device-token');
    if (token.isEmpty) {
      setState(() {
        _error =
            'Thiếu manager-device-token: cần client mới đăng ký lại Manager';
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    _messages.add(_ChatMessage('user', '📷 ${file.name}'));
    setState(() {});
    try {
      final bytes = await File(file.path!).readAsBytes();
      final uri = Uri.parse('$kApiBase/client/attach')
          .replace(queryParameters: {'name': file.name});
      final req = await _client.postUrl(uri);
      req.headers.set('X-Device-Token', token);
      req.headers.set('Content-Type', 'application/octet-stream');
      req.add(bytes);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw 'upload HTTP ${resp.statusCode}: $body';
      }
      final url = ((jsonDecode(body) as Map)['url'] ?? '').toString();
      final text = '📎 ${file.name}\n$url';
      final conversationId = await _ensureConversation();
      await _postMessage(conversationId, text);
      _messages.add(_ChatMessage('user', text));
      _waitingReply = true;
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

  /// Upload bytes to the Manager attachment API, return the download URL.
  /// Both the attach button and the Ctrl+V paste flow go through this.
  Future<String> _uploadBytes(Uint8List bytes, String name) async {
    final token = bind.mainGetLocalOption(key: 'manager-device-token');
    if (token.isEmpty) {
      throw 'Thiếu manager-device-token: cần client mới đăng ký lại Manager';
    }
    final uri = Uri.parse('$kApiBase/client/attach')
        .replace(queryParameters: {'name': name});
    final request = await _client.postUrl(uri).timeout(_kRequestTimeout);
    request.headers.set('X-Device-Token', token);
    request.headers.contentType = ContentType.binary;
    request.add(bytes);
    final response = await request.close().timeout(_kRequestTimeout);
    final text =
        await response.transform(utf8.decoder).join().timeout(_kRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $text', uri: uri);
    }
    final data = text.isEmpty ? null : jsonDecode(text);
    final url = data is Map ? '${data['url'] ?? ''}' : '';
    if (url.isEmpty) {
      throw const FormatException('không có url trong phản hồi upload');
    }
    return url;
  }

  /// Ctrl+V paste flow: read the image bytes from the clipboard and upload
  /// them as an attachment. Falls back to normal paste when the clipboard
  /// holds no image (handled by the TextField itself).
  Future<void> _pasteImageOrText() async {
    final image = await Pasteboard.image;
    if (image == null || image.isEmpty) {
      return; // no image on clipboard: let the Flutter paste continue
    }
    final name = 'clipboard-${DateTime.now().millisecondsSinceEpoch}.png';
    final url = await _uploadBytes(image, name);
    final text = '📷 $name\n$url';
    _messages.add(_ChatMessage('user', text));
    setState(() {});
    try {
      final conversationId = await _ensureConversation();
      await _postMessage(conversationId, text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
        });
      }
    }
  }

  /// Attach button flow: pick an image file and upload it.
  Future<void> _pickAndSendAttachment() async {
    if (_sending) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) {
      return;
    }
    final file = result.files.single;
    final bytes = await File(file.path!).readAsBytes();
    final token = bind.mainGetLocalOption(key: 'manager-device-token');
    if (token.isEmpty) {
      setState(() {
        _error =
            'Thiếu manager-device-token: cần client mới đăng ký lại Manager';
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    _messages.add(_ChatMessage('user', '📷 ${file.name}'));
    setState(() {});
    try {
      final url =
          await _uploadBytes(bytes, file.name).timeout(_kRequestTimeout);
      final text = '📷 ${file.name}\n$url';
      final conversationId = await _ensureConversation();
      await _postMessage(conversationId, text);
      _messages.add(_ChatMessage('user', text));
      _waitingReply = true;
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

  /// Ctrl+V flow body: upload the clipboard image via the Manager attach API
  /// and send the link as a message. No-op when the clipboard holds no image.
  Future<void> _pasteImageOrTextUpload() async {
    if (_sending) return;
    final image = await Pasteboard.image;
    if (image == null || image.isEmpty) return;
    final name = 'clipboard-${DateTime.now().millisecondsSinceEpoch}.png';
    _sending = true;
    _messages.add(_ChatMessage('user', '📷 $name'));
    if (mounted) setState(() {});
    try {
      final url = await _uploadBytes(image, name).timeout(_kRequestTimeout);
      final text = '📷 $name\n$url';
      final conversationId = await _ensureConversation();
      await _postMessage(conversationId, text);
      _messages.add(_ChatMessage('user', text));
      _waitingReply = true;
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
    if (widget.widgetLight) {
      return Column(
        children: [
          Expanded(child: _lightMessageList()),
          if (_error != null) _lightErrorBanner(),
          _lightInputRow(),
        ],
      );
    }
    return Scaffold(
      // Embedded in the docked widget: the host window already draws the
      // header, so the page must not add another app bar.
      appBar: widget.embedded
          ? null
          : AppBar(
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

  // Clipped to the widget card: white incoming bubbles with a 3px top-left
  // corner, blue-gradient outgoing bubbles (client-widget.html .msg-bubble).
  Widget _lightMessageList() {
    final showWelcome = _messages.isEmpty && !_waitingReply;
    if (showWelcome) {
      // The mockup pins the welcome bubble to the top of the message area.
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        children: [_lightWelcomeBubble()],
      );
    }
    final itemCount = _messages.length + (_waitingReply ? 1 : 0);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_waitingReply && index == 0) return _lightTypingBubble();
        final messageIndex =
            _messages.length - 1 - (index - (_waitingReply ? 1 : 0));
        return _lightBubble(_messages[messageIndex]);
      },
    );
  }

  Widget _lightWelcomeBubble() {
    return _lightBubble(_ChatMessage(
      'admin',
      'Chào bạn! Nhập tin nhắn gửi tới Admin IT để được hỗ trợ từ xa.\n'
          'Có thể nhấn Ctrl+V để dán ảnh chụp màn hình lỗi trực tiếp.',
    ));
  }

  Widget _lightAvatar({required bool user}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: user ? _kwOrangeLight : _kwBlueLight,
        shape: BoxShape.circle,
      ),
      child: Icon(
        user ? Icons.person_outline : Icons.support_agent,
        size: 13,
        color: user ? _kwOrange : _kwBlue,
      ),
    );
  }

  Widget _lightBubble(_ChatMessage message) {
    final isUser = message.sender.toLowerCase() == 'user';
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                colors: [_kwBlue, _kwBlueDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUser ? null : Colors.white,
        border: isUser ? null : Border.all(color: _kwBorder),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isUser ? 12 : 3),
          topRight: Radius.circular(isUser ? 3 : 12),
          bottomLeft: const Radius.circular(12),
          bottomRight: const Radius.circular(12),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SelectableText(
        message.text,
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: isUser ? Colors.white : _kwText,
        ),
      ),
    );
    final meta = Padding(
      padding: const EdgeInsets.only(top: 3, left: 2, right: 2),
      child: Text(
        '${_formatTime(message.time)} · '
        '${isUser ? 'Bạn' : _senderLabel(message.sender)}',
        style: const TextStyle(fontSize: 9.5, color: _kwSubtle),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) _lightAvatar(user: false),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.86,
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [bubble, meta],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _lightAvatar(user: true),
        ],
      ),
    );
  }

  Widget _lightTypingBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lightAvatar(user: false),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _kwBorder),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kwBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lightErrorBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0x1AF87171),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        _error!,
        style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626)),
      ),
    );
  }

  /// `.chat-input-row` capsule of the mockup: attach · input · blue send.
  Widget _lightInputRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _kwBorderStrong),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _sending ? null : _uploadAndSendAttachment,
              tooltip: translate('Attach image'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              icon: const Icon(Icons.attach_file, size: 15, color: _kwMuted),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Focus(
                // Ctrl+V: upload a pasted screenshot via the Manager attach
                // API; text paste falls through untouched.
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.keyV &&
                      HardwareKeyboard.instance.isControlPressed) {
                    unawaited(_pasteImageOrTextUpload());
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 3,
                  cursorColor: _kwBlue,
                  style: const TextStyle(fontSize: 12, color: _kwText),
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Nhập nội dung yêu cầu... (Ctrl+V dán ảnh/video)',
                    hintStyle: TextStyle(fontSize: 12, color: _kwMuted),
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _sending
                ? const Padding(
                    padding: EdgeInsets.all(4),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kwBlue),
                    ),
                  )
                : InkWell(
                    onTap: _send,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_kwBlue, _kwBlueDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x400284C7),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child:
                          const Icon(Icons.send, size: 13, color: Colors.white),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // Reversed list so the newest message (and the typing indicator) stays at
  // the bottom.
  Widget _messageList() {
    if (_messages.isEmpty && !_waitingReply) {
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
            const SizedBox(height: 4),
            Text(
              translate('Chat with the AI bot or admin via the Manager'),
              style: TextStyle(
                fontSize: _kContentFontSize - 2,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      );
    }
    final itemCount = _messages.length + (_waitingReply ? 1 : 0);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(15),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_waitingReply && index == 0) {
          return _typingBubble();
        }
        final messageIndex =
            _messages.length - 1 - (index - (_waitingReply ? 1 : 0));
        return _bubble(_messages[messageIndex]);
      },
    );
  }

  Widget _bubble(_ChatMessage message) {
    final isUser = message.sender.toLowerCase() == 'user';
    final isBot = message.sender.toLowerCase() == 'bot';
    return isUser ? _userBubble(message) : _botBubble(message, isBot);
  }

  Widget _userBubble(_ChatMessage message) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: const BoxDecoration(
            color: _kAccentColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                message.text,
                style: const TextStyle(
                  fontSize: _kContentFontSize,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(message.time),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botBubble(_ChatMessage message, bool isBot) {
    final badgeColor = isBot ? _kAccentColor : Colors.blueGrey;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: badgeColor.withOpacity(0.15),
              child: Icon(
                isBot
                    ? Icons.smart_toy_outlined
                    : Icons.admin_panel_settings_outlined,
                size: 16,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Sender badge; the Bot badge uses the accent color.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _senderLabel(message.sender),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(message.time),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      message.text,
                      style: TextStyle(
                        fontSize: _kContentFontSize,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Left-aligned bot bubble with a spinner shown while waiting for a reply.
  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _kAccentColor.withOpacity(0.15),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: _kAccentColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
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

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

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
          IconButton(
            onPressed: _sending ? null : _uploadAndSendAttachment,
            tooltip: translate('Attach image'),
            icon: const Icon(Icons.attach_file, size: 20),
          ),
          Expanded(
            child: Focus(
              // Ctrl+V: upload a pasted screenshot via the Manager attach API.
              // When the clipboard holds no image the event is ignored and the
              // normal text paste proceeds.
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.keyV &&
                    HardwareKeyboard.instance.isControlPressed) {
                  unawaited(_pasteImageOrTextUpload());
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                enabled: !_sending,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: translate('Type a message'),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.4),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
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
                  // Filled circular send button to match the bubble accent.
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kAccentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  tooltip: translate('Send'),
                ),
        ],
      ),
    );
  }
}
