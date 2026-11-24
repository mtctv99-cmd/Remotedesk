import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/features/deskagent/deskagent_tokens.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Verify Console credentials; discard returned bearer token immediately.
Future<bool> verifyConsolePassword(String username, String password) async {
  final apiServer = (await bind.mainGetApiServer()).trim();
  if (apiServer.isEmpty) {
    throw StateError(translate('Manager API URL is not configured'));
  }
  final uri =
      Uri.parse('${apiServer.replaceFirst(RegExp(r'/+$'), '')}/api/auth/login');
  final client = HttpClient();
  try {
    final request =
        await client.postUrl(uri).timeout(const Duration(seconds: 10));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode({
      'username': username.trim(),
      'password': password,
    })));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) return false;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}: $body', uri: uri);
    }
    final payload = jsonDecode(body);
    return payload is Map &&
        payload['token'] is String &&
        (payload['token'] as String).isNotEmpty;
  } finally {
    client.close(force: true);
  }
}

Future<bool> showConsoleAuthDialog(
  BuildContext context, {
  required String peerDescription,
  required Future<bool> Function(String username, String password) onAuthorize,
}) async {
  final username = TextEditingController();
  final password = TextEditingController();
  var busy = false;
  try {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => Dialog(
              backgroundColor: DeskAgentFluentColors.dialogSurface,
              elevation: 24,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(DeskAgentMetrics.radiusDialog),
                side: const BorderSide(color: DeskAgentFluentColors.border12),
              ),
              child: SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 16, color: DeskAgentFluentColors.accent),
                          const SizedBox(width: 8),
                          const Text(
                            'DeskAgent Console',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: DeskAgentFluentColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        translate('Verify remote session from {}')
                            .replaceFirst('{}', peerDescription),
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: DeskAgentFluentColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: username,
                        autofocus: true,
                        style: const TextStyle(
                            fontSize: 12,
                            color: DeskAgentFluentColors.textPrimary),
                        decoration:
                            _fieldDecoration(translate('Console account')),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: password,
                        obscureText: true,
                        style: const TextStyle(
                            fontSize: 12,
                            color: DeskAgentFluentColors.textPrimary),
                        decoration:
                            _fieldDecoration(translate('Console password')),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _dialogButton(
                            label: translate('Cancel'),
                            primary: false,
                            enabled: !busy,
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                          ),
                          const SizedBox(width: 8),
                          _dialogButton(
                            label: translate('Verify and accept'),
                            primary: true,
                            enabled: !busy,
                            child: busy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : null,
                            onPressed: () async {
                              if (username.text.trim().isEmpty ||
                                  password.text.isEmpty) {
                                showToast(translate(
                                    'Enter the console username and password'));
                                return;
                              }
                              setDialogState(() => busy = true);
                              try {
                                if (!await onAuthorize(
                                    username.text.trim(), password.text)) {
                                  showToast(translate(
                                      'Wrong console username or password'));
                                  if (dialogContext.mounted) {
                                    setDialogState(() => busy = false);
                                  }
                                  return;
                                }
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop(true);
                                }
                              } catch (e) {
                                showToast(
                                    '${translate('Could not reach the console')}: $e');
                                if (dialogContext.mounted) {
                                  setDialogState(() => busy = false);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ) ??
        false;
  } finally {
    username.dispose();
    password.dispose();
  }
}

InputDecoration _fieldDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          fontSize: 11.5, color: DeskAgentFluentColors.textSecondary),
      filled: true,
      fillColor: DeskAgentFluentColors.subtle,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
        borderSide: const BorderSide(color: DeskAgentFluentColors.border12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
        borderSide: const BorderSide(color: DeskAgentFluentColors.border12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
        borderSide: const BorderSide(color: DeskAgentFluentColors.accent),
      ),
    );

Widget _dialogButton({
  required String label,
  required bool primary,
  required bool enabled,
  required VoidCallback onPressed,
  Widget? child,
}) =>
    Material(
      color: primary
          ? DeskAgentFluentColors.accent
          : DeskAgentFluentColors.hoverOverlay,
      borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
        hoverColor: primary
            ? DeskAgentFluentColors.accentHover
            : DeskAgentFluentColors.activeOverlay,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
            border: primary
                ? null
                : Border.all(color: DeskAgentFluentColors.border12),
          ),
          child: child ??
              Text(
                label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: primary
                        ? const Color(0xFF0B0B0B)
                        : DeskAgentFluentColors.textPrimary),
              ),
        ),
      ),
    );
