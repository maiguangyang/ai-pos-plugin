import 'package:flutter/material.dart';

const _actionItemSpacing = 16.0;
const _actionColumnCount = 4;

@immutable
final class FloatingActionSheetItem<T> {
  const FloatingActionSheetItem({
    required this.value,
    required this.surfaceKey,
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final Key surfaceKey;
  final IconData icon;
  final String label;
  final bool enabled;
}

/// Shared content layout for floating workspace action sheets.
final class FloatingActionSheetContent<T> extends StatelessWidget {
  const FloatingActionSheetContent({
    super.key,
    required this.surfaceKey,
    required this.introductionKey,
    required this.leading,
    required this.title,
    required this.description,
    required this.items,
    required this.onSelected,
  });

  final Key surfaceKey;
  final Key introductionKey;
  final Widget leading;
  final String title;
  final String description;
  final List<FloatingActionSheetItem<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleDescription = description.trim();
    final rowCount =
        (items.length + _actionColumnCount - 1) ~/ _actionColumnCount;
    return Material(
      key: surfaceKey,
      color: colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: colors.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Semantics(
                  key: introductionKey,
                  header: true,
                  child: Row(
                    children: [
                      SizedBox.square(dimension: 44, child: leading),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (visibleDescription.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                visibleDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w400,
                                      height: 1.4,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: colors.surfaceContainerLow,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var row = 0; row < rowCount; row += 1) ...[
                          if (row > 0)
                            const SizedBox(height: _actionItemSpacing),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var column = 0;
                                column < _actionColumnCount;
                                column += 1
                              )
                                Expanded(
                                  child: _buildActionCell(
                                    row * _actionColumnCount + column,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCell(int index) {
    if (index >= items.length) return const SizedBox.shrink();
    final item = items[index];
    return _FloatingActionSheetItem(
      item: item,
      onTap: () => onSelected(item.value),
    );
  }
}

final class _FloatingActionSheetItem<T> extends StatelessWidget {
  const _FloatingActionSheetItem({required this.item, required this.onTap});

  final FloatingActionSheetItem<T> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            key: item.surfaceKey,
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: item.enabled ? onTap : null,
              child: SizedBox.square(
                dimension: 68,
                child: Icon(
                  item.icon,
                  size: 27,
                  color: item.enabled
                      ? colors.onSurface
                      : colors.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: item.enabled
                  ? colors.onSurfaceVariant
                  : colors.onSurfaceVariant.withValues(alpha: 0.38),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
