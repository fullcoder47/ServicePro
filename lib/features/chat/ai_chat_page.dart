import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/localized_text.dart';

/// Existing public widget name and constructor are intentionally unchanged.
/// Gemini API keys must stay in Supabase Edge Function Secrets, never here.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  static const _legacyStorageKey = 'servicepro_ai_chat_messages_v1';
  static const _storagePrefix = 'servicepro_ai_chat_messages_v2_';
  static const _welcomeText =
      'Salom! Men ServicePro AI yordamchisiman. App, ariza, chat, reklama, '
      'billing, biznes, marketing, telefon, kompyuter yoki kundalik savollar '
      'bo‘yicha yordam beraman.';
  static const _clearedText = 'Tarix tozalandi. Yangi savol bering.';
  static const _maxMessageLength = 3000; // Same limit as servicepro-ai.
  static const _maxSavedMessages = 80;

  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final List<_AiMessage> messages = <_AiMessage>[];

  StreamSubscription<AuthState>? _authSubscription;
  Future<void> _storageQueue = Future<void>.value();
  String? _activeUserId;
  String? _errorText;
  String? _retryPrompt;
  bool _loadingHistory = true;
  bool typing = false;
  int _loadGeneration = 0;
  int _requestGeneration = 0;

  String? get _storageKey => _activeUserId == null
      ? null
      : '$_storagePrefix$_activeUserId';

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
          (_) {
        final nextUserId = Supabase.instance.client.auth.currentUser?.id;
        if (nextUserId != _activeUserId) {
          _requestGeneration++;
          _loadHistory();
        }
      },
    );
    _loadHistory();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _requestGeneration++;
    _authSubscription?.cancel();
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final generation = ++_loadGeneration;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (mounted) {
      setState(() {
        _activeUserId = userId;
        _loadingHistory = true;
        typing = false;
        _errorText = null;
        _retryPrompt = null;
        messages.clear();
      });
    }

    final loaded = <_AiMessage>[];
    try {
      if (userId != null) {
        final prefs = await SharedPreferences.getInstance();
        final key = '$_storagePrefix$userId';
        var raw = prefs.getString(key);

        // One-time upgrade of the original single-device history format.
        // New messages are kept separately for each signed-in account.
        if (raw == null) {
          final oldRaw = prefs.getString(_legacyStorageKey);
          if (oldRaw != null && oldRaw.isNotEmpty) {
            raw = oldRaw;
            await prefs.setString(key, oldRaw);
            await prefs.remove(_legacyStorageKey);
          }
        }
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final entry in decoded) {
              if (entry is Map) {
                final message = _AiMessage.fromJson(entry);
                if (message.text.trim().isNotEmpty) loaded.add(message);
              }
            }
          }
        }
      }
    } catch (error) {
      debugPrint('ServicePro AI: history load failed: $error');
    }

    if (loaded.isEmpty) {
      loaded.add(const _AiMessage(
        text: _welcomeText,
        mine: false,
        includeInContext: false,
      ));
    }

    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      messages
        ..clear()
        ..addAll(loaded);
      _loadingHistory = false;
    });
    _scrollBottom(jump: true);
  }

  /// Serializes writes to avoid a slower write overwriting a newer message.
  void _saveHistory() {
    final key = _storageKey;
    if (key == null) return;
    final compact = messages.length > _maxSavedMessages
        ? messages.sublist(messages.length - _maxSavedMessages)
        : messages;
    final value = jsonEncode(compact.map((m) => m.toJson()).toList());
    _storageQueue = _storageQueue.then<void>((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }).catchError((Object error) {
      debugPrint('ServicePro AI: history save failed: $error');
    });
  }

  /// Only complete user/assistant exchanges are used as conversation context.
  /// Failed questions and the greeting are never sent back to Gemini.
  List<Map<String, String>> _buildHistory() {
    final history = <Map<String, String>>[];
    String? pendingUserText;
    for (final message in messages) {
      if (!message.includeInContext) continue;
      if (message.mine) {
        pendingUserText = message.text;
      } else if (pendingUserText != null) {
        history.add(<String, String>{'role': 'user', 'text': pendingUserText});
        history.add(<String, String>{'role': 'model', 'text': message.text});
        pendingUserText = null;
      }
    }
    // The Edge Function accepts the last 8 history entries.
    return history.length > 8
        ? history.sublist(history.length - 8)
        : history;
  }

  Future<void> _send({String? retryText}) async {
    if (_loadingHistory || typing) return;
    final text = (retryText ?? controller.text).trim();
    if (text.isEmpty) return;
    if (text.length > _maxMessageLength) {
      setState(() {
        _errorText = 'Savol $_maxMessageLength belgidan oshmasligi kerak.';
        _retryPrompt = null;
      });
      return;
    }

    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    if (session == null ||
        supabase.auth.currentUser?.id == null ||
        supabase.auth.currentUser?.id != _activeUserId) {
      setState(() {
        _errorText = 'AI yordamchidan foydalanish uchun hisobingizga qayta kiring.';
        _retryPrompt = null;
      });
      return;
    }

    final history = _buildHistory();
    final requestGeneration = ++_requestGeneration;
    setState(() {
      if (retryText == null ||
          messages.isEmpty ||
          !messages.last.mine ||
          messages.last.text != text) {
        messages.add(_AiMessage(text: text, mine: true));
      }
      if (retryText == null) controller.clear();
      _errorText = null;
      _retryPrompt = null;
      typing = true;
    });
    _saveHistory();
    _scrollBottom();

    try {
      // The official Supabase client provides the user's Authorization token.
      // GEMINI_API_KEY is read only by the servicepro-ai Edge Function.
      final response = await supabase.functions.invoke(
        'servicepro-ai',
        body: <String, Object>{
          'message': text,
          'history': history,
        },
      ).timeout(const Duration(seconds: 45));

      final body = response.data;
      final Map<dynamic, dynamic> data;
      if (body is Map) {
        data = body;
      } else if (body is String && body.isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is! Map) throw const FormatException('Unexpected AI response');
        data = decoded;
      } else {
        throw const FormatException('Empty AI response');
      }

      final reply = data['reply'];
      if (reply is! String || reply.trim().isEmpty) {
        throw const FormatException('Missing reply from AI');
      }
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        messages.add(_AiMessage(text: reply.trim(), mine: false));
        typing = false;
      });
      _saveHistory();
      _scrollBottom();
    } on TimeoutException {
      _showSendError(
        requestGeneration,
        text,
        'AI javobi kechikdi. Internetni tekshirib, qayta urinib ko‘ring.',
      );
    } on FunctionException catch (error) {
      _showSendError(requestGeneration, text, _functionErrorText(error));
    } on FormatException {
      _showSendError(
        requestGeneration,
        text,
        'Serverdan noto‘g‘ri javob keldi. Qayta urinib ko‘ring.',
      );
    } catch (error) {
      debugPrint('ServicePro AI: request failed: ${error.runtimeType}');
      _showSendError(
        requestGeneration,
        text,
        'AI bilan bog‘lanib bo‘lmadi. Internetni tekshirib, qayta urinib ko‘ring.',
      );
    }
  }

  String _functionErrorText(FunctionException error) {
    final status = error.status;
    final details = error.details;
    String? code;
    if (details is Map && details['code'] is String) {
      code = details['code'] as String;
    } else if (details is String) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map && decoded['code'] is String) {
          code = decoded['code'] as String;
        }
      } catch (_) {
        // Some SDK versions provide a plain-text response body.
      }
    }

    if (status == 401 || status == 403 || code == 'UNAUTHORIZED') {
      return 'Sessiya tugagan yoki kirish rad etilgan. Qayta kiring.';
    }
    if (status == 429 || code == 'GEMINI_RATE_LIMIT') {
      return 'Gemini so‘rov limiti tugagan. Birozdan keyin urinib ko‘ring.';
    }
    if (code == 'GEMINI_NOT_CONFIGURED' || code == 'SERVER_CONFIG') {
      return 'AI server sozlamalarini tekshirish kerak. Administratorga xabar bering.';
    }
    if (code == 'GEMINI_UPSTREAM_ERROR') {
      return 'Gemini API javob bermadi. Kalit, tarif va model ruxsatini tekshiring.';
    }
    if (status == 404) {
      return 'servicepro-ai funksiyasi topilmadi. Supabase deployni tekshiring.';
    }
    if (status == 0) {
      return 'Internet yoki Supabase serveriga ulanishda muammo bor.';
    }
    return 'AI xizmati vaqtincha ishlamayapti (kod: $status). Qayta urinib ko‘ring.';
  }

  void _showSendError(int generation, String prompt, String description) {
    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      typing = false;
      _errorText = description;
      _retryPrompt = prompt;
    });
    _scrollBottom();
  }

  /// Reports only real AI responses. No changes to Gemini or chat history.
  /// The report is stored in Supabase for developer moderation.
  Future<void> _reportAiResponse(int index) async {
    if (_loadingHistory || index < 0 || index >= messages.length) return;
    final response = messages[index];
    if (response.mine || !response.includeInContext) return;

    final client = Supabase.instance.client;
    final reportingUserId = client.auth.currentUser?.id;
    if (reportingUserId == null || client.auth.currentSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shikoyat yuborish uchun hisobingizga kiring.')),
      );
      return;
    }

    // Attach only the question immediately preceding this AI response.
    // Disclose that context to the reporter before submitting it.
    String? prompt;
    if (index > 0 && messages[index - 1].mine) {
      prompt = messages[index - 1].text;
    }

    String reason = 'inaccurate';
    String details = '';
    bool submitting = false;
    String? submitError;
    if (!mounted) return;
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('AI javobidan shikoyat / Report AI content'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Noto‘g‘ri yoki nomaqbul AI javobini ishlab chiquvchiga '
                    'yuborishingiz mumkin. Shikoyat ko‘rib chiqiladi.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Shikoyat sababi'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'inaccurate',
                        child: Text('Noto‘g‘ri yoki chalg‘ituvchi ma’lumot'),
                      ),
                      DropdownMenuItem(
                        value: 'harmful',
                        child: Text('Zararli yoki xavfli mazmun'),
                      ),
                      DropdownMenuItem(
                        value: 'offensive',
                        child: Text('Haqoratomuz yoki nomaqbul mazmun'),
                      ),
                      DropdownMenuItem(
                        value: 'privacy',
                        child: Text('Shaxsiy ma’lumot yoki maxfiylik'),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text('Boshqa sabab'),
                      ),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) {
                            if (value != null) {
                              updateDialog(() => reason = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    enabled: !submitting,
                    maxLines: 3,
                    maxLength: 500,
                    onChanged: (value) => details = value,
                    decoration: const InputDecoration(
                      labelText: 'Qo‘shimcha izoh (ixtiyoriy)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shikoyat bilan birga tanlangan AI javobi, unga tegishli '
                    'savolingiz (bo‘lsa) va hisob identifikatori '
                    'tekshirish uchun yuboriladi.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      submitError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Bekor qilish'),
            ),
            FilledButton.icon(
              onPressed: submitting
                  ? null
                  : () async {
                      updateDialog(() {
                        submitting = true;
                        submitError = null;
                      });
                      try {
                        if (client.auth.currentUser?.id != reportingUserId) {
                          throw StateError('account_changed');
                        }
                        await client.from('ai_content_reports').insert({
                          'reporter_user_id': reportingUserId,
                          'ai_response': response.text,
                          'user_prompt': prompt,
                          'reason': reason,
                          'details': details.trim().isEmpty
                              ? null
                              : details.trim(),
                        }).timeout(const Duration(seconds: 20));
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (error) {
                        debugPrint('ServicePro AI report: ${error.runtimeType}');
                        if (!dialogContext.mounted) return;
                        updateDialog(() {
                          submitting = false;
                          if (error is PostgrestException &&
                              error.code == '42P01') {
                            submitError = 'AI shikoyatlar jadvali o‘rnatilmagan. '
                                'Administratorga xabar bering.';
                          } else if (error is StateError) {
                            submitError = 'Hisob o‘zgargan. Qayta kiring.';
                          } else {
                            submitError = 'Shikoyat yuborilmadi. '
                                'Internet va Supabase ruxsatlarini tekshirib, '
                                'qayta urinib ko‘ring.';
                          }
                        });
                      }
                    },
              icon: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flag_outlined),
              label: const Text('Yuborish'),
            ),
          ],
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shikoyatingiz qabul qilindi. Rahmat!'),
        ),
      );
    }
  }

  Future<void> _clearHistory() async {
    if (_loadingHistory || typing) return;
    final userIdBeforeDialog = _activeUserId;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('AI chat tarixi tozalansinmi?'),
        content: const LocalizedText('Faqat AI yordamchi yozishmalari o‘chadi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Tozalash'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true || _activeUserId != userIdBeforeDialog) {
      return;
    }
    setState(() {
      messages
        ..clear()
        ..add(const _AiMessage(
          text: _clearedText,
          mine: false,
          includeInContext: false,
        ));
      _errorText = null;
      _retryPrompt = null;
    });
    // Overwriting the key clears only the current account's AI history.
    _saveHistory();
    _scrollBottom(jump: true);
  }

  void _scrollBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      final max = scrollController.position.maxScrollExtent;
      if (jump) {
        scrollController.jumpTo(max);
      } else {
        scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ServicePro AI'),
        actions: [
          IconButton(
            tooltip: LocalizedText.translate(context, 'Tarixni tozalash'),
            onPressed: (_loadingHistory || typing) ? null : _clearHistory,
            icon: const Icon(Icons.cleaning_services_rounded),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.25,
            colors: [
              colors.primaryContainer.withValues(alpha: .55),
              colors.surface,
              colors.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _AiTopCard(colors: colors),
            ),
            Expanded(
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: messages.length + (typing ? 1 : 0),
                itemBuilder: (context, index) {
                  if (typing && index == messages.length) {
                    return const _TypingBubble();
                  }
                  return _AiBubble(
                    message: messages[index],
                    onReport: (!messages[index].mine &&
                            messages[index].includeInContext)
                        ? () => _reportAiResponse(index)
                        : null,
                  );
                },
              ),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 20, color: colors.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                      if (_retryPrompt != null)
                        TextButton(
                          onPressed: typing
                              ? null
                              : () => _send(retryText: _retryPrompt),
                          child: const Text('Qayta'),
                        ),
                    ],
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.primary.withValues(alpha: .24)),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: .08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          enabled: !_loadingHistory && !typing,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: _maxMessageLength,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: LocalizedText.translate(
                              context,
                              'Savolingizni yozing...',
                            ),
                            prefixIcon: const Icon(Icons.psychology_alt_rounded),
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: (_loadingHistory || typing) ? null : _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
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
}

