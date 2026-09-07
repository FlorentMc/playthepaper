import 'package:flutter/material.dart';

/// Feedback and board colours shared by every game, with a text colour that
/// reads on each. Colour never carries meaning alone; games pair each state
/// with a symbol or label.
class GameColors extends ThemeExtension<GameColors> {
  const GameColors({
    required this.correct,
    required this.misplaced,
    required this.absent,
    required this.onFeedback,
    required this.cell,
    required this.cellSelected,
    required this.cellHighlight,
    required this.cellBorder,
    required this.given,
    required this.error,
    required this.rule,
    required this.subtle,
  });

  final Color correct;
  final Color misplaced;
  final Color absent;
  final Color onFeedback;
  final Color cell;
  final Color cellSelected;
  final Color cellHighlight;
  final Color cellBorder;
  final Color given;
  final Color error;

  /// Hairline rule colour, as between newspaper columns.
  final Color rule;

  /// Muted ink for captions and secondary text.
  final Color subtle;

  static const light = GameColors(
    correct: Color(0xFF2E7D5B),
    misplaced: Color(0xFFC08A1E),
    absent: Color(0xFF8A847A),
    onFeedback: Color(0xFFFFFDF8),
    cell: Color(0xFFFFFDF8),
    cellSelected: Color(0xFFF3DFA6),
    cellHighlight: Color(0xFFEFE8D8),
    cellBorder: Color(0xFF8E887C),
    given: Color(0xFF1A1917),
    error: Color(0xFFB3261E),
    rule: Color(0xFFD9D2C3),
    subtle: Color(0xFF6B665C),
  );

  static const dark = GameColors(
    correct: Color(0xFF3F9A72),
    misplaced: Color(0xFFD1A03A),
    absent: Color(0xFF5A564F),
    onFeedback: Color(0xFF141311),
    cell: Color(0xFF26241F),
    cellSelected: Color(0xFF5A4B1F),
    cellHighlight: Color(0xFF33302A),
    cellBorder: Color(0xFF7A7469),
    given: Color(0xFFECE6D8),
    error: Color(0xFFE5776E),
    rule: Color(0xFF3A3731),
    subtle: Color(0xFFA29C8F),
  );

  @override
  GameColors copyWith({
    Color? correct,
    Color? misplaced,
    Color? absent,
    Color? onFeedback,
    Color? cell,
    Color? cellSelected,
    Color? cellHighlight,
    Color? cellBorder,
    Color? given,
    Color? error,
    Color? rule,
    Color? subtle,
  }) =>
      GameColors(
        correct: correct ?? this.correct,
        misplaced: misplaced ?? this.misplaced,
        absent: absent ?? this.absent,
        onFeedback: onFeedback ?? this.onFeedback,
        cell: cell ?? this.cell,
        cellSelected: cellSelected ?? this.cellSelected,
        cellHighlight: cellHighlight ?? this.cellHighlight,
        cellBorder: cellBorder ?? this.cellBorder,
        given: given ?? this.given,
        error: error ?? this.error,
        rule: rule ?? this.rule,
        subtle: subtle ?? this.subtle,
      );

  @override
  GameColors lerp(GameColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GameColors(
      correct: l(correct, other.correct),
      misplaced: l(misplaced, other.misplaced),
      absent: l(absent, other.absent),
      onFeedback: l(onFeedback, other.onFeedback),
      cell: l(cell, other.cell),
      cellSelected: l(cellSelected, other.cellSelected),
      cellHighlight: l(cellHighlight, other.cellHighlight),
      cellBorder: l(cellBorder, other.cellBorder),
      given: l(given, other.given),
      error: l(error, other.error),
      rule: l(rule, other.rule),
      subtle: l(subtle, other.subtle),
    );
  }
}

extension GameColorsContext on BuildContext {
  GameColors get gameColors => Theme.of(this).extension<GameColors>()!;
}

/// A small, well-set newspaper: cream paper, black ink, one restrained accent.
class DaypencilTheme {
  static const displayFamily = 'Playfair Display';
  static const bodyFamily = 'Source Sans 3';

