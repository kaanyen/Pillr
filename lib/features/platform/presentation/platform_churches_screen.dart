import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../common/widgets/pillr_surface_card.dart';
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
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(row.name, style: AppTypography.heading),
                const SizedBox(height: AppSpacing.sm),
                SelectableText('ID: ${row.churchId}', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.md),
                if (row.logoUrl != null && row.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: CachedNetworkImage(
                      imageUrl: row.logoUrl!,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Contact',
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    row.primaryContactName,
                    row.contactEmail,
                    row.contactPhone,
                  ].where((e) => e != null && e.toString().trim().isNotEmpty).join('\n'),
                  style: AppTypography.body,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Location',
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    row.address,
                    row.city,
                    row.region,
                    row.country,
                  ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', '),
                  style: AppTypography.body,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Active users: ${row.activeUsers}', style: AppTypography.body),
                Text('Currency: ${row.currency ?? '—'}', style: AppTypography.body),
                Text(
                  'Setup completed: ${row.churchSetupCompletedAt != null ? 'yes' : 'no'}',
                  style: AppTypography.body,
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
          onPressed: () => context.go('/dashboard'),
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
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                PillrSurfaceCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Invite new church', style: AppTypography.headingSm),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _bootstrapEmail,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: AppSpacing.sm),
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
                          const SizedBox(height: AppSpacing.sm),
                          Text(_formError!, style: AppTypography.caption.copyWith(color: AppColors.ink)),
                        ],
                        const SizedBox(height: AppSpacing.md),
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
                const SizedBox(height: AppSpacing.md),
                Text('${rows.length} churches', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.sm),
                ...rows.map((row) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