class _AiTopCard extends StatelessWidget {
  const _AiTopCard({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: .22),
            colors.secondaryContainer.withValues(alpha: .65),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .22)),
      ),
      child: const Row(
        children: [
          CircleAvatar(child: Icon(Icons.auto_awesome_rounded)),
          SizedBox(width: 12),
          Expanded(
            child: LocalizedText(
              'AI yordamchi eski yozishmalarni saqlaydi va keyingi kirishda ham ko‘rsatadi.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiMessage {
  const _AiMessage({
    required this.text,
    required this.mine,
    this.includeInContext = true,
  });

  final String text;
  final bool mine;
  final bool includeInContext;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'mine': mine,
    'includeInContext': includeInContext,
  };

  factory _AiMessage.fromJson(Map<dynamic, dynamic> json) {
    final text = '${json['text'] ?? ''}';
    final mine = json['mine'] == true;
    // Old v1 assistant responses were hardcoded, not genuine Gemini replies.
    // Keep those messages visible, but don't teach Gemini from them.
    final includeInContext = json['includeInContext'] is bool
        ? json['includeInContext'] == true
        : false;
    return _AiMessage(
      text: text,
      mine: mine,
      includeInContext: includeInContext,
    );
  }
}

class _AiBubble extends StatelessWidget {
  const _AiBubble({required this.message, this.onReport});

  final _AiMessage message;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: message.mine
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(message.mine ? 22 : 6),
            bottomRight: Radius.circular(message.mine ? 6 : 22),
          ),
          border: Border.all(
            color: colors.primary.withValues(alpha: message.mine ? .24 : .10),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: .05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message.text),
            if (onReport != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.flag_outlined, size: 17),
                  label: const Text('Shikoyat / Report'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
        ),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final active = (controller.value * 3).floor() % 3;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 7,
                  height: i == active ? 12 : 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: i == active ? 1 : .35),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
