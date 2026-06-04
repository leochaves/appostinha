import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _bg = Color(0xFF0D1117);
const _primary = Color(0xFF00C851);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final onPerfil = location == '/perfil';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: _bg,
          border: Border(top: BorderSide(color: _border, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _BarItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Início',
                  active: !onPerfil,
                  onTap: () => context.go('/'),
                ),
                _BarItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Perfil',
                  active: onPerfil,
                  onTap: () => context.go('/perfil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon,
                color: active ? _primary : _muted, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: active ? _primary : _muted)),
          ],
        ),
      ),
    );
  }
}
