import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/navigation/panel_flows.dart';
import '../../../design/seline.dart';
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
  bool _loading = true;

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
    if (!mounted) return;
    setState(() {
      _results = list;
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
              : ListView.builder(
                  itemCount: _results.length + 1,
                  itemBuilder: (context, i) {
                    if (i == _results.length) {
                      return ListTile(
                        leading: const Icon(LucideIcons.plus),
                        title: const Text('Create new partner'),
                        onTap: () async {
                          await showPartnerFormPanel(
                            context,
                            churchId: widget.churchId,
                            uid: widget.uid,
                          );
                          if (mounted) _load(_controller.text.trim());
                        },
                      );
                    }
                    final p = _results[i];
                    return ListTile(
                      title: Text(p.fullName),
                      subtitle: Text(p.displayLabel),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
