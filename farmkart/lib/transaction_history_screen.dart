// transaction_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TransactionHistoryScreen extends StatelessWidget {
  final User user;

  const TransactionHistoryScreen({Key? key, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('transactions')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final transactions = snapshot.data!.docs;

          if (transactions.isEmpty) {
            return const Center(child: Text('No transactions yet'));
          }

          return ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index].data() as Map<String, dynamic>;
              final date = (transaction['date'] as Timestamp).toDate();

              return Card(
                child: ListTile(
                  leading: Icon(
                    transaction['type'] == 'purchase'
                        ? Icons.shopping_cart
                        : Icons.card_giftcard,
                    color: Colors.green,
                  ),
                  title: Text(
                    transaction['type'] == 'purchase'
                        ? 'Purchase: \$${transaction['amount']}'
                        : 'Reward Claim: ${transaction['points']} pts',
                  ),
                  subtitle: Text(DateFormat('MMM d, y - h:mm a').format(date)),
                  trailing: Text(
                    transaction['status'],
                    style: TextStyle(
                      color: transaction['status'] == 'completed'
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}