  static const _paper = Color(0xFFF6F1E7);
  static const _paperRaised = Color(0xFFFFFDF8);
  static const _ink = Color(0xFF1A1917);
  static const _accent = Color(0xFFA6322B);

  static const _night = Color(0xFF161513);
  static const _nightRaised = Color(0xFF201F1C);
  static const _nightInk = Color(0xFFECE6D8);
  static const _nightAccent = Color(0xFFE2725B);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: _paper,
        surface: _paperRaised,
        ink: _ink,
        accent: _accent,
        colors: GameColors.light,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: _night,
        surface: _nightRaised,
        ink: _nightInk,
        accent: _nightAccent,
        colors: GameColors.dark,
      );

  static TextStyle display({double size = 28, double weight = 700, Color? color, double? height}) => TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        fontWeight: weight >= 600 ? FontWeight.bold : FontWeight.normal,
        fontVariations: [FontVariation('wght', weight)],
        color: color,
        height: height,
      );

  static TextStyle body({double size = 16, double weight = 400, Color? color, double? height}) => TextStyle(
        fontFamily: bodyFamily,
        fontSize: size,
        fontWeight: weight >= 600 ? FontWeight.w600 : FontWeight.normal,
        fontVariations: [FontVariation('wght', weight)],
        color: color,
        height: height,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color ink,
    required Color accent,
    required GameColors colors,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: ink,
      onPrimary: background,
      secondary: accent,
      onSecondary: background,
      error: colors.error,
      onError: background,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: colors.cellHighlight,
      outline: colors.rule,
      outlineVariant: colors.rule,
      onSurfaceVariant: colors.subtle,
      tertiary: colors.correct,
      onTertiary: colors.onFeedback,
    );

    final textTheme = TextTheme(
      displayLarge: display(size: 40),
      displayMedium: display(size: 32),
      displaySmall: display(size: 26),
      headlineLarge: display(size: 30),
      headlineMedium: display(size: 24),
      headlineSmall: display(size: 20),
      titleLarge: body(size: 20, weight: 600),
      titleMedium: body(size: 17, weight: 600),
      titleSmall: body(size: 15, weight: 600),
      bodyLarge: body(size: 17, height: 1.4),
      bodyMedium: body(size: 16, height: 1.4),
      bodySmall: body(size: 14, height: 1.35, color: colors.subtle),
      labelLarge: body(size: 16, weight: 600),
      labelMedium: body(size: 14, weight: 600),
      labelSmall: body(size: 12, weight: 600, color: colors.subtle),
    ).apply(bodyColor: ink, displayColor: ink);

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: bodyFamily,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

    return base.copyWith(
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: display(size: 20, color: ink),
        shape: Border(bottom: BorderSide(color: colors.rule)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.rule),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.rule, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: background,
          shape: buttonShape,
          padding: buttonPadding,
          textStyle: body(size: 16, weight: 600),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink),
          shape: buttonShape,
          padding: buttonPadding,
          textStyle: body(size: 16, weight: 600),
          minimumSize: const Size(48, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          shape: buttonShape,
          textStyle: body(size: 16, weight: 600),
          minimumSize: const Size(48, 44),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink, minimumSize: const Size(48, 48)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: body(size: 15, color: background),
        behavior: SnackBarBehavior.floating,
        shape: buttonShape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titleTextStyle: display(size: 22, color: ink),
        contentTextStyle: body(size: 16, color: ink, height: 1.4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(background),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : colors.absent,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: ink,
        inactiveTrackColor: colors.rule,
        thumbColor: ink,
        overlayColor: ink.withValues(alpha: 0.12),
        valueIndicatorColor: ink,
        valueIndicatorTextStyle: body(size: 14, color: background, weight: 600),
      ),
      listTileTheme: ListTileThemeData(iconColor: ink, textColor: ink),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: colors.rule),
        labelStyle: body(size: 14, color: ink, weight: 600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
