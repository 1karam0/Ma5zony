import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ma5zony/features/onboarding/tour_targets.dart';
import 'package:ma5zony/utils/constants.dart';

/// A single step in a guided spotlight tour. Points at a registered
/// [TourTargets] anchor and shows a small popover with title + description.
class SpotlightStep {
  final String anchorId;
  final String title;
  final String description;

  /// Optional navigation route to push *before* showing this step (so we can
  /// guide users across screens). Null → no navigation.
  final String? navigateTo;

  /// Padding around the highlighted shape, in logical pixels.
  final double padding;

  /// Optional predicate evaluated periodically while this step is shown. As
  /// soon as it returns `true`, the coach automatically advances to the next
  /// step. Use this to detect that the user has fulfilled the task (e.g. a
  /// supplier was added, a product was created).
  ///
  /// The predicate is called every ~400ms. Keep it cheap (no I/O) — just
  /// check a captured state reference. Use a closure that captures AppState
  /// (or any other object) at tour-start time rather than reading from a
  /// BuildContext, so navigation between routes cannot invalidate it.
  final bool Function()? completeWhen;

  const SpotlightStep({
    required this.anchorId,
    required this.title,
    required this.description,
    this.navigateTo,
    this.padding = 8,
    this.completeWhen,
  });
}

/// Spotlight overlay that dims the screen *around* a target widget while
/// leaving the target itself fully click-through, so the user can actually
/// complete the action the step is asking about. A small popover card
/// explains the step and offers Next / Skip controls.
///
/// Use [SpotlightCoach.start] to run a list of steps.
class SpotlightCoach {
  /// Runs the spotlight sequence. Caller may pass an [onNavigate] function
  /// (typically `(path) => context.go(path)`) so steps can jump between
  /// screens between their highlights.
  static Future<void> start(
    BuildContext context,
    List<SpotlightStep> steps, {
    required void Function(String path) onNavigate,
  }) async {
    if (steps.isEmpty) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    // Capture the root NavigatorState early (before any route changes).
    // This stays valid for the app lifetime and lets us dismiss open
    // dialogs/bottom-sheets before each inter-route navigation so they
    // don't bleed through to the next step's page.
    final navigator = Navigator.of(context, rootNavigator: true);
    // Shell navigator (non-root). Used to detect when a dialog/modal is
    // currently open so we can suppress the pulse ring — the ring lives in
    // the root overlay (above everything) and would float on top of any
    // dialog opened by a step action.
    final shellNav = Navigator.of(context);

    int index = 0;
    late OverlayEntry entry;
    Timer? pollTimer;
    Timer? repositionTimer;
    bool removed = false;

    void disposeTimers() {
      pollTimer?.cancel();
      pollTimer = null;
      repositionTimer?.cancel();
      repositionTimer = null;
    }

    void safeRemove() {
      if (removed) return;
      removed = true;
      disposeTimers();
      entry.remove();
    }

    void render() {
      if (!removed) entry.markNeedsBuild();
    }

    Future<void> goToStep(int next) async {
      disposeTimers();
      if (next >= steps.length) {
        safeRemove();
        return;
      }
      final step = steps[next];
      // Navigate first if requested.
      if (step.navigateTo != null) {
        // Dismiss any open dialog / bottom-sheet before changing route.
        // showDialog() pushes a route onto the root navigator that GoRouter's
        // go() does NOT automatically pop, causing dialogs to bleed into
        // the next step's page. A single pop() closes the topmost dialog.
        try {
          if (navigator.canPop()) navigator.pop();
        } catch (_) {}
        onNavigate(step.navigateTo!);
        // Give the target screen time to mount and lay out its widgets.
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (removed) return;
      index = next;
      render();

      // Poll the success predicate so the tour auto-advances the moment the
      // user fulfills the task (e.g. adds a supplier, creates a product).
      // NOTE: predicates are plain closures that capture AppState directly —
      // no BuildContext involved — so GoRouter navigation (which disposes the
      // originating route's context) cannot kill the timer.
      //
      // We only start polling when the condition is NOT already satisfied.
      // This prevents instant-skip on accounts that already have data (e.g.
      // replaying the tour on an existing account that already has suppliers).
      if (step.completeWhen != null && !step.completeWhen!()) {
        pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
          if (removed) return;
          try {
            if (step.completeWhen!()) goToStep(index + 1);
          } catch (_) {
            // Predicate threw unexpectedly. Ignore — retry on next tick.
          }
        });
      }

      // Live-reposition the cutout. The highlighted button may move when a
      // dialog opens / closes or when its parent rebuilds. Instead of blindly
      // rebuilding the whole overlay 8×/sec (which ran the corner-selection
      // algorithm and re-laid-out the card every tick — the main cause of tour
      // lag during navigation), we poll only the target rect (cheap) and
      // rebuild the overlay ONLY when it actually changed.
      Rect? lastRect = TourTargets.instance.rectFor(step.anchorId);
      repositionTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (_) {
          if (removed) return;
          final current = TourTargets.instance.rectFor(step.anchorId);
          if (!_rectsClose(lastRect, current)) {
            lastRect = current;
            render();
          }
        },
      );

    }

    entry = OverlayEntry(
      builder: (ctx) {
        final step = steps[index];
        final rect = TourTargets.instance.rectFor(step.anchorId);
        return _SpotlightLayer(
          step: step,
          targetRect: rect,
          stepIndex: index,
          totalSteps: steps.length,
          onNext: () => goToStep(index + 1),
          onSkip: safeRemove,
          shellNavigator: shellNav,
        );
      },
    );

    overlay.insert(entry);
    // Kick off the first step (navigation aware).
    await goToStep(0);
  }
}

