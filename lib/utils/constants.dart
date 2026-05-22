import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shopify Admin-inspired design tokens.
///
/// Based on Shopify's Polaris design system adapted for Flutter:
/// - Shopify Green primary (#008060)
/// - Dark navy sidebar (#1A1A2E)
/// - Warm gray background (#F6F6F7)
/// - Clean white cards with subtle shadows
class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────────
  static const primary = Color(0xFF008060);       // Shopify green
  static const primaryDark = Color(0xFF006E52);    // Pressed/hover state
  static const primaryLight = Color(0xFFE3F1ED);   // Light green tint
  static const secondary = Color(0xFFF0FDF4);      // Very light green wash
  static const accent = Color(0xFF5C6AC4);          // Indigo accent

  // ── Sidebar ───────────────────────────────────────────────────────────────
  static const sidebarBg = Color(0xFF1A1A2E);       // Dark navy
  static const sidebarBgHover = Color(0xFF232340);   // Hover state
  static const sidebarText = Color(0xFFB0B7C3);      // Muted text
  static const sidebarTextActive = Colors.white;      // Active text
  static const sidebarAccent = Color(0xFF008060);     // Active indicator

  // ── Surface / Layout ──────────────────────────────────────────────────────
  static const background = Color(0xFFF6F6F7);     // Page background
  static const surface = Colors.white;              // Card surface
  static const surfaceHover = Color(0xFFFAFAFB);   // Card hover
  static const border = Color(0xFFE1E3E5);          // Border/divider
  static const borderLight = Color(0xFFF0F1F2);    // Subtle border

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF202223);     // Headings, body
  static const textSecondary = Color(0xFF6D7175);   // Captions, labels
  static const textSubdued = Color(0xFF8C9196);     // Disabled, hints
  static const textOnPrimary = Colors.white;        // Text on green

  // ── Status ────────────────────────────────────────────────────────────────
  static const success = Color(0xFF008060);         // Green (same as primary)
  static const successBg = Color(0xFFAEE9D1);       // Success background
  static const warning = Color(0xFFFFC453);          // Amber warning
  static const warningBg = Color(0xFFFFEABF);       // Warning background
  static const error = Color(0xFFD72C0D);            // Red error
  static const errorBg = Color(0xFFFED3CA);          // Error background
  static const info = Color(0xFF2C6ECB);             // Blue info
  static const infoBg = Color(0xFFB4E1FA);           // Info background

  // ── Charts / Data Viz ─────────────────────────────────────────────────────
  static const chart1 = Color(0xFF008060);   // Primary green
  static const chart2 = Color(0xFF5C6AC4);   // Indigo
  static const chart3 = Color(0xFFF49342);   // Orange
  static const chart4 = Color(0xFF47C1BF);   // Teal
  static const chart5 = Color(0xFFDE3618);   // Red
  static const chart6 = Color(0xFF9C6ADE);   // Purple

  // ── ABC-XYZ Classification Colors ─────────────────────────────────────────
  static const classA = Color(0xFF008060);   // Green — high value
  static const classB = Color(0xFFF49342);   // Orange — moderate value
  static const classC = Color(0xFF8C9196);   // Gray — low value
  static const classX = Color(0xFF2C6ECB);   // Blue — stable
  static const classY = Color(0xFFFFC453);   // Amber — moderate
  static const classZ = Color(0xFFD72C0D);   // Red — erratic

  // ── Urgency ───────────────────────────────────────────────────────────────
  static const urgencyCritical = Color(0xFFD72C0D);
  static const urgencyWarning = Color(0xFFFFC453);
  static const urgencyNormal = Color(0xFF008060);

  // ── Semantic border variants (for AlertBanner accents) ────────────────────
  static const errorBorder = Color(0xFFD72C0D);
  static const warningBorder = Color(0xFFB98900);
  static const successBorder = Color(0xFF007A5A);
  static const infoBorder = Color(0xFF1D5FA3);

  // ── Table row hover ───────────────────────────────────────────────────────
  static const tableRowHover = Color(0xFFF6F6F7);

  // ── Operator-Editorial redesign tokens ────────────────────────────────────
  /// Warmer page background — replaces cold `background` in new shell.
  static const canvas = Color(0xFFFAFAF9);
  /// Subtle filled-input / hover surface.
  static const surfaceSubtle = Color(0xFFF4F4F2);
  /// Thinner divider, used in place of `border` for new outlined surfaces.
  static const divider = Color(0xFFEAEAEA);
  /// Dot indicator (status pills, nav badges) — small, high-contrast.
  static const dot = Color(0xFF202223);

  // ── Zoho-inspired tokens ──────────────────────────────────────────────────
  /// Active item background inside the sidebar (lighter than `sidebarBg`).
  static const sidebarBgActive = Color(0xFF252542);
  /// Card surface (alias of `surface` for new Zoho-pattern widgets).
  static const surfaceCard = Color(0xFFFFFFFF);
  /// Sunken surface used for inputs and contextual setup cards.
  static const surfaceSunken = Color(0xFFF7F8FA);
  /// Very subtle border — used in Zoho-style cards and form groups.
  static const borderSubtle = Color(0xFFEEEFF1);
  /// Help / placeholder text — softer than `textSubdued`.
  static const textHelp = Color(0xFF9EA8B3);
  /// Required field label color (Zoho pattern: red-ish label, no asterisk).
  static const requiredLabel = Color(0xFFD9534F);

  /// Returns a [WidgetStateProperty] that highlights DataTable rows on hover.
  static WidgetStateProperty<Color?> get dataRowColor =>
      WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.hovered)) return tableRowHover;
        return null;
      });
}

