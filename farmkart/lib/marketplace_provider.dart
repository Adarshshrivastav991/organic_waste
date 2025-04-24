import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MarketplaceProvider extends ChangeNotifier {
  List<CompostProduct> compostProducts = [];
  List<CompostProduct> filteredProducts = [];
  bool isLoading = false;
  String? errorMessage;
  String selectedFilter = 'All';
  RangeValues priceRange = const RangeValues(0, 1000);
  bool availabilityFilter = true;

  MarketplaceProvider() {
    loadProducts();
    _setupProductsStream();
  }

  StreamSubscription<QuerySnapshot>? _productsSubscription;

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

  Future<void> addProduct(Map<String, dynamic> productData) async {
    try {
      isLoading = true;
      notifyListeners();

      if (!productData.containsKey('createdAt')) {
        productData['createdAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('products')
          .add(productData);

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
      // Type filter
      final typeMatch = typeFilter == null ||
          typeFilter == 'All' ||
          product.type == typeFilter;

      // Price filter
      final priceMatch = (priceRange ?? this.priceRange).start <= product.pricePerKg &&
          product.pricePerKg <= (priceRange ?? this.priceRange).end;

      // Availability filter (using availableQuantity > 0 as availability check)
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
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}