/// Returns true when two optional rects are effectively the same position
/// (within 0.5px on every edge), so the reposition timer can skip a rebuild.
bool _rectsClose(Rect? a, Rect? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  const eps = 0.5;
  return (a.left - b.left).abs() < eps &&
      (a.top - b.top).abs() < eps &&
      (a.width - b.width).abs() < eps &&
      (a.height - b.height).abs() < eps;
}

class _SpotlightLayer extends StatefulWidget {
  final SpotlightStep step;
  final Rect? targetRect;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  /// Shell navigator (non-root). When it can pop, a dialog is open and the
  /// pulse ring should be hidden so it doesn't float above the dialog.
  final NavigatorState? shellNavigator;

  const _SpotlightLayer({
    required this.step,
    required this.targetRect,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
    this.shellNavigator,
  });

  @override
  State<_SpotlightLayer> createState() => _SpotlightLayerState();
}

class _SpotlightLayerState extends State<_SpotlightLayer> {
  // User-applied drag delta from the drag handle. Reset to zero whenever the
  // step index changes so the card snaps to the new step's best corner.
  Offset _dragOffset = Offset.zero;

  // Set to true the moment the user taps the highlighted anchor. This hides
  // the ring immediately on click — before the resulting dialog even opens —
  // so the ring never floats on top of a dialog or other opened surface.
  bool _ringTapped = false;

