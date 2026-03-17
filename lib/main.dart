import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/app.dart';
import 'package:ma5zony/providers/app_state.dart';

void main() {
  debugPrint('App starting...');
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState()..loadAll())],
      child: const Ma5zonyApp(),
    ),
  );
  debugPrint('runApp called');
}
