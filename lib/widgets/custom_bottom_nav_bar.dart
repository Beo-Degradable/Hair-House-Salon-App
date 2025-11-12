import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const CustomBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = const [
      (_IconPair(Icons.home_outlined, Icons.home), 'Home'),
      (
        _IconPair(Icons.design_services_outlined, Icons.design_services),
        'Services',
      ),
      (_IconPair(Icons.shopping_bag_outlined, Icons.shopping_bag), 'Products'),
      (_IconPair(Icons.person_outline, Icons.person), 'Profile'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (i) {
              final active = i == selectedIndex;
              final (icons, label) = items[i];
              final color = active
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.7);
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? cs.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          active ? icons.filled : icons.outline,
                          color: color,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _IconPair {
  final IconData outline;
  final IconData filled;
  const _IconPair(this.outline, this.filled);
}

/// A lightweight shell that keeps the bottom navbar persistent
/// and swaps between the provided [pages] using an IndexedStack.
class CustomBottomNavScaffold extends StatefulWidget {
  final List<Widget> pages;
  final int initialIndex;
  final void Function(int, {String? highlight})? onTabSwitch;

  CustomBottomNavScaffold({
    super.key,
    required this.pages,
    this.initialIndex = 0,
    this.onTabSwitch,
  }) : assert(pages.length == 4, 'Expected exactly 4 pages');

  @override
  State<CustomBottomNavScaffold> createState() =>
      _CustomBottomNavScaffoldState();
}

class _CustomBottomNavScaffoldState extends State<CustomBottomNavScaffold> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _restoreIndex();
  }

  Future<void> _restoreIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final i = prefs.getInt('last_nav_index');
    if (i != null && i >= 0 && i < widget.pages.length) {
      if (mounted) setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: widget.pages),
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _index,
        onTap: (i) async {
          setState(() => _index = i);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_nav_index', i);
          if (widget.onTabSwitch != null) widget.onTabSwitch!(i);
        },
      ),
    );
  }
}
