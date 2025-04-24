// waste_collection_service.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';


class WasteCollectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get nearby waste collection companies based on user location and waste type
  Future<List<Map<String, dynamic>>> getNearbyCompanies({
    required String userId,
    required String wasteType,
    required double latitude,
    required double longitude,
    required double radiusInKm,
  }) async {
    try {
      // Get user data
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userAddress = userDoc.data()?['address'] ?? '';

      // Query companies that handle this waste type within radius
      final querySnapshot = await _firestore
          .collection('companies')
          .where('services', arrayContains: wasteType)
          .where('isActive', isEqualTo: true)
          .get();

      // Filter by distance (simplified for example - in production use geohashes)
      final nearbyCompanies = querySnapshot.docs.map((doc) {
        final data = doc.data();
        final companyLat = data['latitude'] ?? 0.0;
        final companyLon = data['longitude'] ?? 0.0;
        final distance = _calculateDistance(
            latitude, longitude, companyLat, companyLon);

        return {
          'id': doc.id,
          ...data,
          'distance': distance,
          'userAddress': userAddress,
        };
      }).where((company) => company['distance'] <= radiusInKm)
          .toList();

      // Sort by distance and rating
      nearbyCompanies.sort((a, b) {
        final distCompare = a['distance'].compareTo(b['distance']);
        if (distCompare != 0) return distCompare;
        return (b['rating'] ?? 0).compareTo(a['rating'] ?? 0);
      });

      return nearbyCompanies;
    } catch (e) {
      print('Error getting nearby companies: $e');
      return [];
    }
  }

  // Schedule a pickup with a company
  Future<bool> schedulePickup({
    required String userId,
    required String companyId,
    required String wasteType,
    required double amountKg,
    required DateTime preferredDate,
    required String userNotes,
  }) async {
    try {
      // Get user data
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      // Create pickup request
      await _firestore.collection('pickupRequests').add({
        'userId': userId,
        'companyId': companyId,
        'wasteType': wasteType,
        'amountKg': amountKg,
        'preferredDate': preferredDate,
        'actualDate': null,
        'userNotes': userNotes,
        'status': 'pending',
        'userName': userData['name'] ?? '',
        'userPhone': userData['phone'] ?? '',
        'userAddress': userData['address'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Notify company (in a real app, you might send a push notification)
      await _firestore.collection('companies').doc(companyId).update({
        'pendingRequests': FieldValue.increment(1),
      });

      return true;
    } catch (e) {
      print('Error scheduling pickup: $e');
      return false;
    }
  }

  // Predict optimal pickup schedule based on user's waste generation patterns
  Future<Map<String, dynamic>> predictOptimalSchedule(String userId) async {
    try {
      // Get user's historical waste data
      final history = await _firestore
          .collection('users')
          .doc(userId)
          .collection('wasteHistory')
          .orderBy('date', descending: true)
          .limit(30)
          .get();

      if (history.docs.isEmpty) {
        return {
          'suggestion': 'No enough data yet. Please use the app for a few weeks.',
          'nextPickup': null,
          'frequency': null,
        };
      }

      // Simple analysis (in production, use proper ML models)
      final compostableCount = history.docs
          .where((doc) => doc['category'] == 'Compostable')
          .length;
      final recyclableCount = history.docs
          .where((doc) => doc['category'] == 'Recyclable')
          .length;
      final landfillCount = history.docs
          .where((doc) => doc['category'] == 'Landfill')
          .length;

      final total = compostableCount + recyclableCount + landfillCount;
      final compostablePercent = compostableCount / total;
      final recyclablePercent = recyclableCount / total;

      String suggestion;
      DateTime? nextPickup;
      String? frequency;

      if (compostablePercent > 0.6) {
        suggestion = 'High compostable waste. Consider weekly organic pickup.';
        frequency = 'weekly';
        nextPickup = DateTime.now().add(const Duration(days: 7));
      } else if (recyclablePercent > 0.5) {
        suggestion = 'Mostly recyclables. Bi-weekly pickup recommended.';
        frequency = 'bi-weekly';
        nextPickup = DateTime.now().add(const Duration(days: 14));
      } else {
        suggestion = 'Mixed waste. Monthly pickup would be sufficient.';
        frequency = 'monthly';
        nextPickup = DateTime.now().add(const Duration(days: 30));
      }

      return {
        'suggestion': suggestion,
        'nextPickup': nextPickup,
        'frequency': frequency,
        'stats': {
          'compostable': compostablePercent,
          'recyclable': recyclablePercent,
          'landfill': landfillCount / total,
        },
      };
    } catch (e) {
      print('Error predicting schedule: $e');
      return {
        'error': 'Failed to generate prediction',
      };
    }
  }

  // Helper function to calculate distance between coordinates
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }
}