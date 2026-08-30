import 'package:flutter/material.dart';

/// 小红书贴纸风格主题
/// 配色参考 character-paper.css
class AppTheme {
  // 颜色
  static const Color shell = Color(0xFFE8DFCF); // 背景底色
  static const Color surface = Color(0xFFF6EDDA); // 表层
  static const Color surface2 = Color(0xFFEFE3CC); // 第二层
  static const Color textColor = Color(0xFF26221C); // 主文字
  static const Color text2 = Color(0xAE26221C); // 次级文字
  static const Color textMute = Color(0x6B26221C); // 弱化文字
  static const Color accent = Color(0xFFE8503A); // 红色强调
  static const Color accentSoft = Color(0x1FE8503A); // 红色软底
  static const Color accent2 = Color(0xFF2F7CD6); // 蓝色强调
  static const Color card = Color(0xFFFFFDF6); // 卡片白底
  static const Color rule = Color(0x2E26221C); // 分割线

  // 阴影
  static const List<BoxShadow> stickerShadow = [
    BoxShadow(
      color: Color(0xE626221C),
      offset: Offset(5, 6),
      blurRadius: 0,
    ),
  ];

  static const List<BoxShadow> stickerShadowSm = [
    BoxShadow(
      color: Color(0xD926221C),
      offset: Offset(3, 3),
      blurRadius: 0,
    ),
  ];

  // 圆角
  static const double radiusLg = 14;
  static const double radiusMd = 10;
  static const double radiusSm = 6;

  // 边框
  static const double borderWidth = 2.5;

  // 主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: shell,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        surface: card,
        primary: accent,
        secondary: accent2,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: textColor,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textColor,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: text2,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: shell,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: textColor, width: 2),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          side: const BorderSide(color: textColor, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: textColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: textColor, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: accent,
        unselectedItemColor: textMute,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
