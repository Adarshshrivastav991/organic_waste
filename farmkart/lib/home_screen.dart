import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'auth_service.dart';
import 'marketplace_screen.dart';
import 'nearby_market_screen.dart';
import 'profile_screen.dart';
import 'classify_screen.dart';
import 'upload_video_screen.dart';

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

  Widget _buildVideoFeed() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Educational Videos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UploadVideoScreen(),
                    ),
                  );
                },
                tooltip: 'Upload Video',
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('videos')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }

              if (snapshot.data!.docs.isEmpty) {
                return Center(child: Text('No videos available yet'));
              }

              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var videoData = snapshot.data!.docs[index];
                  return VideoCard(
                    title: videoData['title'],
                    description: videoData['description'],
                    videoUrl: videoData['videoUrl'],
                    username: videoData['username'],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    switch (_selectedIndex) {
      case 0:
        bodyContent = _buildVideoFeed();
        break;
      case 1:
        bodyContent = const WasteClassificationScreen();
        break;
      case 2:
        bodyContent = const MarketplaceScreen();
        break;
      case 3:
        bodyContent = const NearByMarketScreen();
        break;
      default:
        bodyContent = _buildVideoFeed();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FarmKart'),
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
        ],
      ),
      body: bodyContent,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library),
            label: 'Videos',
          ),
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

class VideoCard extends StatefulWidget {
  final String title;
  final String description;
  final String videoUrl;
  final String username;

  const VideoCard({
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.username,
    Key? key,
  }) : super(key: key);

  @override
  _VideoCardState createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  Future<void> _initializeVideoPlayer() async {
    _videoPlayerController = VideoPlayerController.network(widget.videoUrl);
    await _videoPlayerController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: false,
      looping: false,
      showControls: true,
      placeholder: Container(
        color: Colors.grey,
      ),
    );

    setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              widget.title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Posted by: ${widget.username}',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController)
                : Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(widget.description),
          ),
        ],
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