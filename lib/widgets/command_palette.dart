import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ma5zony/utils/constants.dart';

// ── Route entry model (also used by main_layout for nav structure) ─────────────

@immutable
class NavRouteEntry {
  final IconData icon;
  final String label;
  final String path;

  const NavRouteEntry({
    required this.icon,
    required this.label,
    required this.path,
  });
}

// ── Command Palette ─────────────────────────────────────────────────────────────

class CommandPalette extends StatefulWidget {
  final List<NavRouteEntry> entries;

  const CommandPalette({super.key, required this.entries});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  // Recent navigations survive dialog open/close within the session.
  static final List<NavRouteEntry> _sessionRecent = [];

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  late List<NavRouteEntry> _results;
  int _selectedIndex = 0;
  bool _hasQuery = false;

  @override
  void initState() {
    super.initState();
    _results = _defaultResults();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<NavRouteEntry> _defaultResults() {
    if (_sessionRecent.isNotEmpty) {
      // Recent first, then remaining routes
      final recentPaths = _sessionRecent.map((e) => e.path).toSet();
      final others = widget.entries.where((e) => !recentPaths.contains(e.path));
      return [..._sessionRecent, ...others];
    }
    return List.of(widget.entries);
  }

  void _onQueryChanged(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _hasQuery = false;
        _results = _defaultResults();
        _selectedIndex = 0;
      });
      return;
    }

    final scored = widget.entries
        .map((e) => (entry: e, score: _fuzzyScore(q, e.label.toLowerCase())))
        .where((r) => r.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    setState(() {
      _hasQuery = true;
      _results = scored.map((r) => r.entry).toList();
      _selectedIndex = 0;
    });
  }

  /// Returns a score > 0 if [query] matches [target]. Higher = better.
  int _fuzzyScore(String query, String target) {
    if (target == query) return 100;
    if (target.startsWith(query)) return 50;
    if (target.contains(query)) return 30;
    // Word-starts match: "fo" matches "Forecasts" via 'f'+'o'
    final words = target.split(RegExp(r'\s+'));
    if (words.any((w) => w.startsWith(query))) return 20;
    // Characters-in-order fuzzy
    int qi = 0;
    for (int i = 0; i < target.length && qi < query.length; i++) {
      if (target[i] == query[qi]) qi++;
    }
    if (qi == query.length) return max(1, 10 - (target.length - query.length));
    return 0;
  }

  void _navigate(NavRouteEntry entry) {
    // Update recent list
    _sessionRecent.removeWhere((e) => e.path == entry.path);
    _sessionRecent.insert(0, entry);
    if (_sessionRecent.length > 6) _sessionRecent.removeLast();

    Navigator.of(context).pop();
    context.go(entry.path);
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, _results.length - 1);
    setState(() => _selectedIndex = next);
    // Scroll to keep selected item visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        const itemH = 48.0;
        final target = next * itemH;
        final viewportH = _scrollController.position.viewportDimension;
        final current = _scrollController.offset;
        if (target < current) {
          _scrollController.jumpTo(target);
        } else if (target + itemH > current + viewportH) {
          _scrollController.jumpTo(target + itemH - viewportH);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isApple = platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    final kbdHint = isApple ? '⌘K' : 'Ctrl K';

    return GestureDetector(
      // Dismiss when tapping outside the palette box
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {}, // prevent outer tap from closing
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: AppColors.divider),
                  boxShadow: AppShadows.lifted,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Search input ──────────────────────────────────
                    _SearchInput(
                      controller: _controller,
                      focusNode: _focusNode,
                      kbdHint: kbdHint,
                      onChanged: _onQueryChanged,
                      onKeyEvent: (event) {
                        if (event is! KeyDownEvent) return KeyEventResult.ignored;
                        switch (event.logicalKey) {
                          case LogicalKeyboardKey.arrowDown:
                            _moveSelection(1);
                            return KeyEventResult.handled;
                          case LogicalKeyboardKey.arrowUp:
                            _moveSelection(-1);
                            return KeyEventResult.handled;
                          case LogicalKeyboardKey.enter:
                            if (_results.isNotEmpty) {
                              _navigate(_results[_selectedIndex]);
                            }
                            return KeyEventResult.handled;
                          case LogicalKeyboardKey.escape:
                            Navigator.of(context).pop();
                            return KeyEventResult.handled;
                          default:
                            return KeyEventResult.ignored;
                        }
                      },
                    ),
                    const Divider(height: 1),
                    // ── Results list ──────────────────────────────────
                    if (_results.isEmpty)
                      _EmptyState(hasQuery: _hasQuery)
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.builder(
                          controller: _scrollController,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _results.length,
                          itemBuilder: (_, i) => _ResultItem(
                            entry: _results[i],
                            isSelected: i == _selectedIndex,
                            isRecent: !_hasQuery &&
                                _sessionRecent.any((r) => r.path == _results[i].path),
                            onTap: () => _navigate(_results[i]),
                            onHover: () => setState(() => _selectedIndex = i),
                          ),
                        ),
                      ),
                    // ── Footer hints ──────────────────────────────────
                    _Footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Search input row ──────────────────────────────────────────────────────────

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String kbdHint;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.kbdHint,
    required this.onChanged,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: onKeyEvent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.textSubdued),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: AppTextStyles.body.copyWith(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Go to...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: AppRadius.sharp,
                color: AppColors.surfaceSubtle,
              ),
              child: Text(kbdHint, style: AppTextStyles.kbd),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result item ───────────────────────────────────────────────────────────────

class _ResultItem extends StatelessWidget {
  final NavRouteEntry entry;
  final bool isSelected;
  final bool isRecent;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _ResultItem({
    required this.entry,
    required this.isSelected,
    required this.isRecent,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: isSelected ? AppColors.primaryLight : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surfaceSubtle,
                  borderRadius: AppRadius.sharp,
                ),
                child: Icon(
                  entry.icon,
                  size: 16,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    color: isSelected ? AppColors.textPrimary : AppColors.textPrimary,
                  ),
                ),
              ),
              if (isRecent)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.history, size: 14, color: AppColors.textSubdued),
                ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: AppRadius.sharp,
                  ),
                  child: Text('↵', style: AppTextStyles.kbd),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 32, color: AppColors.textSubdued.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            hasQuery ? 'No matching pages' : 'Start typing to search',
            style: AppTextStyles.body.copyWith(color: AppColors.textSubdued),
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          _KbdChip('↑↓'),
          const SizedBox(width: 4),
          Text('navigate', style: AppTextStyles.monoSm),
          const SizedBox(width: 12),
          _KbdChip('↵'),
          const SizedBox(width: 4),
          Text('open', style: AppTextStyles.monoSm),
          const SizedBox(width: 12),
          _KbdChip('Esc'),
          const SizedBox(width: 4),
          Text('close', style: AppTextStyles.monoSm),
        ],
      ),
    );
  }
}

class _KbdChip extends StatelessWidget {
  final String label;
  const _KbdChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: AppRadius.sharp,
        color: AppColors.surfaceSubtle,
      ),
      child: Text(label, style: AppTextStyles.kbd),
    );
  }
}
