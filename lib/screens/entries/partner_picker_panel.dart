import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/navigation/panel_flows.dart';
import '../../../design/seline.dart';
import '../../features/maintenance/domain/data_health.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/partners/providers/partners_providers.dart';

/// Search and pick a partner — body for [showPartnerPickerPanel].
class PartnerPickerPanel extends ConsumerStatefulWidget {
  const PartnerPickerPanel({
    super.key,
    required this.churchId,
    required this.uid,
  });

  final String churchId;
  final String uid;

  @override
  ConsumerState<PartnerPickerPanel> createState() => _PartnerPickerPanelState();
}

class _PartnerPickerPanelState extends ConsumerState<PartnerPickerPanel> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<Partner> _results = [];
  List<PartnerSuggestion> _suggestions = const [];
  bool _loading = true;

  /// Every active partner, loaded once for "Did you mean…?". The search
  /// itself stays a server prefix query.
  List<Partner>? _book;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load('');
  }

  Future<void> _load(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final repo = ref.read(partnersRepositoryProvider);
    final list = await repo.searchPartners(widget.churchId, q);
    var suggestions = const <PartnerSuggestion>[];
    if (q.length >= 3) {
      try {
        _book ??= await repo.fetchAllActivePartners(widget.churchId);
        suggestions = suggestPartners(
          q,
          _book!,
          exclude: {for (final p in list) p.id},
        );
      } catch (_) {
        // Suggestions are a help, not the search. Without them the list
        // still works.
      }
    }
    if (!mounted) return;
    setState(() {
      _results = list;
      _suggestions = suggestions;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelField(
          controller: _controller,
          hint: 'Search by name, member ID, fellowship…',
          prefixIcon: LucideIcons.search,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 280), () {
              if (mounted) _load(v.trim());
            });
          },
        ),
        const SizedBox(height: SelSpace.x4),
        SizedBox(
          height: 360,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    for (final p in _results)
                      ListTile(
                        title: Text(p.fullName),
                        subtitle: Text(p.displayLabel),
                        onTap: () => Navigator.pop(context, p),
                      ),
                    if (_suggestions.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SelSpace.x4,
                          SelSpace.x3,
                          SelSpace.x4,
                          SelSpace.x1,
                        ),
                        child: Text(
                          _results.isEmpty
                              ? 'No exact match. Did you mean…'
                              : 'Did you mean…',
                          style: SelType.small,
                        ),
                      ),
                      for (final s in _suggestions)
                        ListTile(
                          leading: const Icon(LucideIcons.userCheck),
                          title: Text(s.partner.fullName),
                          subtitle: Text(
                            '${s.partner.displayLabel}  ·  ${s.reason}',
                          ),
                          onTap: () => Navigator.pop(context, s.partner),
                        ),
                    ],
                    ListTile(
                      leading: const Icon(LucideIcons.plus),
                      title: const Text('Create new partner'),
                      subtitle: _suggestions.isEmpty
                          ? null
                          : const Text('Only if none of the above is them.'),
                      onTap: () async {
                        await showPartnerFormPanel(
                          context,
                          churchId: widget.churchId,
                          uid: widget.uid,
                        );
                        if (mounted) _load(_controller.text.trim());
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
