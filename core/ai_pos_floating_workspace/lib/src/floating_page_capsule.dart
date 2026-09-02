import 'package:flutter/material.dart';

/// Shared mini-app-style capsule for floating workspace page shells.
final class FloatingPageCapsule extends StatelessWidget {
  const FloatingPageCapsule({
    super.key,
    required this.surfaceKey,
    required this.moreButtonKey,
    required this.closeButtonKey,
    required this.menuOpen,
    required this.onMore,
    required this.onClose,
  });

  final Key surfaceKey;
  final Key moreButtonKey;
  final Key closeButtonKey;
  final bool menuOpen;
  final VoidCallback onMore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    return SizedBox(
      width: 96,
      height: 48,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Ink(
              key: surfaceKey,
              width: 88,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.78),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.52),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            Row(
              children: [
                IconButton(
                  key: moreButtonKey,
                  onPressed: onMore,
                  isSelected: menuOpen,
                  tooltip: localizations.moreButtonTooltip,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(Icons.more_horiz_rounded, size: 22),
                ),
                IconButton(
                  key: closeButtonKey,
                  onPressed: onClose,
                  tooltip: localizations.closeButtonTooltip,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(Icons.adjust_rounded, size: 21),
                ),
              ],
            ),
            IgnorePointer(
              child: SizedBox(
                width: 1,
                height: 16,
                child: ColoredBox(
                  color: colors.outlineVariant.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
