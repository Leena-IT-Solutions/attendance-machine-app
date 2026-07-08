import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // State for loading
  bool _isLoadingCompany = true;
  bool _isLoadingEmployee = false;
  bool _isDownloadingExcel = false;
  bool _isDownloadingPdf = false;
  bool _isDownloadingEmpPdf = false;
  bool _isDeletingCycle = false;

  // Selection state
  String _selectedMonth = DateTime.now().month.toString().padLeft(2, '0');
  String _selectedYear = DateTime.now().year.toString();
  String? _selectedEmployeeCode;

  // Data state
  List<dynamic> _employeesList = [];
  String _companyStartStr = '';
  String _companyEndStr = '';
  Map<String, dynamic> _companySummary = {
    'total_employees': 0,
    'present_employees': 0,
    'absent_employees': 0,
    'attendance_rate': 0.0,
    'total_punches': 0,
  };
  List<dynamic> _companyLogs = [];

  // Employee report data
  String _empStartStr = '';
  String _empEndStr = '';
  Map<String, dynamic> _empSummary = {
    'total_days': 0,
    'present_days': 0,
    'absent_days': 0,
    'late_minutes': 0,
    'total_lop': 0.0,
  };
  List<dynamic> _empLedger = [];

  final List<String> _months = [
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
    '11',
    '12',
  ];

  final List<String> _years = List.generate(
    3,
    (i) => (DateTime.now().year - 1 + i).toString(),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadEmployees();
    _fetchCompanySummaryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      if (_tabController.index == 1 && _selectedEmployeeCode != null) {
        _fetchEmployeeReportData();
      }
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await ApiService.getEmployees();
      if (mounted) {
        setState(() {
          _employeesList = list;
          if (list.isNotEmpty) {
            _selectedEmployeeCode = list.first['code'];
          }
        });
        if (_tabController.index == 1 && _selectedEmployeeCode != null) {
          _fetchEmployeeReportData();
        }
      }
    } catch (e) {
      debugPrint('Error fetching employees list: $e');
    }
  }

  Future<void> _fetchCompanySummaryData() async {
    setState(() => _isLoadingCompany = true);
    try {
      final response = await ApiService.fetchReportSummary(
        _selectedMonth,
        _selectedYear,
      );
      if (!mounted) return;
      setState(() {
        _companyStartStr = response['start_date'] ?? '';
        _companyEndStr = response['end_date'] ?? '';
        _companySummary = response['summary'] ?? _companySummary;
        _companyLogs = response['logs'] ?? [];
        _isLoadingCompany = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingCompany = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading report: $e')));
    }
  }

  Future<void> _fetchEmployeeReportData() async {
    if (_selectedEmployeeCode == null) return;
    setState(() => _isLoadingEmployee = true);
    try {
      final response = await ApiService.fetchEmployeeReport(
        _selectedEmployeeCode!,
        _selectedMonth,
        _selectedYear,
      );
      if (!mounted) return;
      setState(() {
        _empStartStr = response['start_date'] ?? '';
        _empEndStr = response['end_date'] ?? '';
        _empSummary = response['summary'] ?? _empSummary;
        _empLedger = response['ledger'] ?? [];
        _isLoadingEmployee = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingEmployee = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading employee report: $e')),
      );
    }
  }

  Future<void> _downloadCompanyExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isDownloadingExcel = true);
    try {
      final response = await ApiService.downloadReport(
        _selectedMonth,
        _selectedYear,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath =
            '${directory.path}/Company_Matrix_${_selectedYear}_$_selectedMonth.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        _showFileActionsDialog(
          filePath,
          'Excel Matrix Sheet',
          'Company_Matrix_${_selectedYear}_$_selectedMonth.xlsx',
        );
      } else {
        throw Exception('Failed to download Matrix report');
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Excel Download Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isDownloadingExcel = false);
    }
  }

  Future<void> _downloadCompanyPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isDownloadingPdf = true);
    try {
      final response = await ApiService.downloadPdfReport(
        _selectedMonth,
        _selectedYear,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath =
            '${directory.path}/Company_Report_${_selectedYear}_$_selectedMonth.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        _showFileActionsDialog(
          filePath,
          'PDF Document',
          'Company_Report_${_selectedYear}_$_selectedMonth.pdf',
        );
      } else {
        throw Exception('Failed to download PDF report');
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('PDF Download Error: $e')));
    } finally {
      if (mounted) setState(() => _isDownloadingPdf = false);
    }
  }

  Future<void> _downloadEmployeePdf() async {
    if (_selectedEmployeeCode == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isDownloadingEmpPdf = true);
    try {
      final response = await ApiService.downloadEmployeePdf(
        _selectedEmployeeCode!,
        _selectedMonth,
        _selectedYear,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath =
            '${directory.path}/Performance_Report_${_selectedEmployeeCode}_${_selectedYear}_$_selectedMonth.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        _showFileActionsDialog(
          filePath,
          'Employee Performance PDF',
          'Performance_Report_${_selectedEmployeeCode}_${_selectedYear}_$_selectedMonth.pdf',
        );
      } else {
        throw Exception('Failed to download employee PDF');
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('PDF Download Error: $e')));
    } finally {
      if (mounted) setState(() => _isDownloadingEmpPdf = false);
    }
  }

  Future<void> _deleteSelectedCycle() async {
    // Show confirmation dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete all attendance punch records for the selected cycle ($_companyStartStr to $_companyEndStr)?\n\nThis action cannot be undone.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[800],
              foregroundColor: Colors.white,
            ),
            child: const Text('DELETE PERMANENTLY', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeletingCycle = true);
    try {
      final month = int.parse(_selectedMonth);
      final year = int.parse(_selectedYear);
      
      final response = await ApiService.deleteCycle(month, year);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Selected cycle records deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh the page data
      await _fetchCompanySummaryData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting cycle records: $e'),
          backgroundColor: Colors.red[800],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingCycle = false);
      }
    }
  }

  void _showFileActionsDialog(
    String filePath,
    String fileType,
    String fileName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              fileType.contains('PDF') ? Icons.picture_as_pdf : Icons.grid_on,
              color: fileType.contains('PDF') ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text('$fileType Ready'),
          ],
        ),
        content: Text(
          'Your $fileType has been saved successfully.\nWould you like to open it or share it?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await SharePlus.instance.share(
                ShareParams(
                  files: [XFile(filePath)],
                  subject: 'Attendance Report $fileName',
                ),
              );
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('SHARE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final result = await OpenFilex.open(filePath);
              if (!context.mounted) return;
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open file: ${result.message}'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('OPEN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: fileType.contains('PDF')
                  ? Colors.red[700]
                  : Colors.green[700],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return '${date.day} ${months[date.month - 1]} ${date.year}';
      }
    } catch (_) {}
    return dateStr;
  }

  String _getDayName(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return days[date.weekday - 1];
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reports & Analytics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(icon: Icon(Icons.grid_on_outlined), text: 'Company Matrix'),
            Tab(
              icon: Icon(Icons.person_pin_outlined),
              text: 'Employee Performance',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter section shared by both tabs
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedMonth,
                          decoration: InputDecoration(
                            labelText: 'Month',
                            labelStyle: const TextStyle(
                              color: Colors.indigo,
                              fontWeight: FontWeight.bold,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: _months
                              .map(
                                (m) =>
                                    DropdownMenuItem(value: m, child: Text(m)),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedMonth = val);
                              _fetchCompanySummaryData();
                              if (_selectedEmployeeCode != null) {
                                _fetchEmployeeReportData();
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedYear,
                          decoration: InputDecoration(
                            labelText: 'Year',
                            labelStyle: const TextStyle(
                              color: Colors.indigo,
                              fontWeight: FontWeight.bold,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: _years
                              .map(
                                (y) =>
                                    DropdownMenuItem(value: y, child: Text(y)),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedYear = val);
                              _fetchCompanySummaryData();
                              if (_selectedEmployeeCode != null) {
                                _fetchEmployeeReportData();
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCompanyMatrixTab(),
                _buildEmployeePerformanceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildCompanyMatrixTab() {
    return _isLoadingCompany
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_companyStartStr.isNotEmpty &&
                    _companyEndStr.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9), // Soft slate background
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.date_range_outlined,
                          color: Color(0xFF475569),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cycle: ${_formatDate(_companyStartStr)} - ${_formatDate(_companyEndStr)}',
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // KPI Stats Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _buildKpiCard(
                      title: 'Attendance Rate',
                      value:
                          '${((_companySummary['attendance_rate'] ?? 0.0) as num).toDouble().toStringAsFixed(1)}%',
                      color: Colors.indigo,
                      icon: Icons.trending_up,
                    ),
                    _buildKpiCard(
                      title: 'Active Staff',
                      value:
                          '${_companySummary['present_employees']} / ${_companySummary['total_employees']}',
                      color: Colors.teal,
                      icon: Icons.people_outline,
                    ),
                    _buildKpiCard(
                      title: 'Total Scans',
                      value: '${_companySummary['total_punches']}',
                      color: Colors.orange,
                      icon: Icons.fingerprint,
                    ),
                    _buildKpiCard(
                      title: 'Absenteeism',
                      value: '${_companySummary['absent_employees']}',
                      color: Colors.red,
                      icon: Icons.no_accounts_outlined,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Export Buttons
                const Text(
                  'EXPORT COMPANY MATRIX',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isDownloadingPdf
                            ? null
                            : _downloadCompanyPdf,
                        icon: _isDownloadingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf, size: 20),
                        label: const Text('COMPANY PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isDownloadingExcel
                            ? null
                            : _downloadCompanyExcel,
                        icon: _isDownloadingExcel
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.grid_on, size: 20),
                        label: const Text('EXCEL MATRIX'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Text(
                  'DANGER ZONE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isDeletingCycle ? null : _deleteSelectedCycle,
                    icon: _isDeletingCycle
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.red,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.delete_forever, size: 20),
                    label: const Text('DELETE RECORDS FOR SELECTED CYCLE'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[800],
                      side: BorderSide(color: Colors.red[800]!),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Attendance Logs
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'DAILY AUDIT LEDGER',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '${_companyLogs.length} records',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.indigo,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_companyLogs.isEmpty)
                  _buildEmptyState()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _companyLogs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final log = _companyLogs[index];
                      final isPresent = log['status'] == 'Present';
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isPresent
                                  ? Colors.indigo[50]
                                  : Colors.amber[50],
                              child: Icon(
                                isPresent
                                    ? Icons.person
                                    : Icons.warning_amber_rounded,
                                color: isPresent
                                    ? Colors.indigo
                                    : Colors.amber[800],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Code: ${log['code']} | ${_formatDate(log['date'])}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPresent
                                        ? Colors.green[50]
                                        : Colors.amber[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isPresent
                                          ? Colors.green[100]!
                                          : Colors.amber[100]!,
                                    ),
                                  ),
                                  child: Text(
                                    isPresent
                                        ? 'In: ${log['in']} | Out: ${log['out']}'
                                        : 'In: ${log['in']} | Out: --',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: isPresent
                                          ? Colors.green[800]
                                          : Colors.amber[800],
                                    ),
                                  ),
                                ),
                                if (isPresent && log['hours'] != '---') ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hrs: ${log['hours']}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
  }

  Widget _buildEmployeePerformanceTab() {
    if (_employeesList.isEmpty) {
      return const Center(
        child: Text(
          'No employees synced yet. Please sync in local settings first!',
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Employee selector Dropdown card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                value: _selectedEmployeeCode,
                decoration: const InputDecoration(
                  labelText: 'Select Employee',
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                  prefixIcon: Icon(Icons.person, color: Colors.indigo),
                  border: InputBorder.none,
                ),
                items: _employeesList.map((emp) {
                  return DropdownMenuItem<String>(
                    value: emp['code'],
                    child: Text(
                      emp['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedEmployeeCode = val);
                    _fetchEmployeeReportData();
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          _isLoadingEmployee
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(color: Colors.indigo),
                  ),
                )
              : _selectedEmployeeCode == null
              ? const Center(child: Text('Please select an employee'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_empStartStr.isNotEmpty && _empEndStr.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF1F5F9,
                          ), // Soft slate background
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.date_range_outlined,
                              color: Color(0xFF475569),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Shift Range: ${_formatDate(_empStartStr)} - ${_formatDate(_empEndStr)}',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Horizontally scrolling list of 9 KPI Cards matching second image layout
                    const Text(
                      'PERFORMANCE METRICS SUMMARY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildEmployeeKpiCell(
                            title: 'Total Days',
                            value: '${_empSummary['total_days']}',
                            color: Colors.grey,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Present',
                            value: '${_empSummary['present_days']}',
                            color: Colors.green,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Absent',
                            value: '${_empSummary['absent_days']}',
                            color: Colors.red,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Leave',
                            value: '0',
                            color: Colors.orange,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'On Duty',
                            value: '0',
                            color: Colors.purple,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Short Lv',
                            value: '0',
                            color: Colors.blue,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Overtime',
                            value: '0h',
                            color: Colors.teal,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Late Ad.',
                            value: '${((_empSummary['late_minutes'] ?? 0) as num).toStringAsFixed(1)}m',
                            color: Colors.red,
                          ),
                          _buildEmployeeKpiCell(
                            title: 'Total LOP',
                            value: ((_empSummary['total_lop'] ?? 0.0) as num)
                                .toDouble()
                                .toStringAsFixed(2),
                            color: Colors.indigo,
                            isHighlight: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Download section
                    const Text(
                      'DOWNLOAD EMPLOYEE PERFORMANCE CARD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDownloadingEmpPdf
                            ? null
                            : _downloadEmployeePdf,
                        icon: _isDownloadingEmpPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: const Text('GENERATE PERFORMANCE PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Tabular Punch History
                    const Text(
                      'MONTHLY PUNCH LEDGER HISTORY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_empLedger.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _empLedger.length,
                        itemBuilder: (context, index) {
                          final row = _empLedger[index];
                          final status = row['status'];
                          final isWorking = status == 'Working';
                          final isWeekoff = status == 'Weekoff';
                          final isHoliday = status == 'Holiday';

                          Color badgeBg = Colors.red[50]!;
                          Color badgeText = Colors.red[800]!;
                          String statusText = 'Absent';

                          if (isWorking) {
                            badgeBg = Colors.grey[100]!;
                            badgeText = Colors.grey[800]!;
                            statusText = 'Working';
                          } else if (isWeekoff) {
                            badgeBg = Colors.blueGrey[50]!;
                            badgeText = Colors.blueGrey[600]!;
                            statusText = 'Weekoff';
                          } else if (isHoliday) {
                            badgeBg = Colors.indigo[50]!;
                            badgeText = Colors.indigo[600]!;
                            statusText = 'Holiday';
                          }

                          return Card(
                            elevation: 0.5,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey[200]!),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Date & Day
                                  SizedBox(
                                    width: 75,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _formatDate(
                                            row['date'],
                                          ).split(' ').take(2).join(' '),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          _getDayName(row['date']),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: badgeText,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Punches
                                  Expanded(
                                    child: Row(
                                      children: [
                                        if (row['in'] != '---')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            margin: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo[50],
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.indigo[100]!,
                                              ),
                                            ),
                                            child: Text(
                                              row['in'].substring(0, 5),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                color: Colors.indigo,
                                              ),
                                            ),
                                          ),
                                        if (row['out'] != '---')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo[50],
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.indigo[100]!,
                                              ),
                                            ),
                                            child: Text(
                                              row['out'].substring(0, 5),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                color: Colors.indigo,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Late or LOP highlights
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (row['late_min'] > 0)
                                        Text(
                                          'Late: ${((row['late_min'] ?? 0) as num).toStringAsFixed(1)}m',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      if (row['lop'] > 0.0) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'LOP: ${row['lop'].toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Colors.red[800],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildEmployeeKpiCell({
    required String title,
    required String value,
    required Color color,
    bool isHighlight = false,
  }) {
    return Container(
      width: 75,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isHighlight ? Colors.indigo[50] : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlight ? Colors.indigo[300]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          // Top color accent bar
          Container(
            height: 3,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isHighlight
                  ? Colors.indigo[800]
                  : (color == Colors.red ? Colors.red[800] : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    // Generate custom gradients based on the theme color
    final List<Color> gradientColors;
    if (color == Colors.indigo) {
      gradientColors = [const Color(0xFF6366F1), const Color(0xFF4F46E5)]; // Indigo
    } else if (color == Colors.teal) {
      gradientColors = [const Color(0xFF14B8A6), const Color(0xFF0D9488)]; // Teal
    } else if (color == Colors.orange) {
      gradientColors = [const Color(0xFFF59E0B), const Color(0xFFD97706)]; // Amber
    } else if (color == Colors.red) {
      gradientColors = [const Color(0xFFEF4444), const Color(0xFFDC2626)]; // Red
    } else {
      gradientColors = [color.withOpacity(0.8), color];
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors[1].withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.assignment_late_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          const Text(
            'No records for this cycle',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Try choosing a different month or year.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
