import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/app_router.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class Ma5zonyApp extends StatefulWidget {
  final AppState appState;

  const Ma5zonyApp({super.key, required this.appState});

  @override
  State<Ma5zonyApp> createState() => _Ma5zonyAppState();
}

class _Ma5zonyAppState extends State<Ma5zonyApp> {
  // Router is built ONCE and stored in State — never recreated on rebuild.
  late final GoRouter _router = buildAppRouter(widget.appState);

  @override
  Widget build(BuildContext context) {
    // Only rebuild MaterialApp when the theme actually changes — not on every
    // AppState.notifyListeners() (CRUD, background sync, demand updates, …),
    // which previously rebuilt the entire MaterialApp wrapper needlessly.
    final themeMode =
        context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp.router(
      title: 'Ma5zony - Inventory Management',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _buildLightTheme(),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
        ),
      ),
      routerConfig: _router,
    );
  }

  /// Operator-Editorial theme: outlined cards (no elevation), filled inputs
  /// with bottom-border-only focus, sharp 4px chips, soft 6px default radius,
  /// warmer canvas background.
  ThemeData _buildLightTheme() {
    const baseRadius = AppRadius.soft;

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(),
      scaffoldBackgroundColor: AppColors.canvas,
      dividerColor: AppColors.divider,

      // Cards: outlined, no elevation, soft corners.
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: baseRadius,
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Inputs: filled with subtle bg, no top/left/right borders, 1px bottom
      // border that thickens + tints primary on focus. Labels above field.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        isDense: true,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        hintStyle: AppTextStyles.hint,
        labelStyle: AppTextStyles.formLabel,
        errorStyle: AppTextStyles.errorText,
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.divider),
          borderRadius: BorderRadius.zero,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.divider),
          borderRadius: BorderRadius.zero,
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.zero,
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.error),
          borderRadius: BorderRadius.zero,
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.error, width: 2),
          borderRadius: BorderRadius.zero,
        ),
      ),

      // Chips: sharp 4px corners; light-tint selected bg + primary border.
      // selectedColor uses a light tint (not solid primary) so dark label text
      // remains readable on both selected and unselected chips.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        secondarySelectedColor: AppColors.primary.withValues(alpha: 0.12),
        labelStyle: AppTextStyles.label,
        secondaryLabelStyle: AppTextStyles.label,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sharp),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
      ),

      // Buttons — primary filled, 6px radius, no elevation; secondary outlined.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: baseRadius),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          shape: const RoundedRectangleBorder(borderRadius: baseRadius),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: const RoundedRectangleBorder(borderRadius: baseRadius),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Dialogs / sheets — soft corners, lifted shadow.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: baseRadius,
          side: const BorderSide(color: AppColors.divider),
        ),
      ),

      // App bar — warm canvas, no shadow, no tint.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),

      // Tooltips — small, dark, sharp.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: AppRadius.sharp,
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 12,
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        waitDuration: const Duration(milliseconds: 500),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.borderLight,
        circularTrackColor: AppColors.borderLight,
      ),

      // DataTable: subtle header background, consistent row height.
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.surfaceSubtle),
        headingTextStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.textSecondary,
        ),
        dataTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        dataRowMinHeight: 52,
        dataRowMaxHeight: 52,
        columnSpacing: 16,
        horizontalMargin: 16,
        dividerThickness: 1,
        headingRowHeight: 40,
      ),

      // PopupMenu: surface, soft radius, divider border.
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: baseRadius,
          side: const BorderSide(color: AppColors.divider),
        ),
        textStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
      ),
    );
  }
}
