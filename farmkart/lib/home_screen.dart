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
import 'schedule_pickup_screen.dart';
import 'nearby_market_screen.dart';
import 'profile_screen.dart';

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
  String? _classificationResult;
  String? _confidence;
  String? _explanation;
  String? _disposalInstructions;
  List<Map<String, dynamic>> _history = [];
  final String _geminiApiKey = '866134594150';
  int _selectedIndex = 0;

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
          .collection('classifications')
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
        _classificationResult = null;
        _confidence = null;
        _explanation = null;
        _disposalInstructions = null;
      });
    }
  }

  Future<Map<String, dynamic>> _callGeminiAPI(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      const prompt = """
      Analyze the waste item image and provide a JSON response.
      Strictly follow the JSON format below. Do not include any other text.

      JSON Format:
      {
        "is_compostable": boolean,
        "confidence": string,
        "category": string,
        "explanation": string,
        "disposal": string,
        "misconceptions": string
      }

      Return ONLY the JSON object.
      """;

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey');

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
          "temperature": 0.2,
          "topP": 0.8,
          "topK": 40,
          "maxOutputTokens": 1500
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

        try {
          final jsonResponse = jsonDecode(text);
          if (jsonResponse.containsKey('is_compostable') &&
              jsonResponse.containsKey('category') &&
              jsonResponse.containsKey('confidence') &&
              jsonResponse.containsKey('explanation') &&
              jsonResponse.containsKey('disposal')) {
            return jsonResponse;
          } else {
            return _parsePlainTextResponse(text);
          }
        } catch (e) {
          return _parsePlainTextResponse(text);
        }
      } else {
        throw Exception('API request failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to call Gemini API: $e');
    }
  }

  Map<String, dynamic> _parsePlainTextResponse(String text) {
    final result = {
      'is_compostable': false,
      'confidence': 'Unknown',
      'category': 'Unknown',
      'explanation': 'Could not parse detailed explanation from response.',
      'disposal': 'Could not parse disposal instructions from response.',
      'misconceptions': 'Could not parse misconceptions.',
    };

    final lowerText = text.toLowerCase();

    if (lowerText.contains('compostable')) {
      result['is_compostable'] = (lowerText.contains('"is_compostable": true') ||
          lowerText.contains('is_compostable: true') ||
          lowerText.contains('category: compostable') ||
          lowerText.contains('result: compostable')) &&
          !lowerText.contains('not compostable');
      if (result['is_compostable'] == true) {
        result['category'] = 'Compostable';
      }
    } else if (lowerText.contains('recyclable')) {
      result['category'] = 'Recyclable';
    } else if (lowerText.contains('hazardous')) {
      result['category'] = 'Hazardous';
    } else {
      result['category'] = 'Landfill';
    }

    if (lowerText.contains('confidence: high') || lowerText.contains('"confidence": "high"')) {
      result['confidence'] = 'High';
    } else if (lowerText.contains('confidence: medium') || lowerText.contains('"confidence": "medium"')) {
      result['confidence'] = 'Medium';
    } else if (lowerText.contains('confidence: low') || lowerText.contains('"confidence": "low"')) {
      result['confidence'] = 'Low';
    } else if (result['is_compostable'] == true || result['category'] != 'Landfill') {
      result['confidence'] = 'Medium';
    } else {
      result['confidence'] = 'Low';
    }

    return result;
  }

  Future<void> _classifyImage() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _classificationResult = null;
      _confidence = null;
      _explanation = null;
      _disposalInstructions = null;
    });

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_images/${widget.user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(_image!);
      final imageUrl = await storageRef.getDownloadURL();

      final result = await _callGeminiAPI(_image!);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('classifications')
          .add({
        'imageUrl': imageUrl,
        'is_compostable': result['is_compostable'] ?? false,
        'category': result['category'] ?? 'Landfill',
        'confidence': result['confidence'] ?? 'Unknown',
        'explanation': result['explanation'] ?? 'No explanation provided.',
        'instructions': result['disposal'] ?? 'Disposal instructions not available.',
        'misconceptions': result['misconceptions'] ?? 'No common misconceptions noted.',
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() {
        final category = result['category'] ?? 'Unknown';
        _classificationResult = category.toUpperCase();
        if (result['is_compostable'] == true && _classificationResult != 'COMPOSTABLE') {
          _classificationResult = 'COMPOSTABLE ($category)';
        } else if (result['is_compostable'] == false && _classificationResult == 'COMPOSTABLE') {
          _classificationResult = 'NOT COMPOSTABLE ($category)';
        }
        _confidence = result['confidence'] ?? 'Unknown';
        _explanation = result['explanation'] ?? 'No detailed analysis provided.';
        _disposalInstructions = result['disposal'] ?? 'Disposal information not available.';
        _isLoading = false;
      });

      _loadHistory();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Classification failed: ${e.toString()}')),
      );
    }
  }

  Color _getResultColor() {
    if (_classificationResult == null) return Colors.grey;
    final resultLower = _classificationResult!.toLowerCase();
    if (resultLower.contains('compostable')) return Colors.green;
    if (resultLower.contains('recyclable')) return Colors.blue;
    if (resultLower.contains('hazardous')) return Colors.deepOrange;
    return Colors.red;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    switch (_selectedIndex) {
      case 0:
        bodyContent = _buildClassificationContent();
        break;
      case 1:
        bodyContent = const MarketplaceScreen();
        break;
      case 2:
        bodyContent = const NearByMarketScreen();
        break;
      default:
        bodyContent = _buildClassificationContent();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoSort AI'),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).signOut();
            },
          ),
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

  Widget _buildClassificationContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Upload a clear photo of the waste item:',
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
                onPressed: () => _getImage(ImageSource.gallery),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
              onPressed: _isLoading ? null : _classifyImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 5,
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
                  : const Text(
                'ANALYZE WASTE',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          if (_classificationResult != null && !_isLoading) ...[
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getResultColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _getResultColor().withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _classificationResult!.toLowerCase().contains('compostable')
                            ? Icons.eco
                            : _classificationResult!.toLowerCase().contains('recyclable')
                            ? Icons.recycling
                            : _classificationResult!.toLowerCase().contains('hazardous')
                            ? Icons.warning
                            : Icons.delete_sweep,
                        color: _getResultColor(),
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _classificationResult!,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _getResultColor(),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  if (_confidence != null && _confidence != 'Unknown') ...[
                    const SizedBox(height: 15),
                    Text(
                      'Confidence: $_confidence',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_explanation != null && _explanation != 'No detailed analysis provided.') ...[
                    const SizedBox(height: 15),
                    const Text(
                      'Analysis:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _explanation!,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                  if (_disposalInstructions != null && _disposalInstructions != 'Disposal information not available.') ...[
                    const SizedBox(height: 15),
                    const Text(
                      'Disposal Instructions:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _disposalInstructions!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SchedulePickupScreen(
                      user: widget.user,
                      wasteType: _classificationResult!.replaceAll('COMPOSTABLE (', '').replaceAll(')', ''),
                      amountKg: 1.0,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 5,
              ),
              child: const Text(
                'SCHEDULE PICKUP (IF APPLICABLE)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 30),
          if (_history.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'RECENT SCANS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ..._history.map((item) {
              final String category = item['category'] ?? 'Unknown';
              final bool isCompostable = item['is_compostable'] == true;
              final Color itemColor = isCompostable ? Colors.green : (category == 'Recyclable' ? Colors.blue : (category == 'Hazardous' ? Colors.deepOrange : Colors.red));

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
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
                            errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.broken_image, size: 100, color: Colors.grey),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isCompostable ? Icons.eco : (category == 'Recyclable' ? Icons.recycling : (category == 'Hazardous' ? Icons.warning : Icons.delete_sweep)),
                            color: itemColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              category.toUpperCase(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: itemColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (item['confidence'] != null && item['confidence'] != 'Unknown')
                            Text(
                              item['confidence'],
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                      if (isCompostable && category != 'Compostable')
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Flagged as Compostable',
                            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.green.shade700),
                          ),
                        ),
                      if (item['explanation'] != null && item['explanation'] != 'No detailed analysis provided.') ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Analysis:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          item['explanation'],
                          style: const TextStyle(fontSize: 14, color: Colors.black54),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item['instructions'] != null && item['instructions'] != 'Disposal information not available.') ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Instructions:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          item['instructions'],
                          style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
          if (_image == null && _history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  'Take or select a photo to get started!',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}