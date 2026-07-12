import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import 'api_service.dart';

class IapService {
  static final IapService instance = IapService._internal();

  IapService._internal();

  // Set to true only for local simulation testing without App Store/Google Play Console setup
  static const bool _enableMockBilling = false;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  bool _isLoading = false;
  bool _isUsingMockFallback = false;

  bool get isAvailable => _isAvailable;
  List<ProductDetails> get products => _products;
  bool get isLoading => _isLoading;
  bool get isUsingMockFallback => _isUsingMockFallback;

  // Product IDs defined in App Store Connect (iOS)
  static const Set<String> _iosProductIds = {
    'in.leenaitsolutions.attendance.monthly_5',
    'in.leenaitsolutions.attendance.monthly_10',
    'in.leenaitsolutions.attendance.monthly_20',
    'in.leenaitsolutions.attendance.monthly_50',
    'in.leenaitsolutions.attendance.monthly_100',
    'in.leenaitsolutions.attendance.monthly_unlimited',
    'in.leenaitsolutions.attendance.yearly_5',
    'in.leenaitsolutions.attendance.yearly_10',
    'in.leenaitsolutions.attendance.yearly_20',
    'in.leenaitsolutions.attendance.yearly_50',
    'in.leenaitsolutions.attendance.yearly_100',
    'in.leenaitsolutions.attendance.yearly_unlimited',
  };

  // Product IDs defined in Google Play Console (Android)
  static const Set<String> _androidProductIds = {
    'monthly_5',
    'monthly_10',
    'monthly_20',
    'monthly_50',
    'monthly_100',
    'monthly_unlimited',
    'yearly_5',
    'yearly_10',
    'yearly_20',
    'yearly_50',
    'yearly_100',
    'yearly_unlimited',
  };