class AppTextStyles {
  static TextStyle get h1 => GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.3,
      );
  static TextStyle get h2 => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );
  static TextStyle get h3 => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.4,
      );
  static TextStyle get body =>
      GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, height: 1.5);
  static TextStyle get bodySmall =>
      GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.5);
  static TextStyle get label => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.4,
      );
  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AppColors.textSubdued,
        height: 1.4,
      );
  static TextStyle get kpi => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  // Sidebar-specific styles
  static TextStyle get sidebarItem => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.sidebarText,
        height: 1.4,
      );
  static TextStyle get sidebarItemActive => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.sidebarTextActive,
        height: 1.4,
      );
  static TextStyle get sidebarSection => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.sidebarText.withValues(alpha: 0.5),
        height: 1.4,
      );

  // ── Form / Input ──────────────────────────────────────────────────────────
  /// Above-field label: 12 medium, secondary colour.
  static TextStyle get formLabel => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  /// Placeholder / helper text.
  static TextStyle get hint => GoogleFonts.inter(
        fontSize: 13,
        color: AppColors.textSubdued,
        height: 1.4,
      );

  /// Inline validation error below a field.
  static TextStyle get errorText => GoogleFonts.inter(
        fontSize: 12,
        color: AppColors.error,
        height: 1.4,
      );

  // ── Table ─────────────────────────────────────────────────────────────────
  /// Column header: 12 / semibold / UPPERCASE / 0.5 letter-spacing.
  static TextStyle get tableHeader => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  /// Table cell body.
  static TextStyle get tableCell => GoogleFonts.inter(
        fontSize: 13,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  /// Numeric cell — tabular figures, right-aligned.
  static TextStyle get tableNum => GoogleFonts.inter(
        fontSize: 13,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.textPrimary,
        height: 1.4,
      );

  // ── Operator-Editorial redesign tokens ────────────────────────────────────
  /// Editorial display heading (Fraunces serif). Used SPARINGLY: dashboard hero
  /// metric, page heroes, login wordmark. Do NOT use for body or labels.
  static TextStyle get display => GoogleFonts.fraunces(
        fontSize: 40,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.1,
        letterSpacing: -0.5,
      );

  /// Medium display, e.g. PageHero h1.
  static TextStyle get displaySm => GoogleFonts.fraunces(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.15,
        letterSpacing: -0.3,
      );

  /// Tabular monospace for SKUs, IDs, counts, timestamps.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 13,
        color: AppColors.textPrimary,
        height: 1.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Large mono — used for hero metric numbers.
  static TextStyle get monoLg => GoogleFonts.jetBrainsMono(
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.1,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Small mono — used for metric strip values, badge counts.
  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        color: AppColors.textSecondary,
        height: 1.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Keyboard chip text, e.g. `⌘K` pill in the top bar.
  static TextStyle get kbd => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSubdued,
        height: 1,
      );

  /// Small-caps editorial section label (replaces uppercase letter-spaced
  /// headers everywhere — softer, less generic SaaS).
  static TextStyle get eyebrow => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.textSubdued,
        height: 1.4,
      );

  // ── Zoho-inspired tokens ──────────────────────────────────────────────────
  /// Horizontal tab pill label (Dashboard / Getting Started / Help).
  static TextStyle get tabLabel => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
      );

  /// Form section heading (groups fields like "Basic Information").
  static TextStyle get formSection => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.4,
      );
}

