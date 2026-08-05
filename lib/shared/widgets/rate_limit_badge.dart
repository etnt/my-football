import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

/// Small app-bar badge showing "requests remaining today" (e.g. 87/100).
class RateLimitBadge extends ConsumerWidget {
  const RateLimitBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(rateLimitProvider);
    final remaining = info?.remainingToday;

    final low = remaining != null && remaining <= 10;
    final color = low ? Theme.of(context).colorScheme.error : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_usage, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              info?.dailyLabel ?? '—/—',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
