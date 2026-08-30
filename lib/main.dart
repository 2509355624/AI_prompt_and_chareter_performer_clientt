import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'providers/settings_provider.dart';
import 'providers/generate_provider.dart';
import 'providers/character_provider.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();

    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(apiService)..loadSettings(),
        ),
        ChangeNotifierProvider(
          create: (ctx) => GenerateProvider(ctx.read<ApiService>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => CharacterProvider(ctx.read<ApiService>()),
        ),
      ],
      child: MaterialApp(
        title: 'Console UI Master',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Consumer<SettingsProvider>(
          builder: (_, settings, __) {
            if (!settings.loaded) {
              return const Scaffold(
                backgroundColor: Color(0xFFE8DFCF),
                body: Center(child: CircularProgressIndicator()),
              );
            }
            // 默认有局域网地址时直接进工具中心；未连上也能进，右上角设置可改
            return const HomePage();
          },
        ),
      ),
    );
  }
}
