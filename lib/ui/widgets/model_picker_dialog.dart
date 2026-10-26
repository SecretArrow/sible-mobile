/// Model picker bottom sheet: client-side search + pagination over the
/// InferHub model catalog.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/inferhub_models.dart';
import '../../services/inferhub_service.dart';
import 'common.dart';

/// Opens a modal bottom sheet listing InferHub models with debounced search
/// and pagination. Returns the selected model id, or null when dismissed.
Future<String?> showModelPickerDialog(
  BuildContext context, {
  required InferHubService service,
  required String? current,
  required bool freeOnly,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ModelPickerSheet(
      service: service,
      current: current,
      freeOnly: freeOnly,
    ),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  final InferHubService service;
  final String? current;
  final bool freeOnly;

  const _ModelPickerSheet({
    required this.service,
    required this.current,
    required this.freeOnly,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<InferHubModel>? _models;
  String? _error;
  String _query = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final models = await widget.service.fetchModels();
      if (!mounted) return;
      setState(() => _models = models);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _page = 0;
      });
    });
  }

  List<InferHubModel> get _scoped {
    final all = _models ?? const <InferHubModel>[];
    return widget.freeOnly ? all.where((m) => m.free).toList() : all;
  }

  @override
  Widget build(BuildContext context) {
    final page = _error == null && _models != null
        ? InferHubService.searchModels(
            _scoped,
            query: _query,
            page: _page,
            pageSize: InferHub.modelPageSize,
          )
        : null;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              t(context, 'inferhub.pickTitle'),
              style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: t(context, 'inferhub.modelSearchHint'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _body(page)),
          _footer(page),
        ],
      ),
    );
  }

  Widget _body(ModelPage? page) {
    final error = _error;
    if (error != null) {
      return _center(
        icon: Icons.cloud_off,
        text: t(context, 'inferhub.modelLoadFailed'),
        action: TextButton(
          onPressed: _load,
          child: Text(t(context, 'common.retry')),
        ),
      );
    }
    if (_models == null || page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (page.models.isEmpty) {
      return _center(
        icon: Icons.search_off,
        text: t(context, 'inferhub.modelEmpty'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: page.models.length,
      itemBuilder: (context, i) => _tile(page.models[i]),
    );
  }

  Widget _tile(InferHubModel m) {
    final selected = m.id == widget.current;
    return ListTile(
      dense: true,
      title: Text(
        m.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: SibleTheme.textPrimary,
        ),
      ),
      subtitle: _subtitle(m),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.free)
            StatusChip(
              label: t(context, 'inferhub.freeBadge'),
              color: SibleTheme.success,
            )
          else
            _priceText(m),
          if (selected) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.check_circle,
              size: 18,
              color: SibleTheme.success,
            ),
          ],
        ],
      ),
      onTap: () => Navigator.pop(context, m.id),
    );
  }

  Widget? _subtitle(InferHubModel m) {
    final ctx = m.contextLength;
    if (ctx == null || ctx <= 0) return null;
    final size = ctx >= 1000 ? '${(ctx / 1000).round()}k' : '$ctx';
    return Text(
      '$size ${t(context, 'inferhub.modelContext')}',
      style: const TextStyle(color: SibleTheme.textSecondary, fontSize: 10.5),
    );
  }

  Widget _priceText(InferHubModel m) {
    String f(double? v) => v == null ? '?' : v.toStringAsFixed(2);
    if (m.inputPrice == null && m.outputPrice == null) {
      return const SizedBox.shrink();
    }
    return Text(
      '\$${f(m.inputPrice)} / \$${f(m.outputPrice)}',
      style: const TextStyle(color: SibleTheme.textSecondary, fontSize: 10.5),
    );
  }

  Widget _footer(ModelPage? page) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page == null || page.page <= 0
                ? null
                : () => setState(() => _page = page.page - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            page == null ? '' : '${page.page + 1} / ${page.totalPages}',
            style: const TextStyle(
              color: SibleTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: page == null || page.page >= page.totalPages - 1
                ? null
                : () => setState(() => _page = page.page + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _center({
    required IconData icon,
    required String text,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: SibleTheme.textSecondary),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SibleTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      ),
    );
  }
}
