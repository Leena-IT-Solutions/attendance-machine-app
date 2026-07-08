import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/iap_service.dart';

class SubscriptionScreen extends StatefulWidget {
  final bool showBackButton;
  const SubscriptionScreen({super.key, this.showBackButton = true});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final IapService _iapService = IapService.instance;
  bool _isMonthly = true;
  ProductDetails? _selectedProduct;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProductsAndSelectDefault();
  }

  void _loadProductsAndSelectDefault() async {
    setState(() => _isActionLoading = true);
    await _iapService.loadProducts();
    if (mounted) {
      setState(() {
        _isActionLoading = false;
        _updateSelectedProduct();
      });
    }
  }

  void _updateSelectedProduct() {
    if (_iapService.products.isEmpty) {
      _selectedProduct = null;
      return;
    }

    // Find products matching current monthly/yearly selection
    final filtered = _iapService.products.where((p) {
      return _isMonthly ? p.id.contains('monthly') : p.id.contains('yearly');
    }).toList();

    // Default to the Bronze/lowest tier (e.g. 5 employees)
    if (filtered.isNotEmpty) {
      _selectedProduct = filtered.first;
    } else {
      _selectedProduct = _iapService.products.first;
    }
  }

  int _getLimitFromId(String id) {
    if (id.contains('unlimited')) return 999999;
    final match = RegExp(r'(\d+)').firstMatch(id);
    if (match != null) {
      final matchedText = match.group(0);
      if (matchedText != null) {
        return int.parse(matchedText);
      }
    }
    return 0;
  }

  String _getLimitText(String id) {
    final limit = _getLimitFromId(id);
    return limit == 999999 ? "Unlimited Employees" : "Up to $limit Employees";
  }

  void _handlePurchase() async {
    if (_selectedProduct == null) return;
    setState(() => _isActionLoading = true);
    await _iapService.buySubscription(_selectedProduct!, context);
    if (mounted) {
      setState(() => _isActionLoading = false);
    }
  }

  void _handleRestore() async {
    setState(() => _isActionLoading = true);
    await _iapService.restorePurchases();
    if (mounted) {
      setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _iapService.products.where((p) {
      return _isMonthly ? p.id.contains('monthly') : p.id.contains('yearly');
    }).toList();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1B4B), Color(0xFF1A237E), Color(0xFF283593)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.showBackButton)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      )
                    else
                      const SizedBox(width: 48),
                    const Text(
                      'PREMIUM PLANS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    TextButton(
                      onPressed: _isActionLoading ? null : _handleRestore,
                      child: const Text(
                        'RESTORE',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              // Title Section
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    Icon(Icons.stars, color: Colors.amber, size: 60),
                    SizedBox(height: 12),
                    Text(
                      'Upgrade Attendance Machine',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Select a plan to register more employees. Free tier supports up to 2 employees and unlimited scans.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),

              // Monthly/Yearly Toggle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isMonthly = true;
                            _updateSelectedProduct();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isMonthly ? const Color(0xFF3F51B5) : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Monthly',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isMonthly = false;
                            _updateSelectedProduct();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                            color: !_isMonthly ? const Color(0xFF3F51B5) : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Yearly (Save 15%)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Plans List
              Expanded(
                child: _iapService.isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : products.isEmpty
                        ? const Center(
                            child: Text(
                              'No products found. Please check setup.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(24),
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final prod = products[index];
                              final isSelected = _selectedProduct?.id == prod.id;
                              final limitText = _getLimitText(prod.id);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedProduct = prod;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF3F51B5).withOpacity(0.3)
                                          : Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF7986CB)
                                            : Colors.white12,
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              limitText,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              prod.description,
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          prod.price,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),

              // Bottom Button Section
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isActionLoading || _selectedProduct == null
                            ? null
                            : _handlePurchase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[600],
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: Colors.grey[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        child: _isActionLoading
                            ? const CircularProgressIndicator(color: Colors.black)
                            : const Text(
                                'SUBSCRIBE NOW',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Subscriptions automatically renew. Cancel anytime in App Store / Google Play account settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
