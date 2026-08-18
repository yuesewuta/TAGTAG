import 'package:flutter/material.dart';

abstract final class TagTagColors {
  static const primary = Color(0xff285cc4);
  static const primaryHover = Color(0xff1f4da8);
  static const primarySoft = Color(0xffeaf1ff);
  static const canvas = Color(0xfff5f7fa);
  static const navigation = Color(0xffeef1f5);
  static const surface = Color(0xffffffff);
  static const surfaceSubtle = Color(0xfff8f9fb);
  static const foreground = Color(0xff18202b);
  static const secondaryText = Color(0xff5d6878);
  static const border = Color(0xffdde2e9);
  static const borderStrong = Color(0xffcbd2dc);
  static const folder = Color(0xffc47a16);
  static const success = Color(0xff1f7a55);
  static const warning = Color(0xffb65d18);
  static const destructive = Color(0xffc43b43);
  static const purple = Color(0xff7654b5);
  static const textFaint = Color(0xff7a8492);
}

/// Snappier than the 300ms Material default; menus feel instant.
const quickPopupAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 120),
  reverseDuration: Duration(milliseconds: 90),
  curve: Curves.easeOutCubic,
);

ThemeData buildTagTagTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? const Color(0xff7da6ff) : TagTagColors.primary;
  final primarySoft = dark ? const Color(0xff1b2c4f) : TagTagColors.primarySoft;
  final surface = dark ? const Color(0xff22262e) : TagTagColors.surface;
  final foreground = dark ? const Color(0xffedf1f7) : TagTagColors.foreground;
  final secondaryText = dark
      ? const Color(0xffaab4c2)
      : TagTagColors.secondaryText;
  final border = dark ? const Color(0xff353b45) : TagTagColors.border;
  final borderStrong = dark
      ? const Color(0xff49515e)
      : TagTagColors.borderStrong;
  final canvas = dark ? const Color(0xff171a1f) : TagTagColors.canvas;
  final surfaceSubtle = dark
      ? const Color(0xff1d2128)
      : TagTagColors.surfaceSubtle;
  final surfaceRaised = dark ? const Color(0xff282d36) : TagTagColors.surface;
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xff102344) : Colors.white,
        primaryContainer: primarySoft,
        onPrimaryContainer: dark
            ? const Color(0xffdce7ff)
            : const Color(0xff173d85),
        secondary: TagTagColors.folder,
        onSecondary: Colors.white,
        error: TagTagColors.destructive,
        surface: surface,
        onSurface: foreground,
        onSurfaceVariant: secondaryText,
        outline: borderStrong,
        outlineVariant: border,
        surfaceContainer: canvas,
        surfaceContainerLow: surfaceSubtle,
        surfaceContainerHigh: surfaceRaised,
      );
  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff171a1f)
        : TagTagColors.canvas,
    useMaterial3: true,
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: const [
      'Segoe UI',
      'Microsoft YaHei UI',
      'Noto Sans SC',
    ],
  );
  final textTheme = base.textTheme
      .apply(bodyColor: foreground, displayColor: foreground)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          letterSpacing: 0,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          letterSpacing: 0,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      );
  const roundedRectangle = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 62,
      shape: Border(bottom: BorderSide(color: border)),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: secondaryText, size: 20),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: TagTagColors.foreground,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: TagTagColors.destructive),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(secondaryText),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? primarySoft : null,
        ),
        shape: const WidgetStatePropertyAll(roundedRectangle),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(44, 40),
        shape: roundedRectangle,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(44, 40),
        side: BorderSide(color: borderStrong),
        shape: roundedRectangle,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(44, 40),
        shape: roundedRectangle,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark
          ? const Color(0xff191c22).withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.88),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.50),
        ),
      ),
    ),
    // AlertDialogs get a translucent raised fill; PrototypeDialogFrame renders
    // its own GlassPanel and opts into a transparent shell instead.
    dialogTheme: DialogThemeData(
      backgroundColor: dark
          ? const Color(0xff191c22).withValues(alpha: 0.82)
          : Colors.white.withValues(alpha: 0.80),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xff202833).withValues(alpha: 0.92),
      contentTextStyle: const TextStyle(color: Colors.white),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
