import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF005AC1); // Stitch-like blue
  static const secondary = Color(0xFFE3F2FD);
  static const accent = Color(0xFF00BFA5);
  static const background = Color(0xFFF5F7FA);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const error = Color(0xFFEF4444);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
}

class AppTextStyles {
  static TextStyle get h1 => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static TextStyle get body =>
      GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary);
  static TextStyle get bodySmall =>
      GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary);
  static TextStyle get label => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}

const double kSidebarWidth = 250.0;
const double kSidebarCollapsedWidth = 72.0;
