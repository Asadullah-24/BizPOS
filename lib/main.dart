import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/db.dart';
import 'core/access.dart';
import 'core/license.dart';
import 'services/cloud_service.dart';
import 'services/drive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.instance.init();
  await AppState.instance.load();
  await LicenseService.instance.load();
  Access.instance.load();
  await CloudService.instance.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState.instance),
        ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
        ChangeNotifierProvider<LicenseService>.value(value: LicenseService.instance),
        ChangeNotifierProvider<Access>.value(value: Access.instance),
        ChangeNotifierProvider<CloudService>.value(value: CloudService.instance),
      ],
      child: const BizPosApp(),
    ),
  );
}
