// transactions_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initiatePayment(String userId, double amount, int pointsUsed) async {
    await _firestore.collection('users').doc(userId).collection('transactions').add({
      'amount': amount,
      'pointsUsed': pointsUsed,
      'date': FieldValue.serverTimestamp(),
      'status': 'initiated',
      'type': 'purchase',
    });
  }

  Future<void> updatePaymentStatus(String userId, String transactionId, String status) async {
    await _firestore.collection('users').doc(userId).collection('transactions')
        .doc(transactionId).update({'status': status});
  }
}