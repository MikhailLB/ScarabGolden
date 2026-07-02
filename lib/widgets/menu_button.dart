import 'package:flutter/material.dart';

import '../theme.dart';

class MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double width;

  const MenuButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.width = 260,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 62,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF13285C),
              Color(0xFF0A173E),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold, width: 2.2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.goldLight, size: 22),
              const SizedBox(width: 10),
            ],
            Text(label, style: AppTextStyles.button),
          ],
        ),
      ),
    );
  }
}
