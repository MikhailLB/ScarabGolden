import 'package:flutter/material.dart';

import '../bridge/insight.dart';
import '../theme.dart';
import '../widgets/menu_button.dart';
import 'levels_screen.dart';
import 'webview_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  static const _privacyUrl =
      'https://scarabgolden.com/privacy-policy.html';
  static const _supportUrl = 'https://scarabgolden.com/support.html';

  @override
  void initState() {
    super.initState();
    Insight.screen('menu');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/bgmenu.webp',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.darkNavy),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0x99000000),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.gold, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black87,
                                  blurRadius: 24,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/scarab.jpg',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MenuButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'PLAY',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LevelsScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        MenuButton(
                          icon: Icons.privacy_tip_outlined,
                          label: 'PRIVACY POLICY',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WebPageScreen(
                                title: 'Privacy Policy',
                                url: _privacyUrl,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        MenuButton(
                          icon: Icons.support_agent,
                          label: 'SUPPORT',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WebPageScreen(
                                title: 'Support',
                                url: _supportUrl,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'v1.0.0',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
