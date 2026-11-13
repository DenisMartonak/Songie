import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';

/// Back (when there is somewhere to go back to) and a page's [title].
class PageBar extends StatelessWidget {
  const PageBar(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Row(
        children: [
          if (context.canPop())
            IconButton(
              tooltip: 'Back',
              color: colors.text,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            )
          else
            const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