/// Common shadow definitions.
class AppShadows {
  static const card = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 1,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 3,
      offset: Offset(0, 2),
    ),
  ];

  static const cardHover = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 6,
      offset: Offset(0, 4),
    ),
  ];

  static const elevated = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12,
      offset: Offset(0, 8),
    ),
  ];

  // ── Operator-Editorial redesign ─────────────────────────────────────────
  /// Border-only "shadow" — used by outlined cards (replaces card elevation).
  static const hairline = <BoxShadow>[];

  /// Lifted shadow for menus, modals, command palette ONLY.
  static const lifted = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];
}

/// Common border radius values.
class AppRadius {
  static const sm = BorderRadius.all(Radius.circular(6));
  static const md = BorderRadius.all(Radius.circular(10));
  static const lg = BorderRadius.all(Radius.circular(14));
  static const xl = BorderRadius.all(Radius.circular(20));

  // ── Operator-Editorial redesign ─────────────────────────────────────────
  /// Sharp corners — chips, status pills, tight buttons.
  static const sharp = BorderRadius.all(Radius.circular(4));
  /// Soft corners — DEFAULT for cards, inputs, dialogs.
  static const soft = BorderRadius.all(Radius.circular(6));
  /// Pill — fully rounded.
  static const pill = BorderRadius.all(Radius.circular(999));
}

/// 4E — Spacing scale (4-point grid).
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // ── Operator-Editorial redesign ─────────────────────────────────────────
  /// Asymmetric editorial gutter (between hero zones).
  static const double gutter = 40;
  /// Hero zone top/bottom padding.
  static const double hero = 64;

  /// Shortcut EdgeInsets factories.
  static EdgeInsets all(double v) => EdgeInsets.all(v);
  static EdgeInsets h(double v) => EdgeInsets.symmetric(horizontal: v);
  static EdgeInsets v(double v) => EdgeInsets.symmetric(vertical: v);
  static EdgeInsets page() => const EdgeInsets.all(AppSpacing.lg);
}

const double kSidebarWidth = 240.0;
const double kSidebarCollapsedWidth = 64.0;

// ── Operator-Editorial redesign — new shell dimensions ────────────────────
/// Permanent icon-rail width on the left.
const double kIconRailWidth = 56.0;
/// Flyout panel width that opens on hover/focus.
const double kFlyoutWidth = 260.0;
/// Top bar height.
const double kTopBarHeight = 52.0;
/// Hover delay before flyout opens (ms).
const Duration kFlyoutOpenDelay = Duration(milliseconds: 120);
/// Mouse-leave delay before flyout closes (ms).
const Duration kFlyoutCloseDelay = Duration(milliseconds: 220);

// ── Zoho-inspired tokens ────────────────────────────────────────────────────
/// Height of the horizontal tab bar (Dashboard / Getting Started / Help).
const double kHorizontalTabHeight = 44.0;
/// Mobile bottom navigation bar height.
const double kBottomNavHeight = 64.0;
