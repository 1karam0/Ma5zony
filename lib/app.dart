import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/app_router.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class Ma5zonyApp extends StatelessWidget {
  const Ma5zonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final router = buildAppRouter(appState);

    return MaterialApp.router(
      title: 'Ma5zony - Inventory Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
        scaffoldBackgroundColor: AppColors.background,
      ),
      routerConfig: router,
    );
  }
}
