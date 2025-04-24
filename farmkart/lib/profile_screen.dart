import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final User user;

  const ProfileScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  File? _profileImage;
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _scanHistory = [];
  List<Map<String, dynamic>> _transactionHistory = [];
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadScanHistory();
    _loadTransactionHistory();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() => _isLoading = true);
      final doc = await _firestore.collection('users').doc(widget.user.uid).get();
      if (doc.exists) {
        setState(() => _userData = doc.data()!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load user data: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadScanHistory() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(widget.user.uid)
          .collection('classifications')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      setState(() {
        _scanHistory = snapshot.docs.map((doc) => doc.data()).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load scan history: ${e.toString()}')),
      );
    }
  }

  Future<void> _loadTransactionHistory() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(widget.user.uid)
          .collection('transactions')
          .orderBy('date', descending: true)
          .limit(20)
          .get();

      setState(() {
        _transactionHistory = snapshot.docs.map((doc) => doc.data()).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load transactions: ${e.toString()}')),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _profileImage = File(image.path);
        });
        // TODO: Upload image to Firebase Storage and update user profile
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      setState(() => _isLoading = true);
      await Provider.of<AuthService>(context, listen: false).signOut();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[200],
              backgroundImage: _profileImage != null
                  ? FileImage(_profileImage!)
                  : (widget.user.photoURL != null
                  ? CachedNetworkImageProvider(widget.user.photoURL!)
                  : null),
              child: widget.user.photoURL == null && _profileImage == null
                  ? const Icon(Icons.person, size: 50, color: Colors.grey)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  onPressed: _pickImage,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          widget.user.displayName ?? 'EcoSort User',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          widget.user.email ?? '',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStatsCard(String title, String value) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanHistoryItem(Map<String, dynamic> scan) {
    final category = scan['category'] ?? 'Unknown';
    final isCompostable = scan['is_compostable'] == true;
    final color = isCompostable ? Colors.green :
    (category == 'Recyclable' ? Colors.blue :
    (category == 'Hazardous' ? Colors.deepOrange : Colors.red));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(
          isCompostable ? Icons.eco :
          (category == 'Recyclable' ? Icons.recycling :
          (category == 'Hazardous' ? Icons.warning : Icons.delete)),
          color: color,
        ),
        title: Text(category.toUpperCase()),
        subtitle: Text(
          DateFormat('MMM d, y - h:mm a').format(
              (scan['timestamp'] as Timestamp).toDate()),
        ),
        trailing: Text(
          scan['confidence'] ?? 'Unknown',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        onTap: () {
          // Show detailed scan info
          _showScanDetails(scan);
        },
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final isRedemption = transaction['type'] == 'redemption';
    final date = (transaction['date'] as Timestamp).toDate();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(
          isRedemption ? Icons.card_giftcard : Icons.payment,
          color: isRedemption ? Colors.amber : Colors.green,
        ),
        title: Text(
          isRedemption
              ? 'Redeemed ${transaction['points']} points'
              : 'Purchase: \$${transaction['amount']?.toStringAsFixed(2) ?? '0.00'}',
        ),
        subtitle: Text(DateFormat('MMM d, y - h:mm a').format(date)),
        trailing: Chip(
          label: Text(
            transaction['status'] ?? 'pending',
            style: TextStyle(
              color: transaction['status'] == 'completed'
                  ? Colors.green
                  : Colors.orange,
            ),
          ),
          backgroundColor: Colors.grey[200],
        ),
      ),
    );
  }

  void _showScanDetails(Map<String, dynamic> scan) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(scan['category']?.toString().toUpperCase() ?? 'Scan Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (scan['imageUrl'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: CachedNetworkImage(
                      imageUrl: scan['imageUrl'],
                      placeholder: (context, url) => const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    ),
                  ),
                Text(
                  'Confidence: ${scan['confidence'] ?? 'Unknown'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Analysis:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(scan['explanation'] ?? 'No analysis available'),
                const SizedBox(height: 16),
                Text(
                  'Disposal Instructions:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(scan['instructions'] ?? 'No instructions available'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildProfileHeader(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatsCard('Scans', _userData?['scanCount']?.toString() ?? '0'),
              _buildStatsCard('Points', _userData?['points']?.toString() ?? '0'),
              _buildStatsCard('Level', _userData?['level']?.toString() ?? '1'),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailItem('Full Name', widget.user.displayName ?? 'Not provided'),
                  _buildDetailItem('Email', widget.user.email ?? 'Not provided'),
                  _buildDetailItem('Phone', _userData?['phone'] ?? 'Not provided'),
                  _buildDetailItem(
                      'Member Since',
                      widget.user.metadata.creationTime?.toLocal().toString().split(' ')[0] ?? 'Unknown'
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Divider(height: 20),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_scanHistory.isEmpty) {
      return const Center(child: Text('No scan history yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _scanHistory.length,
      itemBuilder: (context, index) {
        return _buildScanHistoryItem(_scanHistory[index]);
      },
    );
  }

  Widget _buildRewardsTab() {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Your Rewards',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  '${_userData?['points'] ?? 0} Points',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Redeem your points for discounts and rewards',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to rewards redemption screen
                  },
                  child: const Text('Redeem Points'),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent Transactions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: _transactionHistory.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _transactionHistory.length,
            itemBuilder: (context, index) {
              return _buildTransactionItem(_transactionHistory[index]);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Profile'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.person), text: 'Profile'),
              Tab(icon: Icon(Icons.history), text: 'History'),
              Tab(icon: Icon(Icons.card_giftcard), text: 'Rewards'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
          children: [
            _buildProfileTab(),
            _buildHistoryTab(),
            _buildRewardsTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _signOut,
          backgroundColor: Colors.red,
          child: const Icon(Icons.logout, color: Colors.white),
        ),
      ),
    );
  }
}