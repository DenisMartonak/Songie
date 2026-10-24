import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/log.dart';
import '../../../core/result.dart';
import '../../../providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/contrast.dart';
import '../../../theme/theme_repository.dart';
import '../../motion/fade_slide_in.dart';
import '../../motion/pressable.dart';
import '../../widgets/page_snack_bar.dart';
import 'theme_editor_page.dart';
import 'theme_file.dart';

/// Built-in and saved themes.
final _themesProvider = StreamProvider.autoDispose<List<ThemeEntry>>(
  (ref) => ref.watch(themeRepositoryProvider).watchAll(),
);

/// Where the editor for theme [id] lives.
String themeEditorLocation(String id) =>
    '/settings/themes/edit/${Uri.encodeComponent(id)}';

/// Every theme as a card; tapping one applies it (the app's colours tween
/// over `Motion.colour`). Each card's menu edits, duplicates, exports or
/// deletes it; the page makes new themes and imports theme files.
class ThemesPage extends ConsumerWidget {
  const ThemesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final themes = ref.watch(_themesProvider).value ?? const [];
    final activeId = ref.watch(activeThemeProvider).value?.id;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
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
                  Text(
                    'Themes',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const Key('themes.new'),
                    onPressed: () =>
                        context.push(themeEditorLocation(newThemeId)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New theme'),
                  ),
                  TextButton.icon(
                    key: const Key('themes.import'),
                    onPressed: () => _import(context, ref),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Import'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              delegate: SliverChildBuilderDelegate(
                childCount: themes.length,
                (context, i) => FadeSlideIn(
                  index: i,
                  id: themes[i].id,
                  child: _ThemeCard(
                    theme: themes[i],
                    active: themes[i].id == activeId,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final snacks = PageSnackBars.of(context);
    final path = await ref.read(themeFilePickerProvider)();
    if (path == null) return;
    final r = await ref.read(themeFilesProvider).importFile(path);
    switch (r) {
      case Ok():
        // A font the file brought is usable at once, as after the editor's
        // Import font….
        ref.invalidate(resolvedFontFamilyProvider);
        ref.invalidate(importedFontsProvider);
        snacks.show(content: const Text('Theme imported'));
      case Err(:final failure):
        snacks.show(content: Text(failure.message));
    }
  }
}

enum _CardAction { edit, duplicate, export, delete }

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.theme, required this.active});

  final ThemeEntry theme;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final spec = theme.spec;
    // Rebuilt when the imported fonts change, so a newly registered font
    // shows.
    ref.watch(importedFontsProvider);
    final family = ref.watch(fontServiceProvider).resolveFamily(spec);
    final cardRadius = BorderRadius.circular(12);
    final previewRadius = BorderRadius.circular(
      spec.cornerRadius.clamp(0.0, 24.0) / 2,
    );
    final text = readableOn(spec.background, preferred: spec.text);
    return Material(
      key: Key('themes.card.${theme.id}'),
      color: colors.surface,
      borderRadius: cardRadius,
      child: Pressable(
        borderRadius: cardRadius,
        onTap: () => ref.read(themeRepositoryProvider).setActive(theme.id),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: spec.background,
                    borderRadius: BorderRadius.circular(8),
                    border: active
                        ? Border.all(color: colors.accent, width: 2)
                        : null,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good evening',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontFamily: family,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: spec.surface,
                          borderRadius: previewRadius,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: 0.6,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: text.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: spec.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        theme.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (active)
                      Icon(
                        Icons.check_circle_rounded,
                        key: const Key('themes.activeCheck'),
                        color: colors.accent,
                        size: 20,
                        semanticLabel: 'Active theme',
                      ),
                    _menu(context, ref, colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref, SongiesColors colors) =>
      PopupMenuButton<_CardAction>(
        key: Key('themes.menu.${theme.id}'),
        tooltip: 'More',
        iconColor: colors.text,
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (a) => _act(context, ref, a),
        itemBuilder: (context) => [
          const PopupMenuItem(value: _CardAction.edit, child: Text('Edit')),
          const PopupMenuItem(
            value: _CardAction.duplicate,
            child: Text('Duplicate'),
          ),
          const PopupMenuItem(value: _CardAction.export, child: Text('Export')),
          if (!theme.builtIn)
            const PopupMenuItem(
              value: _CardAction.delete,
              child: Text('Delete'),
            ),
        ],
      );

  Future<void> _act(BuildContext context, WidgetRef ref, _CardAction a) async {
    final snacks = PageSnackBars.of(context);
    final repo = ref.read(themeRepositoryProvider);
    switch (a) {
      case _CardAction.edit:
        await context.push(themeEditorLocation(theme.id));
      case _CardAction.duplicate:
        if (await repo.duplicate(theme.id) case Err(:final failure)) {
          snacks.show(content: Text(failure.message));
        }
      case _CardAction.export:
        await _export(ref, snacks);
      case _CardAction.delete:
        if (!await _confirmDelete(context)) return;
        if (await repo.delete(theme.id) case Err(:final failure)) {
          snacks.show(content: Text(failure.message));
        }
    }
  }

  Future<void> _export(WidgetRef ref, PageSnackBars snacks) async {
    final save = ref.read(themeFileSaverProvider);
    try {
      final file = await ref.read(themeFilesProvider).fileFor(theme);
      if (await save(themeFileName(theme.name), file.encode())) {
        snacks.show(content: const Text('Theme exported'));
      }
    } catch (e, s) {
      AppLog.e('Exporting theme ${theme.id} failed', e, s);
      snacks.show(content: const Text("Couldn't export the theme"));
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete theme?'),
        content: Text('"${theme.name}" will be deleted on all your devices.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
