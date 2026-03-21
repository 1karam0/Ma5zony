import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/app.dart';
import 'package:ma5zony/firebase_options.dart';
import 'package:ma5zony/providers/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState()..loadAll())],
      child: const Ma5zonyApp(),
    ),
  );
}
