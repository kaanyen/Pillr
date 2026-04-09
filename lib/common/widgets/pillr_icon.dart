import 'package:flutter/material.dart';

/// Lucide icons need the `Lucide` font; this wrapper applies [color] explicitly so
/// icons stay visible inside buttons and tinted surfaces (matches DrewHub-style UI).
class PillrIcon extends StatelessWidget {
  const PillrIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
  });

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: color ?? IconTheme.of(context).color);
  }
}
