import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/screens/Profile/profile_header.dart';
import 'package:hxhmobile/screens/Profile/my_account_page.dart';
import 'package:hxhmobile/screens/Products/cart_page.dart';
import 'package:hxhmobile/screens/Profile/widgets/my_booking_page.dart';
import 'package:hxhmobile/screens/Profile/history_page.dart';
import 'package:hxhmobile/screens/Notifications/notifications_page.dart';
import 'package:hxhmobile/screens/Settings/settings_page.dart';
import 'package:hxhmobile/screens/Profile/purchased_products_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _name = 'Guest';
  String _email = '';

  Widget _navItem({
    required IconData icon,
    required String label,
    required Widget page,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String? name =
        prefs.getString('display_name') ??
        prefs.getString('full_name') ??
        prefs.getString('name');
    if (name == null || name.trim().isEmpty) {
      final first = prefs.getString('first_name');
      final last = prefs.getString('last_name');
      if (first != null && first.isNotEmpty) {
        name = (last != null && last.isNotEmpty) ? '$first $last' : first;
      }
    }
    if (name == null || name.trim().isEmpty) {
      final email = prefs.getString('email');
      if (email != null && email.isNotEmpty) {
        name = email.split('@')[0];
      }
    }
    final email = prefs.getString('email') ?? '';
    if (!mounted) return;
    setState(() {
      _name = name?.trim().isNotEmpty == true ? name!.trim() : 'Guest';
      _email = email;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // hide back button
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile header (moved to its own widget)
          ProfileHeader(name: _name, email: _email),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          // Quick links / account menu (inline to avoid extra file)
          Card(
            child: Column(
              children: [
                _navItem(
                  icon: Icons.person_outline,
                  label: 'My Account',
                  page: const MyAccountPage(),
                ),
                const Divider(height: 1),
                _navItem(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Cart',
                  page: const CartPage(),
                ),
                const Divider(height: 1),
                _navItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'My Bookings',
                  page: const MyBookingPage(),
                ),
                const Divider(height: 1),
                _navItem(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Purchased Products',
                  page: const PurchasedProductsPage(),
                ),
                const Divider(height: 1),
                _navItem(
                  icon: Icons.history,
                  label: 'History',
                  page: const HistoryPage(),
                ),
                const Divider(height: 1),
                _navItem(
                  icon: Icons.notifications_none,
                  label: 'Notifications',
                  page: const NotificationsPage(),
                ),
                const Divider(height: 1),
                _navItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  page: const SettingsPage(),
                ),
                // Divider after settings
                const Divider(height: 24, thickness: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('is_logged_in', false);
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (_) {}
                      if (context.mounted) {
                        Navigator.of(context).pushReplacementNamed('/login');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
