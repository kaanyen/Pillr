import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../design/seline.dart';

import '../../../core/errors/error_handler.dart';
import '../data/platform_repository.dart';
import '../providers/platform_providers.dart';

class PlatformChurchesScreen extends ConsumerStatefulWidget {
  const PlatformChurchesScreen({super.key});

  @override
  ConsumerState<PlatformChurchesScreen> createState() => _PlatformChurchesScreenState();
}

class _PlatformChurchesScreenState extends ConsumerState<PlatformChurchesScreen> {
  final _bootstrapEmail = TextEditingController();
  String _bootstrapRole = 'pastor';
  String? _formError;
  bool _inviting = false;

  @override
  void dispose() {
    _bootstrapEmail.dispose();
    super.dispose();
  }

  Future<void> _sendBootstrapInvite() async {
    setState(() {
      _formError = null;
      _inviting = true;
    });
    try {
      await ref.read(platformRepositoryProvider).createBootstrapInvite(
            email: _bootstrapEmail.text,
            role: _bootstrapRole,
          );
      if (mounted) {
        _bootstrapEmail.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bootstrap invite sent.')),
        );
      }
    } catch (e) {
      setState(() => _formError = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _toggleActive(PlatformChurchSummary row) async {
    try {
      await ref.read(platformRepositoryProvider).setChurchActive(
            churchId: row.churchId,
            isActive: !row.isActive,
          );
      ref.invalidate(platformChurchesListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeAuthException(e))),
        );
      }
    }
  }

  void _showDetail(PlatformChurchSummary row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.all(SelSpace.x6),
              children: [
                Text(row.name, style: SelType.title),
                const SizedBox(height: SelSpace.x2),
                SelectableText('ID: ${row.churchId}', style: SelType.small),
                const SizedBox(height: SelSpace.x4),
                if (row.logoUrl != null && row.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                    child: CachedNetworkImage(
                      imageUrl: row.logoUrl!,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                const SizedBox(height: SelSpace.x4),
                Text(
                  'Contact',
                  style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    row.primaryContactName,
                    row.contactEmail,
                    row.contactPhone,
                  ].where((e) => e != null && e.toString().trim().isNotEmpty).join('\n'),
                  style: SelType.body,
                ),
                const SizedBox(height: SelSpace.x4),
                Text(
                  'Location',
                  style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    row.address,
                    row.city,
                    row.region,
                    row.country,
                  ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', '),
                  style: SelType.body,
                ),
                const SizedBox(height: SelSpace.x4),
                Text('Active users: ${row.activeUsers}', style: SelType.body),
                Text('Currency: ${row.currency ?? '—'}', style: SelType.body),
                Text(
                  'Setup completed: ${row.churchSetupCompletedAt != null ? 'yes' : 'no'}',
                  style: SelType.body,
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(platformChurchesListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/overview'),
        ),
        title: const Text('Platform · Churches'),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(platformChurchesListProvider),
            child: ListView(
              padding: const EdgeInsets.all(SelSpace.x6),
              children: [
                SelCard(clip: true, 
                  child: Padding(
                    padding: const EdgeInsets.all(SelSpace.x6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Invite new church', style: SelType.subtitle),
                        const SizedBox(height: SelSpace.x2),
                        TextField(
                          controller: _bootstrapEmail,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: SelSpace.x2),
                        DropdownButtonFormField<String>(
                          initialValue: _bootstrapRole,
                          decoration: const InputDecoration(
                            labelText: 'First user role',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pastor', child: Text('Pastor')),
                            DropdownMenuItem(value: 'admin', child: Text('Church admin')),
                          ],
                          onChanged: (v) => setState(() => _bootstrapRole = v ?? 'pastor'),
                        ),
                        if (_formError != null) ...[
                          const SizedBox(height: SelSpace.x2),
                          Text(_formError!, style: SelType.small.copyWith(color: Sel.ink)),
                        ],
                        const SizedBox(height: SelSpace.x4),
                        FilledButton(
                          onPressed: _inviting ? null : _sendBootstrapInvite,
                          child: _inviting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Send bootstrap invite'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: SelSpace.x4),
                Text('${rows.length} churches', style: SelType.small),
                const SizedBox(height: SelSpace.x2),
                ...rows.map((row) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: SelSpace.x2),
                    child: ListTile(
                      leading: row.logoUrl != null && row.logoUrl!.isNotEmpty
                          ? CircleAvatar(
                              backgroundImage: CachedNetworkImageProvider(row.logoUrl!),
                            )
                          : const CircleAvatar(child: Icon(LucideIcons.church)),
                      title: Text(row.name),
                      subtitle: Text(
                        '${row.activeUsers} active · ${row.isActive ? 'Active' : 'Suspended'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.copy, size: 20),
                            tooltip: 'Copy church ID',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: row.churchId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Church ID copied')),
                              );
                            },
                          ),
                          Switch(
                            value: row.isActive,
                            onChanged: (_) => _toggleActive(row),
                          ),
                        ],
                      ),
                      onTap: () => _showDetail(row),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
