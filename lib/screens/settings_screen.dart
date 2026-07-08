import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'attendance_api_screen.dart';
import 'shift_screen.dart';
import 'subscription_screen.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final settingsProvider = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Section
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.indigo[100],
                    child: Text(
                      user?['name']?.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?['name'] ?? 'User Name',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?['email'] ?? 'email@example.com',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Premium Subscription/Upgrade Card
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1E1B4B), // indigo-950
                    Color(0xFF312E81), // indigo-900
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (Colors.amber[400] ?? Colors.amber).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star,
                      color: Colors.amber,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR SUBSCRIPTION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getPlanName(user?['max_employees']),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _getPlanDetails(user?['max_employees']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.indigo[100] ?? Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[500] ?? Colors.amber,
                      foregroundColor: const Color(0xFF1E1B4B),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Account Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Edit Profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.api_outlined),
            title: const Text('Attendance API'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AttendanceApiScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Shift Templates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShiftScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline, color: Colors.indigo),
            title: const Text('Subscription Plans'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Biometric Scanner Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Match Sensitivity (Threshold)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        settingsProvider.matchThreshold.toStringAsFixed(2),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lower values are stricter (e.g. 0.65). Higher values make it easier to match people wearing spectacles or under dynamic light, but slightly increase the risk of false positives.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Slider(
                    value: settingsProvider.matchThreshold,
                    min: 0.50,
                    max: 1.00,
                    divisions: 50,
                    label: settingsProvider.matchThreshold.toStringAsFixed(2),
                    onChanged: (val) {
                      settingsProvider.setMatchThreshold(
                        double.parse(val.toStringAsFixed(2)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.face_retouching_natural),
            title: const Text('Mask & Goggles Reminder'),
            subtitle: const Text(
              'Prompts users to remove accessories when scanning',
            ),
            trailing: Switch(
              value: settingsProvider.showMaskWarning,
              onChanged: (val) {
                settingsProvider.setShowMaskWarning(val);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Blink Liveness Verification'),
            subtitle: const Text(
              'Requires users to blink to verify liveness (prevents photo spoofing)',
            ),
            trailing: Switch(
              value: settingsProvider.enableBlinkLiveness,
              onChanged: (val) {
                settingsProvider.setEnableBlinkLiveness(val);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Camera Resolution'),
            subtitle: Text(
              'Current Preset: ${settingsProvider.cameraResolution.toUpperCase()}',
            ),
            trailing: DropdownButton<String>(
              value: settingsProvider.cameraResolution,
              onChanged: (String? val) {
                if (val != null) {
                  settingsProvider.setCameraResolution(val);
                }
              },
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low (240p)')),
                DropdownMenuItem(
                  value: 'medium',
                  child: Text('Medium (720p/480p)'),
                ),
                DropdownMenuItem(value: 'high', child: Text('High (1080p)')),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'App Configuration',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API Base URL'),
            subtitle: const Text(ApiService.baseUrl),
            onTap: () {
              // Show dialog to edit URL if needed
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Notifications'),
            trailing: Switch(value: true, onChanged: (v) {}),
          ),

          const SizedBox(height: 24),
          const Text(
            'Danger Zone',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.red,
            ),
            title: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => _showDeleteAccountDialog(context),
          ),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.read<AuthProvider>().logout(),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'LOGOUT',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'v1.0.0',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _getPlanName(dynamic maxEmployees) {
    if (maxEmployees == null) return 'Free Tier';
    final limit = int.tryParse(maxEmployees.toString()) ?? 2;
    if (limit <= 2) return 'Free Tier';
    if (limit == 5) return 'Bronze Plan';
    if (limit == 10) return 'Silver Plan';
    if (limit == 20) return 'Gold Plan';
    if (limit == 50) return 'Platinum Plan';
    if (limit == 100) return 'Diamond Plan';
    if (limit >= 999999) return 'Enterprise Plan';
    return 'Premium Plan ($limit)';
  }

  String _getPlanDetails(dynamic maxEmployees) {
    if (maxEmployees == null) return 'Up to 2 employees allowed';
    final limit = int.tryParse(maxEmployees.toString()) ?? 2;
    if (limit <= 2) return 'Up to 2 employees allowed';
    if (limit >= 999999) return 'Unlimited employees allowed';
    return 'Up to $limit employees allowed';
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete Account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This action is permanent and cannot be undone. All your data will be removed.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Enter password to confirm',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty) return;
                      setState(() => isLoading = true);
                      try {
                        await context.read<AuthProvider>().deleteAccount(
                          passwordController.text,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      } finally {
                        if (context.mounted) setState(() => isLoading = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('DELETE'),
            ),
          ],
        ),
      ),
    );
  }

}
