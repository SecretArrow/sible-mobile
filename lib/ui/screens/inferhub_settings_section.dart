/// Self-contained "InferHub AI" settings card.
///
/// Replicates the `_Group` card visual language of `settings_screen.dart`
/// locally (that file is not touched); mount this widget anywhere in the
/// settings list.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/inferhub_models.dart';
import '../../services/inferhub_service.dart';
import '../widgets/model_picker_dialog.dart';

/// Settings card for the InferHub AI brain: master toggle, API key, model
/// picker, feature switches and advanced options (temperature, tokens,
/// price caps, timeout, connection test, docs).
class InferHubSettingsSection extends StatefulWidget {
  const InferHubSettingsSection({super.key});

  @override
  State<InferHubSettingsSection> createState() =>
      _InferHubSettingsSectionState();
}

class _InferHubSettingsSectionState extends State<InferHubSettingsSection> {
  final _apiKeyCtrl = TextEditingController();
  final _maxTokensCtrl = TextEditingController();
  final _maxInPriceCtrl = TextEditingController();
  final _maxOutPriceCtrl = TextEditingController();
  final _timeoutCtrl = TextEditingController();

  InferHubConfig _config = const InferHubConfig();
  String _apiKey = '';
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _maxTokensCtrl.dispose();
    _maxInPriceCtrl.dispose();
    _maxOutPriceCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final settings = await InferHubSettings.load();
      _config = settings.config;
      _apiKey = settings.apiKey;
      _apiKeyCtrl.text = _apiKey;
      _maxTokensCtrl.text = '${_config.maxTokens}';
      _maxInPriceCtrl.text = _numText(_config.maxInputPrice);
      _maxOutPriceCtrl.text = _numText(_config.maxOutputPrice);
      _timeoutCtrl.text = '${_config.timeoutSeconds}';
    } catch (e) {
      debugPrint('[inferhub] settings restore failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _numText(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Future<void> _persist(InferHubConfig next) async {
    setState(() => _config = next);
    try {
      await InferHubSettings.save(config: next, apiKey: _apiKey);
    } catch (e) {
      debugPrint('[inferhub] settings save failed: $e');
    }
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyCtrl.text.trim();
    setState(() => _apiKey = key);
    try {
      await InferHubSettings.save(config: _config, apiKey: key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'inferhub.apiKeySaved'))),
      );
    } catch (e) {
      debugPrint('[inferhub] api key save failed: $e');
    }
  }

  Future<void> _pickModel() async {
    if (_apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'inferhub.apiKeyMissing'))),
      );
      return;
    }
    final picked = await showModelPickerDialog(
      context,
      service: InferHubService(config: _config, apiKey: _apiKey),
      current: _config.model,
      freeOnly: _config.freeOnly,
    );
    if (!mounted) return;
    if (picked != null && picked.isNotEmpty && picked != _config.model) {
      await _persist(_config.copyWith(model: picked));
    }
  }

  Future<void> _testConnection() async {
    if (_apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'inferhub.apiKeyMissing'))),
      );
      return;
    }
    // Capture everything context-dependent before the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final okText = t(context, 'inferhub.testOk');
    final failText = t(context, 'inferhub.testFailed');
    final balanceText = t(context, 'inferhub.balance');
    setState(() => _testing = true);
    var ok = false;
    String detail;
    try {
      final balance = await InferHubService(
        config: _config,
        apiKey: _apiKey,
      ).testConnection();
      ok = true;
      detail = '$balanceText: $balance USDC';
    } catch (e) {
      detail = '$e';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '$okText · $detail' : '$failText · $detail'),
      ),
    );
  }

  Future<void> _openDocs() async {
    try {
      await launchUrl(
        Uri.parse(InferHub.docsUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[inferhub] open docs failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: SibleTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SibleTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Text(
                t(context, 'inferhub.title').toUpperCase(),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            SwitchListTile(
              title: _t(t(context, 'inferhub.enable')),
              subtitle: _s(t(context, 'inferhub.enableHint')),
              value: _config.enabled,
              onChanged: (v) => _persist(_config.copyWith(enabled: v)),
            ),
            _apiKeyField(),
            _modelTile(),
            SwitchListTile(
              title: _t(t(context, 'inferhub.freeOnly')),
              subtitle: _s(t(context, 'inferhub.freeOnlyHint')),
              value: _config.freeOnly,
              onChanged: (v) => _persist(_config.copyWith(freeOnly: v)),
            ),
            SwitchListTile(
              title: _t(t(context, 'inferhub.modeTaskSolver')),
              subtitle: _s(t(context, 'inferhub.modeTaskSolverHint')),
              value: _config.taskSolver,
              onChanged: (v) => _persist(_config.copyWith(taskSolver: v)),
            ),
            SwitchListTile(
              title: _t(t(context, 'inferhub.modePlanner')),
              subtitle: _s(t(context, 'inferhub.modePlannerHint')),
              value: _config.planner,
              onChanged: (v) => _persist(_config.copyWith(planner: v)),
            ),
            SwitchListTile(
              title: _t(t(context, 'inferhub.modeExtensionPicker')),
              subtitle: _s(t(context, 'inferhub.modeExtensionPickerHint')),
              value: _config.extensionPicker,
              onChanged: (v) => _persist(_config.copyWith(extensionPicker: v)),
            ),
            _advanced(),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _apiKeyField() {
    final masked = _apiKey.isEmpty
        ? null
        : '••••${_apiKey.substring(
            _apiKey.length >= 4 ? _apiKey.length - 4 : 0,
          )}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _t(t(context, 'inferhub.apiKey')),
          if (masked != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                masked,
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: t(context, 'inferhub.apiKeyHint'),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_outlined, size: 20),
                onPressed: _saveApiKey,
              ),
            ),
            onSubmitted: (_) => _saveApiKey(),
          ),
        ],
      ),
    );
  }

  Widget _modelTile() {
    final model = _config.model;
    return ListTile(
      title: _t(
        model.isEmpty ? t(context, 'inferhub.modelPick') : model,
        mono: model.isNotEmpty,
      ),
      subtitle: _s(t(context, 'inferhub.model')),
      trailing: const Icon(
        Icons.chevron_right,
        color: SibleTheme.textSecondary,
      ),
      onTap: _pickModel,
    );
  }

  Widget _advanced() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 18),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      title: _t(t(context, 'inferhub.advanced')),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: _t(
            '${t(context, 'inferhub.temperature')} '
            '(${_config.temperature.toStringAsFixed(1)})',
          ),
          trailing: SizedBox(
            width: 160,
            child: Slider(
              value: _config.temperature,
              min: 0,
              max: 2,
              divisions: 20,
              label: _config.temperature.toStringAsFixed(1),
              onChanged: (v) =>
                  setState(() => _config = _config.copyWith(temperature: v)),
              onChangeEnd: (v) => _persist(_config.copyWith(temperature: v)),
            ),
          ),
        ),
        _numberField(
          label: t(context, 'inferhub.maxTokens'),
          controller: _maxTokensCtrl,
          onCommit: (v) => _persist(
            _config.copyWith(maxTokens: int.tryParse(v) ?? _config.maxTokens),
          ),
        ),
        _numberField(
          label: t(context, 'inferhub.maxInputPrice'),
          controller: _maxInPriceCtrl,
          onCommit: (v) => _persist(
            _config.copyWith(maxInputPrice: double.tryParse(v) ?? 0),
          ),
        ),
        _numberField(
          label: t(context, 'inferhub.maxOutputPrice'),
          controller: _maxOutPriceCtrl,
          onCommit: (v) => _persist(
            _config.copyWith(maxOutputPrice: double.tryParse(v) ?? 0),
          ),
        ),
        _numberField(
          label: t(context, 'inferhub.timeout'),
          controller: _timeoutCtrl,
          onCommit: (v) => _persist(
            _config.copyWith(
              timeoutSeconds: int.tryParse(v) ?? _config.timeoutSeconds,
            ),
          ),
        ),
        Row(
          children: [
            OutlinedButton(
              onPressed: _testing ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t(context, 'inferhub.testConnection')),
            ),
            const Spacer(),
            IconButton(
              tooltip: t(context, 'inferhub.docs'),
              onPressed: _openDocs,
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onCommit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, isDense: true),
        onSubmitted: onCommit,
      ),
    );
  }

  Text _t(String s, {bool mono = false}) => Text(
        s,
        maxLines: mono ? 1 : null,
        overflow: mono ? TextOverflow.ellipsis : null,
        style: TextStyle(
          color: SibleTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: mono ? 'monospace' : null,
        ),
      );

  Text _s(String s) => Text(
        s,
        style: const TextStyle(
          color: SibleTheme.textSecondary,
          fontSize: 11.5,
        ),
      );
}
