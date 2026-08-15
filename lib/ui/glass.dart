import 'dart:ui';

import 'package:flutter/material.dart';

/// Liquid Glass material tokens shared by the workspace and dialogs.
abstract final class GlassTokens {
  /// Corner radii (macOS Tahoe / iOS 26 scale).
  static const panelRadius = 16.0;
  static const cardRadius = 18.0;
  static const dialogRadius = 20.0;
  static const buttonRadius = 12.0;

  /// Backdrop blur used by persistent glass panels.
  static const blurSigma = 20.0;

  static Color fill(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xff191c22).withValues(alpha: 0.62)
      : Colors.white.withValues(alpha: 0.60);

  static Color border(Brightness brightness) => brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.45);

  static List<BoxShadow> shadow(Brightness brightness) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: brightness == Brightness.dark ? 0.32 : 0.10,
      ),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
  ];
}

/// A translucent, blurred "liquid glass" surface: backdrop blur, tinted fill,
/// 1px light border, top specular highlight and a soft diffused shadow.
///
/// BackdropFilter is expensive — use on persistent panels only, never per
/// table row or tree node.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = GlassTokens.panelRadius,
    this.blur = GlassTokens.blurSigma,
    this.shadow = true,
    this.specular = true,
    this.fill,
    this.borderRadius,
  });

  final Widget child;
  final double radius;
  final double blur;
  final bool shadow;
  final bool specular;
  final Color? fill;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final borderRadius = this.borderRadius ?? BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow ? GlassTokens.shadow(brightness) : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // The tint sits UNDER the blur layer: the BackdropFilter folds it
            // into the filtered backdrop (a solid fill survives the blur
            // unchanged), which composites reliably inside modal routes on
            // Windows — painting the tint above the BackdropFilter does not.
            Positioned.fill(
              child: ColoredBox(color: fill ?? GlassTokens.fill(brightness)),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: const SizedBox.expand(),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: GlassTokens.border(brightness)),
                borderRadius: borderRadius,
                gradient: specular
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(
                            alpha: brightness == Brightness.dark ? 0.07 : 0.25,
                          ),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.4],
                      )
                    : null,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// The layered workspace canvas that glass panels refract: a soft base color
/// with large, low-opacity radial tints.
class GlassCanvas extends StatelessWidget {
  const GlassCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primaryTint = dark
        ? const Color(0xff7da6ff).withValues(alpha: 0.10)
        : const Color(0xff285cc4).withValues(alpha: 0.07);
    final tealTint = dark
        ? const Color(0xff3fd8c2).withValues(alpha: 0.08)
        : const Color(0xff2aa79b).withValues(alpha: 0.05);
    return ColoredBox(
      color: dark ? const Color(0xff101216) : const Color(0xffedf0f5),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -260,
            top: -220,
            width: 720,
            height: 620,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [primaryTint, primaryTint.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -300,
            bottom: -260,
            width: 820,
            height: 680,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [tealTint, tealTint.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Positioned(
            right: 140,
            top: -320,
            width: 620,
            height: 560,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    primaryTint.withValues(alpha: primaryTint.a * 0.6),
                    primaryTint.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Primary action button with the glass vertical gradient (lighter top) and a
/// 1px inner top highlight. Geometry matches the themed FilledButton.
class GlassPrimaryButton extends StatelessWidget {
  const GlassPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.minimumSize,
    this.padding,
  }) : icon = null;

  const GlassPrimaryButton.icon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget label,
    this.minimumSize,
    this.padding,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Size? minimumSize;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: theme.colorScheme.onPrimary,
      minimumSize: minimumSize ?? const Size(44, 40),
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassTokens.buttonRadius),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.buttonRadius),
        gradient: onPressed == null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(primary, Colors.white, 0.18)!, primary],
              ),
        color: onPressed == null ? primary.withValues(alpha: 0.45) : null,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        ),
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: primary.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: child)
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: child,
            ),
    );
  }
}

/// A pill-shaped toggle used app-wide instead of Material's [Switch].
/// Interaction feedback animates the whole capsule (track color, sliding
/// knob, focus outline hugging the pill) — no detached thumb ring.
class PillSwitch extends StatefulWidget {
  const PillSwitch({super.key, required this.value, required this.onChanged});

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  @override
  State<PillSwitch> createState() => _PillSwitchState();
}

class _PillSwitchState extends State<PillSwitch> {
  bool _focused = false;
  bool _hovered = false;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 160);
    var trackColor = !enabled
        ? scheme.onSurface.withValues(alpha: 0.10)
        : widget.value
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.22);
    if (enabled && (_hovered || _focused)) {
      trackColor = Color.alphaBlend(
        scheme.primary.withValues(alpha: widget.value ? 0.06 : 0.10),
        trackColor,
      );
    }
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? _toggle : null,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused && enabled
                    ? scheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: widget.value
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 3,
                      offset: Offset(0, 1),
                      color: Color(0x33000000),
                    ),
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
