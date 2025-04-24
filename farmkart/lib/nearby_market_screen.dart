import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' show cos, sqrt, asin;

class NearByMarketScreen extends StatefulWidget {
  const NearByMarketScreen({Key? key}) : super(key: key);

  @override
  State<NearByMarketScreen> createState() => _NearByMarketScreenState();
}

class _NearByMarketScreenState extends State<NearByMarketScreen> {
  Position? _currentPosition;
  List<Map<String, dynamic>> _nearbyProducts = [];
  final double searchRadiusKm = 10;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _fetchLocationAndProducts();
  }

  // In NearByMarketScreen's _fetchLocationAndProducts
  Future<void> _fetchLocationAndProducts() async {
    try {
      final hasPermission = await _handlePermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission required'))
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      ).timeout(const Duration(seconds: 10));

      // Rest of the code...
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'))
      );
    }
  }

  Set<Marker> _createMarkers(List<Map<String, dynamic>> products) {
    return products.map((product) {
      return Marker(
        markerId: MarkerId(product['id']),
        position: LatLng(product['latitude'], product['longitude']),
        infoWindow: InfoWindow(
          title: product['name'] ?? 'Compost',
          snippet: '${product['pricePerKg']} ₹/kg',
        ),
      );
    }).toSet();
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
      appBar: AppBar(title: const Text("Nearby Compost Stores")),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        onMapCreated: (controller) => _mapController = controller,
        initialCameraPosition: CameraPosition(
          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          zoom: 13,
        ),
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
