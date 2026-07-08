import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'face_registration_screen.dart';

class AddEditEmployeeScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;
  const AddEditEmployeeScreen({super.key, this.employee});

  @override
  State<AddEditEmployeeScreen> createState() => _AddEditEmployeeScreenState();
}

class _AddEditEmployeeScreenState extends State<AddEditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  
  Uint8List? _imageBytes;
  String? _photoUrl;
  bool _isLoading = false;
  final _picker = ImagePicker();
  Map<String, dynamic>? _faceSignature;
  int _expectedDimension = 512; // Default fallback
  List<dynamic> _shifts = [];
  int? _selectedShiftId;

  bool get _isEditing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employee?['name']);
    _codeController = TextEditingController(text: widget.employee?['code']);
    _photoUrl = widget.employee?['photo_url'];
    if (widget.employee?['face_signature'] != null) {
      _faceSignature = Map<String, dynamic>.from(widget.employee!['face_signature']);
    }
    _selectedShiftId = widget.employee?['shift_id'];
    _loadActiveDimension();
    _fetchShifts();
  }

  Future<void> _fetchShifts() async {
    try {
      final shifts = await ApiService.getShifts();
      if (mounted) {
        setState(() {
          _shifts = shifts;
          // Ensure selected ID exists in the list or is null
          final hasSelected = shifts.any((s) => s['id'] == _selectedShiftId);
          if (!hasSelected) {
            _selectedShiftId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching shifts: $e');
    }
  }

  String _formatTimeStr(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final formattedMinute = minute.toString().padLeft(2, '0');
      return '$formattedHour:$formattedMinute $ampm';
    } catch (_) {
      return timeStr;
    }
  }

  Future<void> _loadActiveDimension() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _expectedDimension = prefs.getInt('active_biometric_dimension') ?? 512;
        });
      }
    } catch (e) {
      debugPrint('Error loading active dimension: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _registerFace() async {
    try {
      // Open Face Registration Screen
      if (!mounted) return;
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(builder: (context) => const FaceRegistrationScreen()),
      );

      if (result != null) {
        setState(() {
          _imageBytes = result['image_bytes'];
          _faceSignature = result['face_signature'];
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Face signature captured successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      debugPrint('Face registration error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Library'),
                onTap: () {
                  _pickImage(ImageSource.gallery);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 50);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final Map<String, dynamic> data = {
          'name': _nameController.text,
          'code': _codeController.text,
          'face_signature': _faceSignature,
          'shift_id': _selectedShiftId,
        };

        if (_imageBytes != null) {
          data['photo_base64'] = 'data:image/png;base64,${base64Encode(_imageBytes!)}';
        }

        if (_isEditing) {
          await ApiService.updateEmployee(widget.employee!['id'], data);
        } else {
          await ApiService.createEmployee(data);
        }

        if (mounted) {
          Navigator.pop(context, true);
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
    bool hasSig = _faceSignature != null && _faceSignature!.isNotEmpty;
    bool isValidSig = false;
    bool isOutdatedSig = false;

    if (hasSig) {
      final firstSig = _faceSignature!.values.first;
      if (firstSig is List) {
        if (firstSig.length == _expectedDimension) {
          isValidSig = true;
        } else {
          isOutdatedSig = true;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Employee' : 'Add Employee'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.indigo[50],
                      child: ClipOval(
                        child: _imageBytes != null
                            ? Image.memory(_imageBytes!, width: 120, height: 120, fit: BoxFit.cover)
                            : (_photoUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: ApiService.fixUrl(_photoUrl),
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const CircularProgressIndicator(),
                                    errorWidget: (context, url, error) => const Icon(Icons.person, size: 60, color: Colors.indigo),
                                  )
                                : const Icon(Icons.person, size: 60, color: Colors.indigo)),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: Colors.indigo,
                        child: IconButton(
                           icon: const Icon(Icons.camera_alt, color: Colors.white),
                          onPressed: () => _showPicker(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty ?? true ? 'Enter name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Employee Code / ID',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty ?? true ? 'Enter employee code' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _shifts.any((s) => s['id'] == _selectedShiftId) ? _selectedShiftId : null,
                decoration: const InputDecoration(
                  labelText: 'Shift Template',
                  prefixIcon: Icon(Icons.schedule_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('Standard Shift (07:30 AM - 04:30 PM)'),
                  ),
                  ..._shifts.map((shift) {
                    return DropdownMenuItem<int>(
                      value: shift['id'] as int,
                      child: Text('${shift['name']} (${_formatTimeStr(shift['start_time'])} - ${_formatTimeStr(shift['end_time'])})'),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedShiftId = val;
                  });
                },
              ),
              const SizedBox(height: 24),
              // Face Signature Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isValidSig 
                      ? Colors.green[50] 
                      : (isOutdatedSig ? Colors.red[50] : Colors.orange[50]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isValidSig 
                        ? Colors.green 
                        : (isOutdatedSig ? Colors.red : Colors.orange),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isValidSig 
                          ? Icons.face 
                          : (isOutdatedSig ? Icons.warning_amber_rounded : Icons.face_retouching_off),
                      color: isValidSig 
                          ? Colors.green 
                          : (isOutdatedSig ? Colors.red : Colors.orange),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isValidSig 
                                ? 'Face Signature Registered ($_expectedDimension)' 
                                : (isOutdatedSig ? 'Face Signature Incompatible' : 'Face Signature Missing'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isValidSig 
                                  ? Colors.green[700] 
                                  : (isOutdatedSig ? Colors.red[700] : Colors.orange[700]),
                            ),
                          ),
                          Text(
                            isValidSig 
                                ? 'Biometrics are active and compatible.' 
                                : (isOutdatedSig 
                                    ? 'Needs rescan for new $_expectedDimension-dim model.' 
                                    : 'Scan face to enable recognition.'),
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _registerFace,
                      icon: Icon(isValidSig 
                          ? Icons.refresh 
                          : (isOutdatedSig ? Icons.build_circle_outlined : Icons.camera_front)),
                      label: Text(isValidSig 
                          ? 'Rescan' 
                          : (isOutdatedSig ? 'Fix' : 'Scan')),
                      style: TextButton.styleFrom(
                        foregroundColor: isValidSig 
                            ? Colors.green 
                            : (isOutdatedSig ? Colors.red : Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEditing ? 'UPDATE EMPLOYEE' : 'SAVE EMPLOYEE',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