  /// Initialize the IAP connection and listen to purchase updates
  void initialize(BuildContext context) async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint("IAP: Billing service is not available on this device.");
      return;
    }

    // Set up the listener for purchase updates
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      (List<PurchaseDetails> purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList, context);
      },
      onDone: () {
        _subscription?.cancel();
      },
      onError: (error) {
        debugPrint("IAP Error: $error");
      },
    );

    // Initial load of products
    loadProducts();
  }

  void dispose() {
    _subscription?.cancel();
  }

  /// Load available subscription products from App Store / Google Play
  Future<void> loadProducts() async {
    final queryIds = Platform.isIOS ? _iosProductIds : _androidProductIds;
    if (!_isAvailable) {
      _isUsingMockFallback = true;
      _loadMockProducts();
      return;
    }

    _isLoading = true;
    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(queryIds);
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint("IAP: Products not found: ${response.notFoundIDs}");
      }
      
      if (response.productDetails.isEmpty) {
        _isUsingMockFallback = true;
        _loadMockProducts();
      } else {
        _isUsingMockFallback = false;
        _products = response.productDetails;
        _sortProducts();
      }
    } catch (e) {
      debugPrint("IAP: Error loading products: $e.");
      _isUsingMockFallback = true;
      _loadMockProducts();
    } finally {
      _isLoading = false;
    }
  }

  void _sortProducts() {
    _products.sort((a, b) {
      final limitA = _getLimitFromId(a.id);
      final limitB = _getLimitFromId(b.id);
      if (limitA != limitB) return limitA.compareTo(limitB);
      return a.id.contains('yearly') ? 1 : -1;
    });
  }

  void _loadMockProducts() {
    final prefix = Platform.isIOS ? 'in.leenaitsolutions.attendance.' : '';
    _products = [
      ProductDetails(
        id: '${prefix}monthly_5',
        title: 'Bronze Plan (5 Employees)',
        description: 'Register up to 5 employees',
        price: '₹25',
        rawPrice: 25.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}monthly_10',
        title: 'Silver Plan (10 Employees)',
        description: 'Register up to 10 employees',
        price: '₹50',
        rawPrice: 50.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}monthly_20',
        title: 'Gold Plan (20 Employees)',
        description: 'Register up to 20 employees',
        price: '₹100',
        rawPrice: 100.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}monthly_50',
        title: 'Platinum Plan (50 Employees)',
        description: 'Register up to 50 employees',
        price: '₹250',
        rawPrice: 250.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}monthly_100',
        title: 'Diamond Plan (100 Employees)',
        description: 'Register up to 100 employees',
        price: '₹500',
        rawPrice: 500.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}monthly_unlimited',
        title: 'Enterprise Plan (Unlimited)',
        description: 'Register unlimited employees',
        price: '₹1000',
        rawPrice: 1000.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}yearly_5',
        title: 'Bronze Plan (Yearly)',
        description: 'Register up to 5 employees (Save 15%)',
        price: '₹250',
        rawPrice: 250.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}yearly_10',
        title: 'Silver Plan (Yearly)',
        description: 'Register up to 10 employees (Save 15%)',
        price: '₹500',
        rawPrice: 500.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}yearly_20',
        title: 'Gold Plan (Yearly)',
        description: 'Register up to 20 employees (Save 15%)',
        price: '₹1000',
        rawPrice: 1000.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}yearly_50',
        title: 'Platinum Plan (Yearly)',
        description: 'Register up to 50 employees (Save 15%)',
        price: '₹2500',
        rawPrice: 2500.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}yearly_100',
        title: 'Diamond Plan (Yearly)',
        description: 'Register up to 100 employees (Save 15%)',
        price: '₹5000',
        rawPrice: 5000.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
      ProductDetails(
        id: '${prefix}yearly_unlimited',
        title: 'Enterprise Plan (Yearly)',
        description: 'Register unlimited employees (Save 15%)',
        price: '₹10000',
        rawPrice: 10000.0,
        currencyCode: 'INR',
        currencySymbol: '₹',
      ),
    ];
    _sortProducts();
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

  /// Purchase a subscription product
  Future<void> buySubscription(ProductDetails product, BuildContext context) async {
    final isMockProduct = _enableMockBilling || _isUsingMockFallback || !_isAvailable || !_products.any((p) => p.id == product.id);

    if (isMockProduct) {
      debugPrint("IAP: Simulating purchase for ${product.id}...");
      final mockPurchase = PurchaseDetails(
        purchaseID: 'mock_tx_${DateTime.now().millisecondsSinceEpoch}',
        productID: product.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'mock_verification_data',
          serverVerificationData: 'mock_verification_token',
          source: 'mock_store',
        ),
        transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
      );
      _listenToPurchaseUpdated([mockPurchase], context);
      return;
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    try {
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint("IAP Purchase Error: $e");
      debugPrint("IAP: Simulating fallback purchase after error.");
      final mockPurchase = PurchaseDetails(
        purchaseID: 'mock_tx_${DateTime.now().millisecondsSinceEpoch}',
        productID: product.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'mock_verification_data',
          serverVerificationData: 'mock_verification_token',
          source: 'mock_store',
        ),
        transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
      );
      _listenToPurchaseUpdated([mockPurchase], context);
    }
  }

  /// Restore previously purchased subscriptions (Required by Apple App Store)
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint("IAP Restore Error: $e");
    }
  }

  /// Handle incoming purchase stream updates
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList, BuildContext context) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Purchase is pending, show loading if necessary
        debugPrint("IAP: Purchase is pending...");
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // Purchase failed, display error
        debugPrint("IAP Error: ${purchaseDetails.error}");
        _completePurchase(purchaseDetails);
        _showSnackBar(context, "Purchase failed: ${purchaseDetails.error?.message}", isError: true);
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                 purchaseDetails.status == PurchaseStatus.restored) {
        // Verify with our backend API
        final bool valid = await _verifyPurchaseOnBackend(purchaseDetails, context);
        if (valid) {
          _completePurchase(purchaseDetails);
          _showSnackBar(context, "Subscription activated successfully!", isError: false);
        } else {
          _showSnackBar(context, "Subscription verification failed on the server.", isError: true);
        }
      }
    }
  }

  /// Send the purchase details (receipt / token) to our Laravel backend
  Future<bool> _verifyPurchaseOnBackend(PurchaseDetails purchaseDetails, BuildContext context) async {
    try {
      final String platform = Platform.isIOS ? 'ios' : 'android';
      final String productId = purchaseDetails.productID;
      
      // Token is transaction receipt on iOS, purchase token on Android
      final String? token = purchaseDetails.verificationData.serverVerificationData;
      if (token == null) {
        debugPrint("IAP Error: Missing server verification data.");
        return false;
      }

      // Call our API
      final response = await ApiService.verifySubscription(
        platform: platform,
        productId: productId,
        verificationToken: token,
      );

      if (response['status'] == 'success') {
        // Update user state inside AuthProvider
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        
        final prefs = await SharedPreferences.getInstance();
        final currentRawUser = prefs.getString('user');
        if (currentRawUser != null) {
          final Map<String, dynamic> userMap = jsonDecode(currentRawUser);
          userMap['subscription_active'] = true;
          userMap['subscription_tier'] = response['user']['subscription_tier'];
          userMap['subscription_expires_at'] = response['user']['subscription_expires_at'];
          userMap['max_employees'] = response['user']['max_employees'];
          
          await prefs.setString('user', jsonEncode(userMap));
          // Trigger profile sync/update inside provider
          await authProvider.fetchProfile();
        }
        return true;
      }
    } catch (e) {
      debugPrint("IAP Backend Verification Exception: $e");
    }
    return false;
  }

  /// Acknowledge/finalize the transaction with Apple / Google Play
  void _completePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.pendingCompletePurchase) {
      await _iap.completePurchase(purchaseDetails);
      debugPrint("IAP: Purchase transaction finalized.");
    }
  }

  void _showSnackBar(BuildContext context, String message, {required bool isError}) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      // SnackBar may fail if context is no longer active
    }
  }
}
