import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  File? _profileImage;
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  bool _isCompany = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            _userData = doc.data();
            _isCompany = _userData?['userType'] == 'company';
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load user data: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      await _auth.signOut();
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildProfileHeader(User user) {
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[200],
              backgroundImage: _profileImage != null
                  ? FileImage(_profileImage!)
                  : (user.photoURL != null
                  ? CachedNetworkImageProvider(user.photoURL!)
                  : null),
              child: user.photoURL == null && _profileImage == null
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
          _userData?['name'] ?? 'User Name',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          user.email ?? '',
          style: const TextStyle(color: Colors.grey),
        ),
        if (_isCompany && _userData?['companyName'] != null) ...[
          const SizedBox(height: 8),
          Text(
            _userData!['companyName'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStatsCard(String title, String value) {
    return Card(
      elevation: 2,
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

  Widget _buildMenuOption(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.green),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildCompanyInfo() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Company Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Address', _userData?['companyAddress'] ?? 'Not provided'),
            const Divider(),
            _buildInfoRow('Registration', _userData?['registrationNumber'] ?? 'Not provided'),
            const Divider(),
            _buildInfoRow('Status', _userData?['verified'] == true ? 'Verified' : 'Pending Verification'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view profile')),
      );
    }

    if (_isLoading || _userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCompany ? 'Company Profile' : 'My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProfileHeader(user),

            // Company-specific information
            if (_isCompany) ...[
              _buildCompanyInfo(),
              const SizedBox(height: 16),
            ],

            // User stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatsCard('Orders', '12'),
                _buildStatsCard('Reviews', '4.8'),
                _buildStatsCard('Points', '150'),
              ],
            ),
            const SizedBox(height: 24),

            // Menu options
            Card(
              elevation: 2,
              child: Column(
                children: [
                  _buildMenuOption(Icons.shopping_bag, 'My Orders', () {
                    Navigator.pushNamed(context, '/orders');
                  }),
                  const Divider(height: 1),
                  _buildMenuOption(Icons.favorite, 'Wishlist', () {
                    Navigator.pushNamed(context, '/wishlist');
                  }),
                  if (!_isCompany) ...[
                    const Divider(height: 1),
                    _buildMenuOption(Icons.location_on, 'Addresses', () {
                      Navigator.pushNamed(context, '/addresses');
                    }),
                  ],
                  const Divider(height: 1),
                  _buildMenuOption(Icons.credit_card, 'Payment Methods', () {
                    Navigator.pushNamed(context, '/payments');
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // More options
            Card(
              elevation: 2,
              child: Column(
                children: [
                  _buildMenuOption(Icons.help, 'Help Center', () {
                    Navigator.pushNamed(context, '/help');
                  }),
                  const Divider(height: 1),
                  _buildMenuOption(Icons.info, 'About EcoSort AI', () {
                    Navigator.pushNamed(context, '/about');
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Logout button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.red, backgroundColor: Colors.red[100],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isLoading ? null : _signOut,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Logout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}