  @override
  void didUpdateWidget(covariant _SpotlightLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepIndex != widget.stepIndex) {
      _dragOffset = Offset.zero;
      _ringTapped = false; // reset for the new step
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final isLast = widget.stepIndex == widget.totalSteps - 1;
    final step = widget.step;
    final targetRect = widget.targetRect;

    // ─── Non-blocking design ─────────────────────────────────────────────
    // No dim, no cutout, no modal barrier. The entire page (and any dialogs
    // opened during a step) is fully interactive. We render only two things:
    //   1. A subtle pulsing ring around the spotlighted anchor (when found,
    //      and only when its center is actually visible). Purely visual.
    //   2. A compact card pinned to the left side of the viewport with the
    //      step text, a Next button (always available), and a Skip control.
    // ────────────────────────────────────────────────────────────────────
    const cardWidth = 300.0;
    const cardHeight = 300.0; // estimated height used only for overlap scoring
    const margin = 16.0;

    // ── Dynamic corner selection ──────────────────────────────────────────
    // Evaluate 4 screen corners; pick the one that (a) does NOT overlap the
    // highlighted anchor rect and (b) is farthest from the anchor centre.
    // Returns a record: (left, isBottomAnchor).
    // Bottom corners use Positioned(bottom:) so the card grows upward and
    // can never be clipped by the viewport edge regardless of content height.
    ({double left, double top, bool isBottom}) bestCorner() {
      // Scoring uses a representative rect; whether it's top- or
      // bottom-anchored doesn't affect the left position.
      final corners = [
        (left: margin,                          top: margin,                          isBottom: false), // top-left
        (left: size.width - cardWidth - margin, top: margin,                          isBottom: false), // top-right
        (left: margin,                          top: size.height - cardHeight - margin, isBottom: true),  // bottom-left
        (left: size.width - cardWidth - margin, top: size.height - cardHeight - margin, isBottom: true),  // bottom-right
      ];
      final tr = targetRect;
      if (tr == null || tr.isEmpty) return corners[2]; // bottom-left default

      final anchorCenter = tr.center;
      final inflated = tr.inflate(step.padding + 20.0);

      var best = corners[0];
      double bestScore = double.negativeInfinity;
      for (final c in corners) {
        final cardRect = Rect.fromLTWH(c.left, c.top, cardWidth, cardHeight);
        final score = (!cardRect.overlaps(inflated) ? 10000.0 : 0.0) +
            (Offset(c.left + cardWidth / 2, c.top + cardHeight / 2) - anchorCenter).distance;
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }
      return best;
    }

    final corner = bestCorner();
    // Apply user drag and clamp horizontally so the card never leaves the viewport.
    final cardLeft = (corner.left + _dragOffset.dx).clamp(0.0, size.width - cardWidth);
    // Vertical drag offset: positive drag moves card down (for top) / up (for bottom).
    final verticalDrag = _dragOffset.dy;
    // For bottom-anchored cards: bottom edge = margin + (negative drag).
    // For top-anchored cards:    top edge  = margin + (positive drag).
    // In both cases clamp so the card stays on screen.
    final maxCardBottom = size.height - margin; // never closer than margin to viewport top
    final cardBottom = corner.isBottom
        ? (margin - verticalDrag).clamp(margin, maxCardBottom)
        : null;
    final cardTop = !corner.isBottom
        ? (margin + verticalDrag).clamp(0.0, size.height - cardHeight)
        : null;

    // Detect whether the anchor is currently visible on screen. Hide the
    // ring when:
    //   (a) the user just tapped the anchor (_ringTapped — instant feedback), OR
    //   (b) a dialog is open on the shell navigator (shellNavigator.canPop() is
    //       true only for imperative routes like dialogs/bottom-sheets; GoRouter
    //       declarative shell routes don't leave poppable entries behind).
    // Either condition hides the ring so it never floats above a dialog.
    final bool dialogIsOpen = widget.shellNavigator?.canPop() ?? false;
    final padded = targetRect?.inflate(step.padding);
    final showRing = !_ringTapped &&
        !dialogIsOpen &&
        padded != null &&
        padded.left >= 0 &&
        padded.top >= 0 &&
        padded.right <= size.width &&
        padded.bottom <= size.height &&
        padded.width > 0 &&
        padded.height > 0;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Subtle pulse ring around the spotlighted anchor (visual cue only).
          // Wrapped in a GestureDetector (translucent) so tapping the anchor
          // sets _ringTapped immediately — before the resulting dialog opens.
          if (showRing)
            Positioned(
              left: padded.left - 2,
              top: padded.top - 2,
              width: padded.width + 4,
              height: padded.height + 4,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _ringTapped = true),
                onTapDown: (_) => setState(() => _ringTapped = true),
                child: IgnorePointer(child: _PulseRing()),
              ),
            ),
          // Compact coach card — draggable by its handle at the top.
          // Bottom-half corners use `bottom:` anchoring so the card grows
          // upward and is never clipped by the viewport regardless of how
          // tall the text content is. Top-half corners use `top:` anchoring.
          Positioned(
            left: cardLeft,
            top: cardTop,
            bottom: cardBottom,
            width: cardWidth,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: corner.isBottom
                      ? (size.height - margin * 2)           // bottom card: up to full viewport
                      : (size.height - (cardTop ?? 0) - margin), // top card: space below
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Drag handle ──────────────────────────────────
                      GestureDetector(
                        onPanUpdate: (d) =>
                            setState(() => _dragOffset += d.delta),
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.textSecondary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      // ── Step pill + close ─────────────────────────────
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Step ${widget.stepIndex + 1} of ${widget.totalSteps}',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'End tour',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: widget.onSkip,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(step.title, style: AppTextStyles.h3),
                      const SizedBox(height: 6),
                      Text(step.description,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.textSecondary)),
                      if (step.completeWhen != null) ...[
                        const SizedBox(height: 10),
                        Builder(builder: (ctx) {
                          final alreadyDone = () {
                            try {
                              return step.completeWhen!();
                            } catch (_) {
                              return false;
                            }
                          }();
                          return Row(
                            children: [
                              Icon(
                                alreadyDone
                                    ? Icons.check_circle
                                    : Icons.touch_app_outlined,
                                size: 14,
                                color: alreadyDone
                                    ? Colors.green
                                    : AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  alreadyDone
                                      ? 'Done — auto-advancing…'
                                      : 'Do it on the page — or press Next to skip.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                      color: alreadyDone
                                          ? Colors.green
                                          : AppColors.textSecondary,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: widget.onSkip,
                            child: const Text('End tour'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: widget.onNext,
                            icon: Icon(
                                isLast ? Icons.check : Icons.arrow_forward,
                                size: 16),
                            label: Text(isLast ? 'Done' : 'Next'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a dimmed full-screen rectangle with a rounded cutout window.
class _CutoutPainter extends CustomPainter {
  final Rect hole;
  final double radius;

  _CutoutPainter({required this.hole, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final outer = Path()..addRect(full);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    final cutout = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(
      cutout,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter old) =>
      old.hole != hole || old.radius != radius;
}

/// A subtle pulsing ring drawn around the highlighted element.
class _PulseRing extends StatefulWidget {
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.6 + 0.4 * t),
              width: 2 + 1.5 * t,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25 * (1 - t)),
                blurRadius: 16 + 8 * t,
                spreadRadius: 2 + 4 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
