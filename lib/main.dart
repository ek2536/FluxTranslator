import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

enum Direction { zhToEn, enToZh }

enum ProviderKind { offline, openai }

enum ThemeModeChoice { system, light, dark }

class TranslationResult {
  const TranslationResult(this.text, this.provider);
  final String text;
  final String provider;
}

class TranslationService {
  Future<TranslationResult> translate({
    required String source,
    required Direction direction,
    required ProviderKind provider,
    String apiKey = '',
    String model = 'gpt-4o-mini',
    String endpoint = 'https://api.openai.com/v1/chat/completions',
  }) async {
    if (provider == ProviderKind.openai) {
      if (apiKey.trim().isEmpty)
        throw Exception('Add an API key in Settings to use AI translation.');
      final target =
          direction == Direction.zhToEn ? 'English' : 'Simplified Chinese';
      final dictionaryStyle = _isShortLookup(source);
      final instruction = dictionaryStyle
          ? 'The input is one word. Return a compact dictionary entry in $target. Put each part of speech on its own line, followed by common meanings separated by semicolons. Omit a category that has no useful common meaning. Return only the entry. Example: n. 图表; 表格\nv. 绘制图表; 制订计划.'
          : 'Translate accurately into $target. Return only the translation, preserving tone, formatting, and line breaks.';
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiKey.trim()}',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.2,
          'messages': [
            {
              'role': 'system',
              'content': instruction,
            },
            {'role': 'user', 'content': source},
          ],
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw Exception(
          'AI request failed (${response.statusCode}). Check your endpoint and key.',
        );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = ((data['choices'] as List).first as Map)['message']
          ['content'] as String;
      return TranslationResult(text.trim(), 'AI · $model');
    }
    final known = <String, String>{
      '你好': 'Hello',
      '谢谢': 'Thank you',
      '早上好': 'Good morning',
      '再见': 'Goodbye',
      '我爱你': 'I love you',
      '多少钱？': 'How much does it cost?',
      '多少钱': 'How much does it cost?',
      '今天': 'today',
      '明天': 'tomorrow',
      '好的': 'Okay',
      '是的': 'Yes',
      '不是': 'No',
      'Hello': '你好',
      'Thank you': '谢谢',
      'Good morning': '早上好',
      'Goodbye': '再见',
      'How are you?': '你好吗？',
      'How much does it cost?': '多少钱？',
      'salary': 'n. 工资; 薪水',
      '工资': 'n. salary; pay',
      'chart': 'n. 图表; 表格; 海图; 记录表; 排行榜\nv. 绘制图表; 制订计划; 记录; 驾驶（航船）测绘航线',
    };
    final result = known[source.trim()];
    if (result != null) return TranslationResult(result, 'Offline phrasebook');
    return TranslationResult(
      direction == Direction.zhToEn
          ? 'No offline match. Switch to AI for contextual translation.'
          : '离线词库中没有匹配项。切换到 AI 获取上下文翻译。',
      'Offline phrasebook',
    );
  }

  bool _isShortLookup(String source) {
    final trimmed = source.trim();
    return trimmed.split(RegExp(r'\s+')).length == 1 &&
        !RegExp(r'[.!?。！？\n]').hasMatch(trimmed);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
      size: Size(560, 620),
      minimumSize: Size(460, 480),
      center: true,
      title: 'Flux Translator',
      alwaysOnTop: false,
      backgroundColor: Colors.transparent);
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const QuickTranslateApp());
}

class QuickTranslateApp extends StatefulWidget {
  const QuickTranslateApp({super.key});
  @override
  State<QuickTranslateApp> createState() => _QuickTranslateAppState();
}

