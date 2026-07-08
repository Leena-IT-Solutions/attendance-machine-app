import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class AttendanceApiScreen extends StatefulWidget {
  const AttendanceApiScreen({super.key});

  @override
  State<AttendanceApiScreen> createState() => _AttendanceApiScreenState();
}

class _AttendanceApiScreenState extends State<AttendanceApiScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  int _monthStartDate = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _urlController = TextEditingController(text: user?['attendance_api_url']);
    _tokenController = TextEditingController(text: user?['api_token']);
    _monthStartDate = user?['month_start_date'] ?? 1;
  }

  void _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await context.read<AuthProvider>().updateProfile({
          'attendance_api_url': _urlController.text,
          'api_token': _tokenController.text,
          'month_start_date': _monthStartDate,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attendance API settings saved!')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance API'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Attendance API Configuration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Define the endpoint where the attendance data should be sent when a face matches.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              
              const Text('Your API Token', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  hintText: '123456789',
                  border: OutlineInputBorder(),
                  helperText: 'Use this token as a Bearer Token when making requests to your Attendance API.',
                ),
              ),
              const SizedBox(height: 24),
              
              const Text('Attendance API URL', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  hintText: 'https://api.example.com/attendance',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (!Uri.parse(value).isAbsolute) return 'Enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              const Text('Report Cycle Start Date', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _monthStartDate,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  helperText: 'The day of the month when your attendance cycle starts (e.g., 26th to 25th).',
                ),
                items: List.generate(31, (index) => index + 1).map((day) {
                  return DropdownMenuItem(
                    value: day,
                    child: Text('$day${_getDaySuffix(day)} of month'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _monthStartDate = val!),
              ),
              const SizedBox(height: 40),
              
              SizedBox(
                width: 120,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1F26),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
}
