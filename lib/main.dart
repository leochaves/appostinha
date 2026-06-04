import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'router.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const ApostinhaApp());
}

class ApostinhaApp extends StatelessWidget {
  const ApostinhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 600
            ? constraints.maxWidth
            : constraints.maxWidth * 0.5;
        return Center(
          child: ClipRect(
            child: SizedBox(
              width: width,
              child: MaterialApp.router(
                title: 'APPostinha',
                debugShowCheckedModeBanner: false,
                routerConfig: router,
                theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF00C851),
                    brightness: Brightness.dark,
                  ),
                  scaffoldBackgroundColor: const Color(0xFF0D1117),
                  useMaterial3: true,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