class _QuickTranslateAppState extends State<QuickTranslateApp> {
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final service = TranslationService();
  Direction direction = Direction.zhToEn;
  ProviderKind provider = ProviderKind.offline;
  ThemeModeChoice themeChoice = ThemeModeChoice.system;
  String output = '';
  String status = 'Ready';
  String? failure;
  bool busy = false;
  bool settings = false;
  bool registered = false;
  String apiKey = '';
  String model = 'gpt-4o-mini';
  String endpoint = 'https://api.openai.com/v1/chat/completions';
  List<String> availableModels = [];
  bool loadingModels = false;
  String? modelsError;
  BuildContext? _themeContext;
  HotKey shortcut = HotKey(
    key: LogicalKeyboardKey.keyT,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      apiKey = p.getString('apiKey') ?? '';
      model = p.getString('model') ?? model;
      endpoint = p.getString('endpoint') ?? endpoint;
      provider = (p.getString('provider') == 'openai')
          ? ProviderKind.openai
          : ProviderKind.offline;
      themeChoice = ThemeModeChoice.values.firstWhere(
          (v) => v.name == p.getString('theme'),
          orElse: () => ThemeModeChoice.system);
      final savedShortcut = p.getString('shortcut');
      if (savedShortcut != null) {
        try {
          shortcut = HotKey.fromJson(jsonDecode(savedShortcut));
        } catch (_) {}
      }
    });
    await _registerHotkey();
  }

  Future<void> _registerHotkey() async {
    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        shortcut,
        keyDownHandler: (_) async {
          if (await windowManager.isMinimized()) {
            await windowManager.restore();
          }
          await windowManager.show();
          await windowManager.focus();
          if (mounted) {
            setState(() {
              settings = false;
            });
            inputFocus.requestFocus();
          }
        },
      );
      setState(() => registered = true);
    } catch (_) {
      setState(() => registered = false);
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('apiKey', apiKey);
    await p.setString('model', model);
    await p.setString('endpoint', endpoint);
    await p.setString('provider', provider.name);
    await p.setString('theme', themeChoice.name);
    await p.setString('shortcut', jsonEncode(shortcut.toJson()));
  }

  Future<void> _loadModels() async {
    if (apiKey.trim().isEmpty) {
      setState(() => modelsError = 'Enter an API key first.');
      return;
    }
    setState(() {
      loadingModels = true;
      modelsError = null;
    });
    try {
      final chatUri = Uri.parse(endpoint);
      final modelsUri = chatUri.replace(
        path: chatUri.path.replaceFirst(
          RegExp(r'/chat/completions/?$'),
          '/models',
        ),
        query: null,
      );
      final response = await http.get(
        modelsUri,
        headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Model request failed (${response.statusCode}).');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['data'] as List<dynamic>)
          .map((item) => (item as Map<String, dynamic>)['id'] as String?)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
      if (models.isEmpty) throw Exception('No models were returned.');
      setState(() => availableModels = models);
    } catch (e) {
      setState(
          () => modelsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loadingModels = false);
    }
  }

  Future<void> _translate() async {
    if (input.text.trim().isEmpty) {
      setState(() => status = 'Enter text to translate');
      return;
    }
    final detected = _detectDirection(input.text);
    if (detected != null && detected != direction)
      setState(() => direction = detected);
    setState(() {
      busy = true;
      status = 'Translating…';
      failure = null;
    });
    try {
      final r = await service.translate(
        source: input.text,
        direction: direction,
        provider: provider,
        apiKey: apiKey,
        model: model,
        endpoint: endpoint,
      );
      setState(() {
        output = r.text;
        status = r.provider;
        failure = null;
      });
    } catch (e) {
      setState(() {
        failure = e.toString().replaceFirst('Exception: ', '');
        status = 'Translation failed';
      });
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    inputFocus.dispose();
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff146c94),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xeef4f7f8),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xffeef3f5),
        ),
      ),
      themeMode: themeChoice == ThemeModeChoice.system
          ? ThemeMode.system
          : themeChoice == ThemeModeChoice.dark
              ? ThemeMode.dark
              : ThemeMode.light,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff67c7e8), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xea11181c),
        fontFamily: 'Segoe UI',
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xff202b30),
        ),
      ),
      home: Builder(builder: (context) {
        _themeContext = context;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      _header(),
                      const SizedBox(height: 16),
                      Expanded(child: settings ? _settings() : _workspace()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xff146c94),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.translate, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Flux',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text('Chinese ↔ English',
                  style: TextStyle(
                    color: Theme.of(_themeContext ?? context)
                        .colorScheme
                        .onSurfaceVariant,
                  )),
            ],
          ),
          const Spacer(),
          Text(
            registered ? _shortcutLabel() : 'Shortcut unavailable',
            style: TextStyle(
              fontSize: 12,
              color: registered ? const Color(0xff146c94) : Colors.red,
            ),
          ),
          const SizedBox(width: 18),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => setState(() => settings = !settings),
            icon: Icon(settings ? Icons.close : Icons.tune),
          ),
        ],
      );
  Widget _workspace() => ListView(
        children: [
          Row(children: [
            Expanded(
                child: _directionButton('中文', 'Chinese', Direction.zhToEn)),
            IconButton(
                tooltip: 'Swap languages',
                onPressed: () => setState(() => direction =
                    direction == Direction.zhToEn
                        ? Direction.enToZh
                        : Direction.zhToEn),
                icon: const Icon(Icons.swap_horiz, size: 18)),
            Expanded(
                child:
                    _directionButton('English', 'English', Direction.enToZh)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
              height: 112,
              child: _panel(
                'Input',
                CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter): _translate,
                  },
                  child: TextField(
                    controller: input,
                    focusNode: inputFocus,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: 'Type or paste text… (Enter to translate)',
                      filled: true,
                      fillColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 10),
          SizedBox(
              height: 180,
              child: _panel(
                  'Translation',
                  failure != null
                      ? _failureView(failure!)
                      : SelectableText(
                          output.isEmpty ? 'Translation appears here.' : output,
                          style: TextStyle(
                              fontSize: 16,
                              color: output.isEmpty
                                  ? Theme.of(_themeContext ?? context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : Theme.of(_themeContext ?? context)
                                      .colorScheme
                                      .onSurface,
                              height: 1.35)),
                  trailing: IconButton(
                    tooltip: 'Copy translation',
                    visualDensity: VisualDensity.compact,
                    onPressed: output.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                                ClipboardData(text: output));
                            if (mounted) setState(() => status = 'Copied');
                          },
                    icon: const Icon(Icons.copy_outlined, size: 17),
                  ))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(_themeContext ?? context)
                        .colorScheme
                        .onSurfaceVariant),
              )),
              const SizedBox(width: 8),
              DropdownButton<ProviderKind>(
                value: provider,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: ProviderKind.offline,
                    child: Text('Offline phrasebook'),
                  ),
                  DropdownMenuItem(
                    value: ProviderKind.openai,
                    child: Text('AI provider'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => provider = v);
                    _save();
                  }
                },
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: busy ? null : _translate,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(_themeContext ?? context).brightness ==
                              Brightness.dark
                          ? const Color(0xff2b6379)
                          : const Color(0xff36718a),
                  foregroundColor: Colors.white,
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward),
                label: Text(busy
                    ? 'Working'
                    : failure != null
                        ? 'Retry'
                        : 'Translate'),
              ),
            ],
          ),
        ],
      );

  Widget _failureView(String message) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.error_outline,
                size: 18,
                color: Theme.of(_themeContext ?? context).colorScheme.error),
            const SizedBox(width: 8),
            const Text('Could not translate',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Expanded(
              child: SingleChildScrollView(
                  child: Text(message,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(_themeContext ?? context)
                              .colorScheme
                              .onSurfaceVariant)))),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                  onPressed: busy ? null : _translate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'))),
        ],
      );
  Widget _directionButton(String title, String subtitle, Direction value) =>
      InkWell(
        onTap: () => setState(() => direction = value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: direction == value
                ? Theme.of(_themeContext ?? context)
                    .colorScheme
                    .primaryContainer
                : Theme.of(_themeContext ?? context)
                    .colorScheme
                    .surfaceContainerHighest,
            border: Border.all(
              color: direction == value
                  ? const Color(0xff146c94)
                  : Theme.of(_themeContext ?? context)
                      .colorScheme
                      .outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                direction == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 19,
                color: const Color(0xff146c94),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(subtitle,
                  style: TextStyle(
                      color: Theme.of(_themeContext ?? context)
                          .colorScheme
                          .onSurfaceVariant)),
            ],
          ),
        ),
      );
  Widget _panel(String label, Widget child, {Widget? trailing}) => Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: Theme.of(_themeContext ?? context)
              .colorScheme
              .surface
              .withValues(alpha: 0.86),
          border: Border.all(
              color: Theme.of(_themeContext ?? context)
                  .colorScheme
                  .outlineVariant),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6))
          ],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(_themeContext ?? context)
                          .colorScheme
                          .onSurfaceVariant,
                      letterSpacing: 1)),
              const Spacer(),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 10),
            Expanded(child: child),
          ],
        ),
      );
  Widget _settings() => ListView(
        children: [
          Text(
            'Settings',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose how translations are produced on this device.',
            style: TextStyle(
                color: Theme.of(_themeContext ?? context)
                    .colorScheme
                    .onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _field(
            'OpenAI-compatible API key',
            apiKey,
            (v) {
              apiKey = v;
              _save();
            },
            obscure: true,
            hint: 'sk-…',
          ),
          _field('Model', model, (v) {
            model = v;
            _save();
          }, hint: 'gpt-4o-mini'),
          _field('Endpoint', endpoint, (v) {
            endpoint = v;
            _save();
          }),
          Row(children: [
            const Expanded(child: Text('Available models')),
            OutlinedButton.icon(
              onPressed: loadingModels ? null : _loadModels,
              icon: loadingModels
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 17),
              label: Text(loadingModels ? 'Loading' : 'Load models'),
            ),
          ]),
          if (availableModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: model,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Select model',
                border: OutlineInputBorder(),
              ),
              items: [
                ...availableModels,
                if (!availableModels.contains(model)) model,
              ]
                  .map((id) => DropdownMenuItem(
                      value: id,
                      child: Text(id, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => model = value);
                  _save();
                }
              },
            ),
          ],
          if (modelsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(modelsError!,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(_themeContext ?? context)
                          .colorScheme
                          .error)),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(_themeContext ?? context)
                      .colorScheme
                      .outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Expanded(child: Text('Global shortcut')),
              HotKeyRecorder(
                initalHotKey: shortcut,
                onHotKeyRecorded: (value) async {
                  if (value.modifiers == null || value.modifiers!.isEmpty) {
                    setState(() =>
                        status = 'Use Ctrl, Alt, Shift, or Windows with a key');
                    return;
                  }
                  setState(() => shortcut = value);
                  await _save();
                  await _registerHotkey();
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ThemeModeChoice>(
            value: themeChoice,
            decoration: const InputDecoration(
                labelText: 'Theme', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: ThemeModeChoice.system, child: Text('System default')),
              DropdownMenuItem(
                  value: ThemeModeChoice.light, child: Text('Light')),
              DropdownMenuItem(
                  value: ThemeModeChoice.dark, child: Text('Dark')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => themeChoice = value);
                _save();
              }
            },
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 20),
          Text(
            'Offline mode uses a tiny phrasebook for predictable, common phrases. For sentences, tone, and domain terminology, use an API provider. Your key is stored in local Windows preferences and sent only to the configured endpoint.',
            style: TextStyle(
                color: Theme.of(_themeContext ?? context)
                    .colorScheme
                    .onSurfaceVariant,
                height: 1.4),
          ),
        ],
      );
  Widget _field(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool obscure = false,
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: TextEditingController(text: value),
          obscureText: obscure,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true,
            fillColor: Theme.of(_themeContext ?? context)
                .colorScheme
                .surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      );

  Direction? _detectDirection(String value) {
    final hasChinese = RegExp(r'[\u3400-\u9fff]').hasMatch(value);
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(value);
    if (hasChinese && !hasLatin) return Direction.zhToEn;
    if (hasLatin && !hasChinese) return Direction.enToZh;
    return null;
  }

  String _shortcutLabel() => shortcut.debugName
      .replaceAll('Control Left', 'Ctrl')
      .replaceAll('Control Right', 'Ctrl')
      .replaceAll('Alt Left', 'Alt')
      .replaceAll('Alt Right', 'Alt')
      .replaceAll('Shift Left', 'Shift')
      .replaceAll('Shift Right', 'Shift')
      .replaceAll('Key ', '');
}
