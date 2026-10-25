import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();
  await ensureRootDir();

  final root = await resolveRootDir();
  final deps = await AppDependencies.build(rootDir: root);
  await deps.accountManager.loadAll();

  // Configure the foreground worker according to stored settings.
  await configureBackgroundService(enabled: deps.settings.serviceEnabled);

  runApp(SibleMinerApp(deps: deps));
}
