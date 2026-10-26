/// Per-account manual proxy override (#8): prefs store + settings card.
library;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/proxy_override_store.dart';
import '../../services/proxy_tester.dart';
import '../widgets/common.dart';

/// Card for the account detail sheet: "use manual proxy" switch, validated
/// URI field with implicit save, and a live proxy test button that reports
/// the exit IP / country via snackbars.
class ProxyOverrideCard extends StatefulWidget {
  /// Account this card configures.
  final String accountId;

  const ProxyOverrideCard({super.key, required this.accountId});

  @override
  State<ProxyOverrideCard> createState() => _ProxyOverrideCardState();
}

class _ProxyOverrideCardState extends State<ProxyOverrideCard> {
  final TextEditingController _uri = TextEditingController();
  bool _enabled = false;
  bool _busy = false;
  bool _loaded = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _uri.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await ProxyOverrideStore.isEnabled(widget.accountId);
    final saved = await ProxyOverrideStore.getOverride(widget.accountId);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _uri.text = saved ?? '';
      _loaded = true;
    });
  }

  void _onToggle(bool v) {
    setState(() => _enabled = v);
    final text = _uri.text.trim();
    final msg = t(context, 'proxy.saved');
    final messenger = ScaffoldMessenger.of(context);
    ProxyOverrideStore.set(
      widget.accountId,
      enabled: v,
      uri: text.isEmpty ? null : normalizeProxyUri(text),
    ).then((_) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  void _onUriChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _saveUri);
  }

  /// Implicit save: persists a normalized URI when valid; clearing the
  /// field drops the stored URI and turns the override off. Invalid text is
  /// only flagged (error text) — the last good value stays stored.
  Future<void> _saveUri() async {
    if (!mounted) return;
    final text = _uri.text.trim();
    if (text.isEmpty) {
      await ProxyOverrideStore.set(
        widget.accountId,
        enabled: false,
        uri: null,
      );
      if (mounted && _enabled) setState(() => _enabled = false);
      return;
    }
    final normalized = normalizeProxyUri(text);
    if (normalized == null) return;
    final msg = t(context, 'proxy.saved');
    final messenger = ScaffoldMessenger.of(context);
    await ProxyOverrideStore.set(
      widget.accountId,
      enabled: _enabled,
      uri: normalized,
    );
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _test() async {
    final text = _uri.text.trim();
    final normalized = normalizeProxyUri(text);
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'proxy.invalidUri'))),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final okTpl = t(context, 'proxy.testOk');
    final failTpl = t(context, 'proxy.testFail');
    setState(() => _busy = true);
    await ProxyOverrideStore.set(
      widget.accountId,
      enabled: _enabled,
      uri: normalized,
    );
    final result = await testProxyUri(normalized);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            okTpl
                .replaceAll('{ip}', result.ip ?? '-')
                .replaceAll('{country}', result.country ?? '-'),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failTpl.replaceAll('{e}', result.error ?? 'unknown'),
          ),
        ),
      );
    }
  }

  InputDecoration _uriDecoration(bool invalid) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      isDense: true,
      hintText: t(context, 'proxy.uri'),
      hintStyle:
          const TextStyle(color: SibleTheme.textSecondary, fontSize: 11.5),
      errorText: invalid ? t(context, 'proxy.invalidUri') : null,
      filled: true,
      fillColor: SibleTheme.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border(SibleTheme.border),
      enabledBorder: border(SibleTheme.border),
      focusedBorder: border(SibleTheme.primary, 1.2),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const GlowCard(
        margin: EdgeInsets.zero,
        child: SizedBox(
          height: 64,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    final text = _uri.text.trim();
    final invalid = text.isNotEmpty && !isValidProxyUri(text);
    return GlowCard(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            value: _enabled,
            onChanged: _busy ? null : _onToggle,
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            title: Text(
              t(context, 'proxy.overrideEnabled'),
              style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              t(context, 'proxy.overrideHint'),
              style: const TextStyle(
                  color: SibleTheme.textSecondary, fontSize: 11.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _uri,
                  enabled: _enabled,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                      color: SibleTheme.textPrimary, fontSize: 12.5),
                  onChanged: _onUriChanged,
                  decoration: _uriDecoration(invalid),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: (_busy || !_enabled || invalid) ? null : _test,
                      icon: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check, size: 16),
                      label: Text(
                        _busy
                            ? t(context, 'proxy.testing')
                            : t(context, 'proxy.test'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
