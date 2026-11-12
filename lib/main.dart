import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/db.dart';
import 'services/drive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.instance.init();
  await AppState.instance.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState.instance),
        ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
      ],
      child: const BizPosApp(),
    ),
  );
}
