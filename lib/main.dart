import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/db.dart';
import 'core/access.dart';
import 'core/license.dart';
import 'services/cloud_service.dart';
import 'services/drive_service.dart';
import 'services/profile_service.dart';
import 'services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pick which store on this phone to open before the database starts.
  Local.prefs = await SharedPreferences.getInstance();
  await ProfileService.instance.load();
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
        ChangeNotifierProvider<ProfileService>.value(value: ProfileService.instance),
      ],
      child: const BizPosApp(),
    ),
  );
  // After the first frame, so a slow Play Store check never delays opening.
  UpdateService.instance.init();
}
