import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS/Desktop
  // Better to use your machine's local IP (e.g., 192.168.x.x) for physical devices
  // static const String baseUrl = 'http://localhost:8000/api';
  // static const String baseUrl = 'http://10.0.2.2:8000/api'; //for Android devices
  // static const String baseUrl = 'http://192.168.1.5:8000/api';
  static const String baseUrl = 'https://attendance.infoleena.com/api';

  static Function? onUnauthorized;

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static void _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      // Check if it's a face mismatch returned as 401 (from legacy/un-updated server code)
      try {
        final data = jsonDecode(response.body);
        if (data is Map && (data['status'] == 'mismatch' || data['message'] == 'Face not recognized')) {
          // Do not trigger global logout for face mismatches
          return;
        }
      } catch (_) {
        // Not JSON or parse error; proceed with standard 401 handler
      }

      if (onUnauthorized != null) {
        onUnauthorized!();
      }
      throw Exception('Unauthorized');
    }
  }

  static String fixUrl(String? url) {
    if (url == null) return '';
    if (url.startsWith('http://192.168') || url.startsWith('http://10.0.2.2') || url.startsWith('http://localhost')) {
      // Extract the path after the domain
      final uri = Uri.parse(url);
      final baseUrlUri = Uri.parse(baseUrl);
      return '${baseUrlUri.scheme}://${baseUrlUri.host}${uri.path}';
    }
    return url;
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'device_name': 'mobile_app',
      }),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('user', jsonEncode(data['user']));
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to login');
    }
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    String? phone,
    required String password,
    required String passwordConfirmation,
  }) async {
    if (Platform.isIOS) {
      throw Exception("Registration is not available on iOS. Please register on the web portal.");
    }
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'password': password,
        'password_confirmation': passwordConfirmation,
        'device_name': 'mobile_app',
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('user', jsonEncode(data['user']));
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to register');
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/forgot-password'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to send reset link');
    }
  }

  static Future<void> logout() async {
    final headers = await _getHeaders();
    await http.post(Uri.parse('$baseUrl/logout'), headers: headers);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/profile'),
      headers: headers,
      body: jsonEncode(fields),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(data['user']));
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to update profile');
    }
  }

  static Future<Map<String, dynamic>> fetchProfile() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/user'),
      headers: headers,
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(data));
      return data;
    } else {
      throw Exception('Failed to fetch profile');
    }
  }

  static Future<Map<String, dynamic>> updatePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/profile/password'),
      headers: headers,
      body: jsonEncode({
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      }),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to update password');
    }
  }

  static Future<Map<String, dynamic>> deleteAccount(String password) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/profile'),
      headers: headers,
      body: jsonEncode({'password': password}),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user');
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to delete account');
    }
  }

  static Future<Map<String, dynamic>> syncEmployees() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/sync'),
      headers: headers,
    );
    _handleResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to sync employees');
    }
  }

  static Future<Map<String, dynamic>> saveAttendance({
    required String employeeCode,
    required String employeeName,
    required String scanDate,
    required String scanTime,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/save'),
      headers: headers,
      body: jsonEncode({
        'employee_code': employeeCode,
        'employee_name': employeeName,
        'scan_date': scanDate,
        'scan_time': scanTime,
      }),
    );

    _handleResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to save attendance');
    }
  }

  static Future<Map<String, dynamic>> recognizeFace({
    required String photoBase64,
    required String scanDate,
    required String scanTime,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/recognize'),
      headers: headers,
      body: jsonEncode({
        'photo_base64': photoBase64,
        'scan_date': scanDate,
        'scan_time': scanTime,
      }),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Face not recognized');
    }
  }

  static Future<List<dynamic>> getEmployees() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/employees'),
      headers: headers,
    );
    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data['employees'];
    } else {
      throw Exception(data['message'] ?? 'Failed to fetch employees');
    }
  }

  static Future<void> createEmployee(Map<String, dynamic> employeeData) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/employees'),
      headers: headers,
      body: jsonEncode(employeeData),
    );

    _handleResponse(response);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Failed to create employee');
    }
  }

  static Future<void> updateEmployee(
    int id,
    Map<String, dynamic> employeeData,
  ) async {
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/employees/$id'),
      headers: headers,
      body: jsonEncode(employeeData),
    );

    _handleResponse(response);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Failed to update employee');
    }
  }

  static Future<void> deleteEmployee(int id) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/employees/$id'),
      headers: headers,
    );

    _handleResponse(response);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Failed to delete employee');
    }
  }

  static Future<Map<String, dynamic>> deleteCycle(int month, int year) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/attendance/cycle'),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'month': month,
        'year': year,
      }),
    );

    _handleResponse(response);

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to delete records for the selected cycle');
    }
    return data;
  }

  static Future<List<dynamic>> getShifts() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/shifts'),
      headers: headers,
    );
    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data['shifts'];
    } else {
      throw Exception(data['message'] ?? 'Failed to fetch shifts');
    }
  }

  static Future<Map<String, dynamic>> createShift({
    required String name,
    required String startTime,
    required String endTime,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/shifts'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'start_time': startTime,
        'end_time': endTime,
      }),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data['shift'];
    } else {
      throw Exception(data['message'] ?? 'Failed to create shift');
    }
  }

  static Future<Map<String, dynamic>> updateShift(
    int id, {
    required String name,
    required String startTime,
    required String endTime,
  }) async {
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/shifts/$id'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'start_time': startTime,
        'end_time': endTime,
      }),
    );

    _handleResponse(response);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data['shift'];
    } else {
      throw Exception(data['message'] ?? 'Failed to update shift');
    }
  }

  static Future<void> deleteShift(int id) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/shifts/$id'),
      headers: headers,
    );

    _handleResponse(response);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Failed to delete shift');
    }
  }

  static Future<void> sendToExternalApi({
    required String url,
    required String? token,
    required Map<String, dynamic> data,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(data),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('External API error: ${response.statusCode}');
    }
  }

  static Future<http.Response> downloadReport(String month, String year) async {
    final headers = await _getHeaders();
    final url = '$baseUrl/attendance/download?month=$month&year=$year';
    final response = await http.get(Uri.parse(url), headers: headers);
    _handleResponse(response);
    return response;
  }

  static Future<Map<String, dynamic>> fetchReportSummary(String month, String year) async {
    final headers = await _getHeaders();
    final url = '$baseUrl/attendance/summary?month=$month&year=$year';
    final response = await http.get(Uri.parse(url), headers: headers);
    _handleResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch report summary');
    }
  }

  static Future<http.Response> downloadPdfReport(String month, String year) async {
    final headers = await _getHeaders();
    final url = '$baseUrl/attendance/download-pdf?month=$month&year=$year';
    final response = await http.get(Uri.parse(url), headers: headers);
    _handleResponse(response);
    return response;
  }

  static Future<Map<String, dynamic>> fetchEmployeeReport(String employeeCode, String month, String year) async {
    final headers = await _getHeaders();
    final url = '$baseUrl/attendance/employee/$employeeCode?month=$month&year=$year';
    final response = await http.get(Uri.parse(url), headers: headers);
    _handleResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch employee report');
    }
  }

  static Future<http.Response> downloadEmployeePdf(String employeeCode, String month, String year) async {
    final headers = await _getHeaders();
    final url = '$baseUrl/attendance/employee/$employeeCode/download-pdf?month=$month&year=$year';
    final response = await http.get(Uri.parse(url), headers: headers);
    _handleResponse(response);
    return response;
  }

  static Future<Map<String, dynamic>> verifySubscription({
    required String platform,
    required String productId,
    required String verificationToken,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/subscription/verify'),
      headers: headers,
      body: jsonEncode({
        'platform': platform,
        'product_id': productId,
        'verification_token': verificationToken,
      }),
    );
    _handleResponse(response);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Subscription verification failed');
    }
  }
}
