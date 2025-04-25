import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MarketplaceProvider extends ChangeNotifier {
  List<CompostProduct> compostProducts = [];
  List<CompostProduct> filteredProducts = [];
  bool isLoading = false;
  String? errorMessage;
  String selectedFilter = 'All';
  RangeValues priceRange = const RangeValues(0, 1000);
  bool availabilityFilter = true;

  // New field for tracking user's orders
  List<Order> userOrders = [];

  MarketplaceProvider() {
    loadProducts();
    _setupProductsStream();
    _setupOrdersStream();
  }

  StreamSubscription<QuerySnapshot>? _productsSubscription;
  StreamSubscription<QuerySnapshot>? _ordersSubscription;

  void _setupProductsStream() {
    _productsSubscription = FirebaseFirestore.instance
        .collection('products')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      updateProductsFromSnapshot(snapshot);
    }, onError: (error) {
      errorMessage = 'Failed to load products: $error';
      isLoading = false;
      notifyListeners();
    });
  }

  void _setupOrdersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _ordersSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('buyerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _updateOrdersFromSnapshot(snapshot);
    }, onError: (error) {
      errorMessage = 'Failed to load orders: $error';
      notifyListeners();
    });
  }

  Future<void> loadProducts() async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .orderBy('createdAt', descending: true)
          .get();

      updateProductsFromQuerySnapshot(snapshot);
    } catch (e) {
      errorMessage = 'Failed to load products: ${e.toString()}';
      if (kDebugMode) print('Error loading products: $e');
      notifyListeners();
    }
  }

  void updateProductsFromQuerySnapshot(QuerySnapshot snapshot) {
    compostProducts = snapshot.docs.map((doc) {
      return CompostProduct.fromFirestore(doc);
    }).toList();

    applyFilters();
    errorMessage = null;
    isLoading = false;
    notifyListeners();
  }

  void updateProductsFromSnapshot(QuerySnapshot snapshot) {
    try {
      compostProducts = snapshot.docs.map((doc) {
        return CompostProduct.fromFirestore(doc);
      }).toList();

      applyFilters();
      errorMessage = null;
    } catch (e) {
      errorMessage = 'Failed to update products: ${e.toString()}';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _updateOrdersFromSnapshot(QuerySnapshot snapshot) {
    try {
      userOrders = snapshot.docs.map((doc) {
        return Order.fromFirestore(doc);
      }).toList();
    } catch (e) {
      errorMessage = 'Failed to update orders: ${e.toString()}';
    }
    notifyListeners();
  }

  // New method for creating an order
  Future<void> createOrder({
    required String productId,
    required String productName,
    required String sellerId,
    required String sellerName,
    required double quantity,
    required double pricePerKg,
    required double totalPrice,
    String? message,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      // Create order document
      final orderData = {
        'productId': productId,
        'productName': productName,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'buyerId': user.uid,
        'buyerName': user.displayName ?? 'Anonymous Buyer',
        'buyerEmail': user.email,
        'quantity': quantity,
        'pricePerKg': pricePerKg,
        'totalPrice': totalPrice,
        'message': message ?? '',
        'status': 'pending', // pending, confirmed, shipped, delivered, cancelled
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('orders').add(orderData);

      // Update product availability
      await _updateProductQuantity(productId, quantity);

      errorMessage = null;
    } catch (e) {
      errorMessage = 'Failed to create order: $e';
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updateProductQuantity(String productId, double quantity) async {
    try {
      final productRef = FirebaseFirestore.instance.collection('products').doc(productId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(productRef);
        final currentQuantity = (snapshot.data()?['availableQuantity'] ?? 0).toDouble();
        final newQuantity = currentQuantity - quantity;

        transaction.update(productRef, {
          'availableQuantity': newQuantity > 0 ? newQuantity : 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      errorMessage = 'Failed to update product quantity: $e';
      rethrow;
    }
  }

  Future<void> addProduct({
    required String name,
    required String type,
    required String description,
    required double pricePerKg,
    required int availableQuantity,
    String? imageUrl,
    String? contactPhone,
    String? contactEmail,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final sellerEmail = contactEmail ?? user.email ?? '';

      final productData = {
        'name': name,
        'type': type,
        'description': description,
        'pricePerKg': pricePerKg,
        'availableQuantity': availableQuantity,
        'imageUrl': imageUrl ?? '',
        'sellerId': user.uid,
        'sellerName': user.displayName ?? 'Anonymous Seller',
        'sellerEmail': sellerEmail,
        'sellerPhone': contactPhone ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('products').add(productData);
      errorMessage = null;
    } catch (e) {
      errorMessage = 'Failed to add product: $e';
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setFilter(String filter) {
    selectedFilter = filter;
    applyFilters();
  }

  void setPriceRange(RangeValues range) {
    priceRange = range;
    applyFilters();
  }

  void setAvailabilityFilter(bool available) {
    availabilityFilter = available;
    applyFilters();
  }

  void applyFilters({
    String? typeFilter,
    RangeValues? priceRange,
    bool? availability,
  }) {
    filteredProducts = compostProducts.where((product) {
      final typeMatch = typeFilter == null || typeFilter == 'All' || product.type == typeFilter;
      final priceMatch = (priceRange ?? this.priceRange).start <= product.pricePerKg &&
          product.pricePerKg <= (priceRange ?? this.priceRange).end;
      final availabilityMatch = (availability ?? availabilityFilter)
          ? product.availableQuantity > 0
          : true;

      return typeMatch && priceMatch && availabilityMatch;
    }).toList();

    notifyListeners();
  }

  List<String> get productTypes {
    final types = compostProducts.map((p) => p.type).toSet().toList();
    return ['All', ...types];
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }
}

class CompostProduct {
  final String id;
  final String name;
  final String type;
  final double pricePerKg;
  final double availableQuantity;
  final String description;
  final String imageUrl;
  final String sellerName;
  final String sellerEmail;
  final String sellerPhone;
  final String sellerId;
  final DateTime createdAt;

  CompostProduct({
    required this.id,
    required this.name,
    required this.type,
    required this.pricePerKg,
    required this.availableQuantity,
    required this.description,
    required this.imageUrl,
    required this.sellerName,
    required this.sellerEmail,
    required this.sellerPhone,
    required this.sellerId,
    required this.createdAt,
  });

  factory CompostProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CompostProduct(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Product',
      type: data['type'] ?? 'General',
      pricePerKg: (data['pricePerKg'] ?? 0).toDouble(),
      availableQuantity: (data['availableQuantity'] ?? 0).toDouble(),
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      sellerName: data['sellerName'] ?? 'Unknown Seller',
      sellerEmail: data['sellerEmail'] ?? '',
      sellerPhone: data['sellerPhone'] ?? '',
      sellerId: data['sellerId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'pricePerKg': pricePerKg,
      'availableQuantity': availableQuantity,
      'description': description,
      'imageUrl': imageUrl,
      'sellerName': sellerName,
      'sellerEmail': sellerEmail,
      'sellerPhone': sellerPhone,
      'sellerId': sellerId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

// New Order class to handle purchase orders
class Order {
  final String id;
  final String productId;
  final String productName;
  final String sellerId;
  final String sellerName;
  final String buyerId;
  final String buyerName;
  final String? buyerEmail;
  final double quantity;
  final double pricePerKg;
  final double totalPrice;
  final String? message;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Order({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sellerId,
    required this.sellerName,
    required this.buyerId,
    required this.buyerName,
    this.buyerEmail,
    required this.quantity,
    required this.pricePerKg,
    required this.totalPrice,
    this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Order(
      id: doc.id,
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      buyerId: data['buyerId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      buyerEmail: data['buyerEmail'],
      quantity: (data['quantity'] ?? 0).toDouble(),
      pricePerKg: (data['pricePerKg'] ?? 0).toDouble(),
      totalPrice: (data['totalPrice'] ?? 0).toDouble(),
      message: data['message'],
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'buyerEmail': buyerEmail,
      'quantity': quantity,
      'pricePerKg': pricePerKg,
      'totalPrice': totalPrice,
      'message': message,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}