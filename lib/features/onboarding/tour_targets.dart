import 'package:flutter/widgets.dart';

/// Lightweight registry that maps a stable string id to a [GlobalKey]. Used by
/// the onboarding spotlight to find live widget positions on screen (sidebar
/// items, primary action buttons, etc.) without forcing those widgets to know
/// anything about the tour.
///
/// Usage:
///   ```dart
///   // attach the key at render-time
///   KeyedSubtree(key: TourTargets.instance.keyFor('sidebar:/suppliers'),
///                child: theWidget);
///
///   // later, the spotlight overlay reads the key's RenderBox bounds.
///   ```
///
/// Keys are kept alive for the lifetime of the app — this is fine because the
/// total number of anchor points is tiny (~10).
class TourTargets {
  TourTargets._();
  static final TourTargets instance = TourTargets._();

  final Map<String, GlobalKey> _keys = {};

  GlobalKey keyFor(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tour:$id'));

  /// Returns the on-screen rect of the registered anchor, or null if it isn't
  /// currently mounted / laid out.
  Rect? rectFor(String id) {
    final key = _keys[id];
    final ctx = key?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }
}
