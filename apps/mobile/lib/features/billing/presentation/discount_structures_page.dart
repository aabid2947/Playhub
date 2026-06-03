import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/features/billing/presentation/discount_structure_form_page.dart';
import 'package:playhub/core/error_messages.dart';

class DiscountStructuresPage extends ConsumerWidget {
  const DiscountStructuresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRows = ref.watch(discountStructuresProvider);
    return Scaffold(
      body: asyncRows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (rows) {
          if (rows.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(discountStructuresProvider),
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _DiscountTile(item: rows[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const DiscountStructureFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New discount'),
      ),
    );
  }
}

class _DiscountTile extends StatelessWidget {
  const _DiscountTile({required this.item});
  final DiscountStructure item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.local_offer_outlined),
      title: Text(item.name),
      subtitle: Text(
        [
          item.type.label,
          item.summary,
          if (item.description != null && item.description!.isNotEmpty)
            item.description,
        ].whereType<String>().join(' · '),
      ),
      trailing: !item.isActive
          ? const Chip(
              label: Text('inactive'),
              visualDensity: VisualDensity.compact,
            )
          : null,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DiscountStructureFormPage(existing: item),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_offer_outlined, size: 48),
            const SizedBox(height: 12),
            Text('No discounts yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Define a sibling, scholarship, or promo discount, then '
              'assign it to a student or a batch.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
