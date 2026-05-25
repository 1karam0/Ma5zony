import 'dart:async';

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
  /// The predicate is called every ~400ms with the BuildContext used to start
  /// the coach. Keep it cheap (no I/O) — just check Provider state.
  final bool Function(BuildContext context)? completeWhen;

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
    final rootContext = context;

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
        onNavigate(step.navigateTo!);
        // Give the target screen 2 frames to mount and lay out.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      if (removed) return;
      index = next;
      render();

      // Poll the success predicate so the tour auto-advances the moment the
      // user fulfills the task (e.g. adds a supplier, creates a product).
      if (step.completeWhen != null) {
        pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
          if (removed) return;
          if (!rootContext.mounted) {
            safeRemove();
            return;
          }
          try {
            if (step.completeWhen!(rootContext)) {
              goToStep(index + 1);
            }
          } catch (_) {
            // Predicate threw (e.g. provider not yet wired). Ignore — try
            // again on the next tick.
          }
        });
      }

      // Live-reposition the cutout. The highlighted button may move when a
      // dialog opens / closes or when its parent rebuilds. Rebuilding the
      // overlay every 120ms keeps the spotlight glued to the right place
      // without coupling us to specific widget lifecycles.
      repositionTimer = Timer.periodic(
          const Duration(milliseconds: 120), (_) => render());
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
        );
      },
    );

    overlay.insert(entry);
    // Kick off the first step (navigation aware).
    await goToStep(0);
  }
}

class _SpotlightLayer extends StatelessWidget {
  final SpotlightStep step;
  final Rect? targetRect;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _SpotlightLayer({
    required this.step,
    required this.targetRect,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final isLast = stepIndex == totalSteps - 1;

    // Padded highlight rect — null safe fallback to centre dot if anchor isn't
    // found (e.g., navigated to a screen where the key isn't present yet).
    final padded = (targetRect ??
            Rect.fromCenter(
                center: Offset(size.width / 2, size.height / 2),
                width: 1,
                height: 1))
        .inflate(step.padding);

    // Clamp to screen bounds so the dim rects don't compute negative sizes.
    final clamped = Rect.fromLTRB(
      padded.left.clamp(0.0, size.width),
      padded.top.clamp(0.0, size.height),
      padded.right.clamp(0.0, size.width),
      padded.bottom.clamp(0.0, size.height),
    );

    // Compute popover position so it doesn't overlap the cutout.
    const popoverWidth = 320.0;
    final spaceBelow = size.height - clamped.bottom;
    final placeBelow = spaceBelow > 220;
    double popoverTop;
    double popoverLeft;
    if (placeBelow) {
      popoverTop = clamped.bottom + 12;
    } else {
      popoverTop = clamped.top - 220;
      if (popoverTop < 24) popoverTop = 24;
    }
    popoverLeft = clamped.center.dx - popoverWidth / 2;
    if (popoverLeft < 16) popoverLeft = 16;
    if (popoverLeft + popoverWidth > size.width - 16) {
      popoverLeft = size.width - popoverWidth - 16;
    }

    const dimColor = Color(0x9E000000); // ~62% black

    // Four dim rectangles framing the cutout so the cutout area itself
    // receives no overlay widgets → pointer events fall straight through to
    // the underlying app (Add Supplier, dialog fields, etc. are clickable).
    Widget dim() => const IgnorePointer(
          ignoring: false,
          child: ColoredBox(color: dimColor),
        );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Top strip
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: clamped.top,
            child: dim(),
          ),
          // Bottom strip
          Positioned(
            left: 0,
            top: clamped.bottom,
            right: 0,
            bottom: 0,
            child: dim(),
          ),
          // Left strip (between top & bottom)
          Positioned(
            left: 0,
            top: clamped.top,
            width: clamped.left,
            height: clamped.height,
            child: dim(),
          ),
          // Right strip
          Positioned(
            left: clamped.right,
            top: clamped.top,
            right: 0,
            height: clamped.height,
            child: dim(),
          ),
          // Pulsing border around the highlighted element (visual only —
          // IgnorePointer so it doesn't block clicks on the highlighted
          // widget underneath).
          if (targetRect != null)
            Positioned(
              left: clamped.left - 2,
              top: clamped.top - 2,
              width: clamped.width + 4,
              height: clamped.height + 4,
              child: IgnorePointer(child: _PulseRing()),
            ),
          // Popover card (receives pointer events normally).
          Positioned(
            left: popoverLeft,
            top: popoverTop,
            width: popoverWidth,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                            'Step ${stepIndex + 1} of $totalSteps',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'End tour',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onSkip,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(step.title, style: AppTextStyles.h3),
                    const SizedBox(height: 6),
                    Text(step.description,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textSecondary)),
                    if (step.completeWhen != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.touch_app_outlined,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Try it — the tour will continue once you do.',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton(
                          onPressed: onSkip,
                          child: const Text('Skip'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: onNext,
                          icon: Icon(
                              isLast
                                  ? Icons.check
                                  : Icons.arrow_forward,
                              size: 16),
                          label: Text(isLast
                              ? 'Done'
                              : (step.completeWhen != null
                                  ? 'Skip step'
                                  : 'Next')),
                        ),
                      ],
                    ),
                  ],
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
