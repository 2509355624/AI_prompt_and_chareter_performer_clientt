import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 贴纸风格卡片
class StickerCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final double? borderRadius;
  final List<BoxShadow>? shadow;
  final double borderWidth;
  final VoidCallback? onTap;
  final double width;
  final double? height;

  const StickerCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.backgroundColor,
    this.borderRadius,
    this.shadow,
    this.borderWidth = 2.5,
    this.onTap,
    this.width = double.infinity,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.card,
        border: Border.all(
          color: AppTheme.textColor,
          width: borderWidth,
        ),
        borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusLg),
        boxShadow: shadow ?? AppTheme.stickerShadow,
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusLg),
        child: card,
      );
    }
    return card;
  }
}

/// 贴纸风格按钮
class StickerButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;
  final double fontSize;

  const StickerButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isPrimary ? AppTheme.accent : Colors.white;
    final fgColor = isPrimary ? Colors.white : AppTheme.textColor;

    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: AppTheme.textColor, width: 2),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Text(text, style: TextStyle(fontSize: fontSize)),
                ],
              ),
      ),
    );
  }
}

/// 贴纸风格输入框
class StickerInput extends StatelessWidget {
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final int maxLines;
  final int? maxLength;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;

  const StickerInput({
    super.key,
    this.hintText,
    this.controller,
    this.focusNode,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppTheme.textMute),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.textColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.textColor, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        counterText: '',
      ),
    );
  }
}

/// 状态指示器（小圆点 + 文字）
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color dotColor;

  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    required this.dotColor,
  });

  factory StatusBadge.ok(String text) => StatusBadge(
        text: text,
        color: const Color(0xFF1A7A3A),
        dotColor: const Color(0xFF1A7A3A),
      );

  factory StatusBadge.error(String text) => StatusBadge(
        text: text,
        color: AppTheme.accent,
        dotColor: AppTheme.accent,
      );

  factory StatusBadge.warning(String text) => StatusBadge(
        text: text,
        color: const Color(0xFFB8860B),
        dotColor: const Color(0xFFB8860B),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.textColor, width: 2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}
