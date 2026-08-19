import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A single in-flight toast. Toasts are compact, top-centered, and dismiss
/// themselves after a short dwell.
class AppToastData {
  const AppToastData({
    required this.id,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final int id;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool isError;
}

/// Global toast service. Call [AppToast.show] from anywhere; the overlay
/// mounted in the workspace root renders the current toast.
class AppToast {
  AppToast._();

  static final ValueNotifier<AppToastData?> _current = ValueNotifier(null);
  static Timer? _timer;
  static int _nextId = 0;

  static ValueListenable<AppToastData?> get listenable => _current;

  static void show(
    String message, {
    String? actionLabel,
    Future<void> Function()? onAction,
    bool isError = false,
  }) {
    // Toasts are terse labels; strip trailing full stops from any source.
    final cleaned = message.endsWith('。')
        ? message.substring(0, message.length - 1)
        : message;
    _timer?.cancel();
    _current.value = AppToastData(
      id: ++_nextId,
      message: cleaned,
      actionLabel: actionLabel,
      onAction: onAction,
      isError: isError,
    );
    _timer = Timer(const Duration(milliseconds: 3400), dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _current.value = null;
  }

  /// Called by the overlay's dispose so no timer outlives the widget tree
  /// (widget tests fail on pending timers otherwise).
  static void reset() {
    _timer?.cancel();
    _timer = null;
    _current.value = null;
  }
}

/// Top-centered compact toast rendered above the workspace content.
class AppToastOverlay extends StatefulWidget {
  const AppToastOverlay({super.key});

  @override
  State<AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<AppToastOverlay> {
  @override
  void dispose() {
    AppToast.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return ValueListenableBuilder<AppToastData?>(
      valueListenable: AppToast.listenable,
      builder: (context, data, _) {
        return Positioned(
          top: 44,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: data == null,
            child: Center(
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, -0.35),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                ),
                child: data == null
                    ? const SizedBox.shrink()
                    : _ToastCard(key: ValueKey(data.id), data: data),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.data});

  final AppToastData data;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.only(left: 14, top: 7, bottom: 7, right: 8),
          decoration: BoxDecoration(
            color: const Color(0xff202833).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 6),
                color: Color(0x40000000),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                data.isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 16,
                color: data.isError
                    ? const Color(0xfff2b8bd)
                    : const Color(0xff80d2a5),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  data.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              if (data.actionLabel != null)
                TextButton(
                  onPressed: () {
                    final action = data.onAction;
                    AppToast.dismiss();
                    if (action != null) unawaited(action());
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xff9db9ff),
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    data.actionLabel!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
