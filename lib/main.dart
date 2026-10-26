/// App entry point with global crash guards.
///
/// Defense in depth:
///  * runZonedGuarded          -> catches every uncaught async error
///  * FlutterError.onError     -> catches framework/widget build errors
///  * PlatformDispatcher.onError -> catches platform dispatch errors
///  * guarded boot sequence    -> the app ALWAYS reaches runApp(); on
///    storage/plugin failure a fallback error screen is shown instead of a
///    permanent white screen.
library;

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/theme.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1) Framework errors (build/layout/paint) - present + record, never crash.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[flutter-error] ${details.exceptionAsString()}');
      };
      // 2) Uncaught platform dispatch errors.
      PlatformDispatcher.instance.onError = (e, st) {
        debugPrint('[platform-error] $e\n$st');
        return true;
      };

      // 3) Boot: every step is individually guarded so one failure can never
      //    leave the user on a white screen.
      await boot();
    },
    (e, st) {
      debugPrint('[uncaught-zone-error] $e\n$st');
    },
  );
}

Future<void> boot() async {
  // Cosmetics - safe to fail.
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  } catch (e) {
    debugPrint('[boot] orientation: $e');
  }

  // Notifications - safe to fail (service degrades to no-ops).
  try {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
  } catch (e) {
    debugPrint('[boot] notifications: $e');
  }

  // Storage root - retry once, then continue (dirs are created lazily anyway).
  try {
    await ensureRootDir();
  } catch (e) {
    debugPrint('[boot] ensureRootDir: $e');
    try {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await ensureRootDir();
    } catch (e2) {
      debugPrint('[boot] ensureRootDir retry: $e2');
    }
  }

  AppDependencies? deps;
  Object? bootError;
  StackTrace? bootStack;
  try {
    final root = await resolveRootDir();
    deps = await AppDependencies.build(rootDir: root);
    await deps.accountManager.loadAll();
    await configureBackgroundService(enabled: deps.settings.serviceEnabled);
  } catch (e, st) {
    bootError = e;
    bootStack = st;
    debugPrint('[boot] FATAL: $e\n$st');
  }

  if (deps != null) {
    runApp(SibleMinerApp(deps: deps));
  } else {
    // Last-resort fallback: never leave a white screen.
    runApp(_BootErrorApp(error: '$bootError', stack: bootStack));
  }
}

/// Minimal error app shown when critical dependencies fail to build.
class _BootErrorApp extends StatelessWidget {
  final String error;
  final StackTrace? stack;

  const _BootErrorApp({required this.error, this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sible Miner',
      debugShowCheckedModeBanner: false,
      theme: SibleTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 56, color: SibleTheme.warning),
                    const SizedBox(height: 16),
                    Text(
                      'Gagal menyiapkan data aplikasi',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Penyimpanan lokal tidak dapat dibuka. Coba buka ulang '
                      'aplikasi; data yang sudah tersimpan tidak akan hilang.\n\n'
                      'Detail: $error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => exitAppAndRestart(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Close the app process; the user can relaunch cleanly from the launcher.
  void exitAppAndRestart() {
    // nothing fancy: just pop the process via SystemNavigator.
    SystemNavigator.pop();
  }
}
