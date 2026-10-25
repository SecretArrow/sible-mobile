import 'package:flutter/material.dart';

/// Modern dark-first design system for Sible Miner.
class SibleTheme {
  // Core palette - deep space dark with electric violet & cyan accents.
  static const Color bg = Color(0xFF070B14);
  static const Color surface = Color(0xFF0E1524);
  static const Color surfaceHigh = Color(0xFF141D31);
  static const Color border = Color(0x14FFFFFF);
  static const Color textPrimary = Color(0xFFF2F5FA);
  static const Color textSecondary = Color(0xFF8C97AD);

  static const Color primary = Color(0xFF6366F1);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF151E33), Color(0xFF0E1524)],
  );

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: cyan,
        surface: surface,
        error: danger,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: null,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.25),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
              color: textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary);
          }
          return const IconThemeData(color: textSecondary);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: const TextStyle(color: textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: Color(0x33FFFFFF)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cyan,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.white
                : textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primary : surfaceHigh),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        showDragHandle: true,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? primary.withValues(alpha: 0.30)
                  : surfaceHigh),
          foregroundColor: const WidgetStatePropertyAll(textPrimary),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.selected) ? primary : border,
              )),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  static Color accentFor(bool ok) => ok ? success : danger;
}
