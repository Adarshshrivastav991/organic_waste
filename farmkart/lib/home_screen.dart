import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'marketplace_screen.dart';
import 'marketplace_screen.dart' show MarketplaceScreen;
import 'schedule_pickup_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({Key? key, required this.user}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _image;
  final picker = ImagePicker();
  bool _isLoading = false;
  Map<String, dynamic>? _productAnalysis;
  List<Map<String, dynamic>> _history = [];
  final String _geminiApiKey = 'AIzaSyCu_GZZiPNpvkt6b6zDlSQn3WtXqWY8Ejg';
  int _selectedIndex = 0;
  File? _profileImage;

  // Profile section methods
  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _profileImage = File(image.path);
        });
        // TODO: Upload profile image to Firebase Storage and update user profile
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
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
                  onPressed: _pickProfileImage,
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

  Widget _buildProfileStatsCard(String title, String value) {
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

  Widget _buildProfileMenuOption(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.green),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildProfileContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildProfileHeader(),

          // User stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildProfileStatsCard('Scans', _history.length.toString()),
              _buildProfileStatsCard('Composted',
                  _history.where((item) => item['isCompostable'] == true).length.toString()),
              _buildProfileStatsCard('Points', '150'),
            ],
          ),
          const SizedBox(height: 24),

          // Menu options
          Card(
            elevation: 2,
            child: Column(
              children: [
                _buildProfileMenuOption(Icons.history, 'Scan History', () {
                  // Navigate to full history screen
                }),
                const Divider(height: 1),
                _buildProfileMenuOption(Icons.eco, 'Compost Stats', () {
                  // Navigate to compost stats
                }),
                const Divider(height: 1),
                _buildProfileMenuOption(Icons.settings, 'Settings', () {
                  // Navigate to settings
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
                _buildProfileMenuOption(Icons.help, 'Help Center', () {
                  // Navigate to help
                }),
                const Divider(height: 1),
                _buildProfileMenuOption(Icons.info, 'About EcoSort', () {
                  // Navigate to about
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
              onPressed: () async {
                await Provider.of<AuthService>(context, listen: false).signOut();
              },
              child: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('product_analyses')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      setState(() {
        _history = snapshot.docs.map((doc) => doc.data()).toList();
      });
    } catch (e) {
      print('Error loading history: $e');
    }
  }

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _productAnalysis = null;
      });
    }
  }

  Future<Map<String, dynamic>> _callGeminiAPI(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      const prompt = """
      Analyze this compost product image and provide a JSON response with these fields:
      - name: string (product name)
      - type: string (Vermicompost/Organic Compost/Manure/Leaf Compost/Bokashi/Other)
      - qualityRating: number (1-5)
      - moistureContent: string (Low/Medium/High)
      - nutrientAnalysis: {
        nitrogen: string (Low/Medium/High),
        phosphorus: string (Low/Medium/High),
        potassium: string (Low/Medium/High)
      }
      - organicMatter: string (Low/Medium/High)
      - phLevel: number (pH value)
      - contaminants: string (description of any contaminants)
      - recommendedUse: string (best use cases)
      - priceEstimate: number (estimated price per kg in local currency)
      - additionalNotes: string (any other observations)

      Guidelines:
      - Be thorough in your analysis
      - Provide specific details about compost quality
      - Estimate price based on quality and local market rates
      - Identify any potential issues or contaminants

      Return ONLY the JSON object, nothing else.
      """;

      final url = Uri.parse(" https://generativelanguage.googleapis.com/v1beta/models/gemini-pro-vision:generateContent?key=$_geminiApiKey ");

      final headers = {'Content-Type': 'application/json'};

      final body = {
        "contents": [
          {
            "parts": [
              {"text": prompt},
              {
                "inlineData": {
                  "mimeType": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.1,
          "topP": 0.7,
          "topK": 20,
          "maxOutputTokens": 1000
        }
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final text = responseData['candidates'][0]['content']['parts'][0]['text'];
        return jsonDecode(text);
      } else {
        throw Exception('API request failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to call Gemini API: $e');
    }
  }

  Future<void> _analyzeProduct() async {
    if (_image == null) return;

    setState(() => _isLoading = true);

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('product_images/${widget.user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(_image!);
      final imageUrl = await storageRef.getDownloadURL();

      final analysis = await _callGeminiAPI(_image!);
      print('API Response: $analysis');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('product_analyses')
          .add({
        'imageUrl': imageUrl,
        ...analysis,
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() {
        _productAnalysis = analysis;
        _isLoading = false;
      });

      _loadHistory();
    } catch (e) {
      print('Error: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildAnalysisResult() {
    if (_productAnalysis == null) return Container();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.green.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Product Analysis',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          _buildAnalysisRow('Name', _productAnalysis!['name'] ?? 'Unknown'),
          _buildAnalysisRow('Type', _productAnalysis!['type'] ?? 'Unknown'),
          _buildAnalysisRow('Quality Rating',
              '${_productAnalysis!['qualityRating']?.toString() ?? 'N/A'}/5'),
          _buildAnalysisRow('Moisture', _productAnalysis!['moistureContent'] ?? 'Unknown'),
          _buildAnalysisRow('Organic Matter', _productAnalysis!['organicMatter'] ?? 'Unknown'),
          _buildAnalysisRow('pH Level', _productAnalysis!['phLevel']?.toString() ?? 'Unknown'),
          _buildAnalysisRow('Price Estimate',
              '${_productAnalysis!['priceEstimate']?.toStringAsFixed(2) ?? 'N/A'} per kg'),

          if (_productAnalysis!['nutrientAnalysis'] != null) ...[
            const SizedBox(height: 15),
            const Text(
              'Nutrient Analysis:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            _buildAnalysisRow('  Nitrogen', _productAnalysis!['nutrientAnalysis']['nitrogen']),
            _buildAnalysisRow('  Phosphorus', _productAnalysis!['nutrientAnalysis']['phosphorus']),
            _buildAnalysisRow('  Potassium', _productAnalysis!['nutrientAnalysis']['potassium']),
          ],

          if (_productAnalysis!['recommendedUse'] != null) ...[
            const SizedBox(height: 15),
            const Text(
              'Recommended Use:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(_productAnalysis!['recommendedUse']),
          ],

          if (_productAnalysis!['additionalNotes'] != null) ...[
            const SizedBox(height: 15),
            const Text(
              'Additional Notes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(_productAnalysis!['additionalNotes']),
          ],

          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              // Navigate to product upload screen with analysis data
            },
            child: const Text('UPLOAD TO MARKETPLACE'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildClassificationContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Upload photo of compost product:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
                onPressed: () => _getImage(ImageSource.camera),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
                onPressed: () => _getImage(ImageSource.gallery),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_image != null) ...[
            Container(
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.file(_image!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _analyzeProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                'ANALYZE PRODUCT',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          if (_productAnalysis != null) ...[
            const SizedBox(height: 30),
            _buildAnalysisResult(),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 30),
            const Text(
              'RECENT ANALYSES',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ..._history.map((item) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item['imageUrl'] != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item['imageUrl'],
                            width: double.infinity,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        item['name'] ?? 'Unknown Product',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Type: ${item['type'] ?? 'Unknown'}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        'Quality: ${item['qualityRating']?.toString() ?? 'N/A'}/5',
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        'Price Estimate: ${item['priceEstimate']?.toStringAsFixed(2) ?? 'N/A'} per kg',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Compost Analyzer' : 'My Profile'),
      ),
      body: _selectedIndex == 0
          ? _buildClassificationContent()
          : _selectedIndex == 1
          ? const MarketplaceScreen()
          : _buildProfileContent(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.eco),
            label: 'Analyze',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Marketplace',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}