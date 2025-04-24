import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' show cos, sqrt, asin;

import 'compost_product_model.dart'; // Your model file
import 'product_grid.dart'; // Accepts List<CompostProduct>

class NearByMarketScreen extends StatefulWidget {
  const NearByMarketScreen({Key? key}) : super(key: key);

  @override
  State<NearByMarketScreen> createState() => _NearByMarketScreenState();
}

class _NearByMarketScreenState extends State<NearByMarketScreen> {
  Position? _currentPosition;
  List<CompostProduct> _nearbyProducts = [];
  final double searchRadiusKm = 10;

  @override
  void initState() {
    super.initState();
    _fetchLocationAndProducts();
  }

  Future<void> _fetchLocationAndProducts() async {
    final hasPermission = await _handlePermission();
    if (!hasPermission) return;

    final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = position;
    });

    final snapshot = await FirebaseFirestore.instance.collection('products').get();

    final filtered = snapshot.docs.map((doc) {
      final data = doc.data();
      final lat = data['latitude'];
      final lon = data['longitude'];

      if (lat == null || lon == null) return null;

      final distance = _calculateDistance(
        position.latitude,
        position.longitude,
        lat,
        lon,
      );

      if (distance <= searchRadiusKm) {
        return {
          'product': CompostProduct.fromMap(doc.id, data),
          'distance': distance,
        };
      } else {
        return null;
      }
    }).where((entry) => entry != null).toList();

    filtered.sort((a, b) =>
        (a!['distance'] as double).compareTo(b!['distance'] as double));

    setState(() {
      _nearbyProducts = filtered.map((e) => e!['product'] as CompostProduct).toList();
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.0174533;
    final a = 0.5 - cos((lat2 - lat1) * p)/2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<bool> _handlePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nearby Compost Products")),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : _nearbyProducts.isEmpty
          ? const Center(child: Text("No nearby products found."))
          : ProductGrid(products: _nearbyProducts),
    );
  }
}
