import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'marketplace_screen.dart';
import 'nearby_market_screen.dart';
import 'profile_screen.dart';
import 'classify_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({Key? key, required this.user}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _userPoints = 0;
  final RewardsSystem _rewardsSystem = RewardsSystem();
  final TransactionsService _transactionsService = TransactionsService();

  @override
  void initState() {
    super.initState();
    _loadUserPoints();
  }

  Future<void> _loadUserPoints() async {
    final points = await _rewardsSystem.getPoints(widget.user.uid);
    setState(() {
      _userPoints = points;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildPointsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            '$_userPoints pts',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _showRewardsDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Claim Your Rewards'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose how to use your points:'),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('100 pts = \$1 discount'),
                onTap: () => _claimReward(100, 1.0),
              ),
              ListTile(
                leading: const Icon(Icons.local_offer),
                title: const Text('250 pts = \$3 discount'),
                onTap: () => _claimReward(250, 3.0),
              ),
              ListTile(
                leading: const Icon(Icons.attach_money),
                title: const Text('500 pts = \$7 discount'),
                onTap: () => _claimReward(500, 7.0),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _claimReward(int points, double value) async {
    if (_userPoints >= points) {
      try {
        await _rewardsSystem.claimReward(widget.user.uid, points);
        await _transactionsService.initiatePayment(widget.user.uid, value, points);
        _loadUserPoints();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully claimed reward of \$$value!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error claiming reward: ${e.toString()}')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough points for this reward')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    switch (_selectedIndex) {
      case 0:
        bodyContent = const WasteClassificationScreen();
        break;
      case 1:
        bodyContent = const MarketplaceScreen();
        break;
      case 2:
        bodyContent = const NearByMarketScreen();
        break;
      default:
        bodyContent = const WasteClassificationScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoSort AI'),
        actions: [
          _buildPointsBadge(),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(user: widget.user),
                ),
              );
            },
          ),
          // Removed the logout button from here
        ],
      ),
      body: bodyContent,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Classify',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Marketplace',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'NearBy Store',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

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

    await _firestore.collection('users').doc(userId).collection('transactions').add({
      'type': 'redemption',
      'points': pointsToClaim,
      'date': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }
}

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