import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_timezone/flutter_timezone.dart';

import 'src/config.dart';
import 'src/planner/recurrence.dart';
import 'src/ui/app_root.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The device zone before anything is created, so new events are saved in the right zone.
  try {
    initTimeZones((await FlutterTimezone.getLocalTimezone()).identifier);
  } catch (_) {
    initTimeZones();
  }
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  }
  runApp(const DumpBoxApp());
}

class DumpBoxApp extends StatelessWidget {
  const DumpBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DumpBox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: AppConfig.isConfigured ? const AppRoot() : const NotConfiguredScreen(),
    );
  }
}
