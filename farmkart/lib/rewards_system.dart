// rewards_system.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RewardsSystem {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addPoints(String userId, int points) async {
    await _firestore.collection('users').doc(userId).update({
      'points': FieldValue.increment(points),
      'lastEarned': FieldValue.serverTimestamp(),
    });
  }

  Future<int> getPoints(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data()?['points'] ?? 0;
  }

  Future<void> claimReward(String userId, int pointsToClaim) async {
    await _firestore.collection('users').doc(userId).update({
      'points': FieldValue.increment(-pointsToClaim),
      'lastClaimed': FieldValue.serverTimestamp(),
    });

    // Add to transaction history
    await _firestore.collection('users').doc(userId).collection('transactions').add({
      'type': 'redemption',
      'points': pointsToClaim,
      'date': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }
}