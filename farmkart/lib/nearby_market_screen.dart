import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:math' show cos, sqrt, asin;

import 'marketplace_provider.dart';
import 'product_grid.dart';

class NearByMarketScreen extends StatefulWidget {
  const NearByMarketScreen({Key? key}) : super(key: key);

  @override
  State<NearByMarketScreen> createState() => _NearByMarketScreenState();
}

class _NearByMarketScreenState extends State<NearByMarketScreen> {
  Position? _currentPosition;
  List<Map<String, dynamic>> _nearbyProducts = [];
  final double searchRadiusKm = 10;

  @override
  void initState() {
    super.initState();
    _fetchLocationAndProducts();
  }

  Future<void> _fetchLocationAndProducts() async {
    final hasPermission = await _handlePermission();
    if (!hasPermission) return;

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = position;
    });

    final snapshot = await FirebaseFirestore.instance.collection('products').get();

    final filtered = snapshot.docs.where((doc) {
      final data = doc.data();
      if (!data.containsKey('location')) return false;

      final geoPoint = data['location'] as GeoPoint;
      final distance = _calculateDistance(
        position.latitude,
        position.longitude,
        geoPoint.latitude,
        geoPoint.longitude,
      );
      return distance <= searchRadiusKm;
    }).map((doc) {
      return {
        'id': doc.id,
        ...doc.data(),
      };
    }).toList();

    setState(() {
      _nearbyProducts = filtered;
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
