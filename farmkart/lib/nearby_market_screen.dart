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

  Future<void> _fetchLocationAndProducts() async {
    final hasPermission = await _handlePermission();
    if (!hasPermission) return;

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
          'id': doc.id,
          ...data,
          'distance': distance,
        };
      }
      return null;
    }).where((e) => e != null).toList();

    filtered.sort((a, b) => a!['distance'].compareTo(b!['distance']));

    setState(() {
      _nearbyProducts = filtered.cast<Map<String, dynamic>>();
      _markers = _createMarkers(_nearbyProducts);
    });
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
