import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'auth_service.dart'; // Assuming this file exists
import 'marketplace_screen.dart'; // Assuming this file exists and contains MarketplaceScreen
import 'schedule_pickup_screen.dart'; // Assuming this file exists

// --- Placeholder for NearBy Store Screen ---
// Replace this with your actual NearBy Store screen widget
class NearByStoreScreen extends StatelessWidget {
  const NearByStoreScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on, size: 80, color: Colors.blueGrey),
          SizedBox(height: 16),
          Text(
            'NearBy Store Screen Placeholder',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Implement your store locator/list here',
            style: TextStyle(fontSize: 16, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
// -------------------------------------------


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
  // IMPORTANT: Securely manage API keys. This is for demonstration.
  final String _geminiApiKey = '866134594150';

  int _selectedIndex = 0; // 0: Classify, 1: Marketplace, 2: NearBy Store

  @override
  void initState() {
    super.initState();
    // Load history only if the user is authenticated (which is handled by the HomeScreen constructor requirement)
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('classifications')
          .orderBy('timestamp', descending: true)
          .limit(5) // Limit to last 5 scans
          .get();

      setState(() {
        _history = snapshot.docs.map((doc) => doc.data()).toList();
      });
    } catch (e) {
      print('Error loading history: $e');
      // Optionally show a SnackBar for the user
    }
  }

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85, // Compress image quality slightly
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        // Clear previous results when a new image is picked
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

      // Updated prompt for better clarity and JSON strictness
      const prompt = """
      Analyze the waste item image and provide a JSON response.
      Strictly follow the JSON format below. Do not include any other text.

      JSON Format:
      {
        "is_compostable": boolean, // true if compostable, false otherwise (strict criteria: food waste, yard trimmings, uncoated paper, natural fibers ONLY)
        "confidence": string, // High/Medium/Low based on image clarity and item
        "category": string, // Compostable/Recyclable/Landfill/Hazardous (determine based on common waste streams)
        "explanation": string, // Detailed technical reasoning for the classification
        "disposal": string, // Specific, clear disposal instructions for the item
        "misconceptions": string // Common mistakes or related facts about disposing this item
      }

      Consider common recycling and composting guidelines. Be conservative with "Compostable" and "Recyclable" classifications if unsure.

      Return ONLY the JSON object.
      """;

      // Using the correct endpoint for Gemini Pro Vision
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
                  "mimeType": "image/jpeg", // Assuming JPEG, adjust if using other formats
                  "data": base64Image
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.2, // Slightly more relaxed temperature
          "topP": 0.8,
          "topK": 40,
          "maxOutputTokens": 1500 // Allow more tokens for detailed explanation/instructions
        }
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // Accessing the text part of the response
        final text = responseData['candidates'][0]['content']['parts'][0]['text'];

        try {
          // Attempt to decode the text as JSON
          final jsonResponse = jsonDecode(text);
          // Validate if expected keys exist (basic validation)
          if (jsonResponse.containsKey('is_compostable') &&
              jsonResponse.containsKey('category') &&
              jsonResponse.containsKey('confidence') &&
              jsonResponse.containsKey('explanation') &&
              jsonResponse.containsKey('disposal')) {
            return jsonResponse;
          } else {
            // If JSON is malformed or missing keys, fall back to text parsing
            print('Warning: API returned JSON but missing keys. Falling back to text parsing.');
            print('Raw API Text Response: $text'); // Log the raw text
            return _parsePlainTextResponse(text);
          }

        } catch (e) {
          // If decoding as JSON fails, try parsing as plain text
          print('Warning: API response was not valid JSON. Attempting plain text parse. Error: $e');
          print('Raw API Text Response: $text'); // Log the raw text
          return _parsePlainTextResponse(text);
        }
      } else {
        print('API Error Status: ${response.statusCode}');
        print('API Error Body: ${response.body}');
        throw Exception('API request failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('Error calling Gemini API: $e');
      throw Exception('Failed to call Gemini API: $e');
    }
  }

  // Fallback parser if API doesn't return strict JSON
  Map<String, dynamic> _parsePlainTextResponse(String text) {
    // Basic fallback - improve this if your API frequently deviates
    final result = {
      'is_compostable': false,
      'confidence': 'Unknown',
      'category': 'Unknown',
      'explanation': 'Could not parse detailed explanation from response.',
      'disposal': 'Could not parse disposal instructions from response.',
      'misconceptions': 'Could not parse misconceptions.',
    };

    final lowerText = text.toLowerCase();

    // Attempt to find key indicators in a simple way
    if (lowerText.contains('compostable')) {
      // Be cautious: only mark as compostable if explicitly confirmed
      result['is_compostable'] = (lowerText.contains('"is_compostable": true') ||
          lowerText.contains('is_compostable: true') ||
          lowerText.contains('category: compostable') ||
          lowerText.contains('result: compostable')) &&
          !lowerText.contains('not compostable'); // Ensure it's not negated
      if (result['is_compostable'] == true) {
        result['category'] = 'Compostable';
      }
    } else if (lowerText.contains('recyclable')) {
      result['category'] = 'Recyclable';
    } else if (lowerText.contains('hazardous')) {
      result['category'] = 'Hazardous';
    } else {
      // Default to Landfill if no specific category is found
      result['category'] = 'Landfill';
    }

    // Extract confidence (simple keyword search)
    if (lowerText.contains('confidence: high') || lowerText.contains('"confidence": "high"')) {
      result['confidence'] = 'High';
    } else if (lowerText.contains('confidence: medium') || lowerText.contains('"confidence": "medium"')) {
      result['confidence'] = 'Medium';
    } else if (lowerText.contains('confidence: low') || lowerText.contains('"confidence": "low"')) {
      result['confidence'] = 'Low';
    } else if (result['is_compostable'] == true || result['category'] != 'Landfill') {
      // Assume at least medium confidence if it's classified as something other than unknown/landfill
      result['confidence'] = 'Medium';
    } else {
      result['confidence'] = 'Low'; // Low confidence if it defaults to landfill and no confidence is specified
    }


    // Attempt to extract explanations and disposal (very basic, might need refinement)
    try {
      RegExp expReg = RegExp(r'(explanation|analysis):\s*(.*?)(disposal:|misconceptions:|$)', dotAll: true);
      var matchExp = expReg.firstMatch(lowerText);
      if (matchExp != null && matchExp.group(2) != null) {
        result['explanation'] = matchExp.group(2)!.trim();
      }

      RegExp disposalReg = RegExp(r'(disposal instructions|disposal):\s*(.*?)(explanation:|misconceptions:|$)', dotAll: true);
      var matchDisposal = disposalReg.firstMatch(lowerText);
      if (matchDisposal != null && matchDisposal.group(2) != null) {
        result['disposal'] = matchDisposal.group(2)!.trim();
      }

      RegExp misconceptionsReg = RegExp(r'(misconceptions):\s*(.*?)(explanation:|disposal:|$)', dotAll: true);
      var matchMisconceptions = misconceptionsReg.firstMatch(lowerText);
      if (matchMisconceptions != null && matchMisconceptions.group(2) != null) {
        result['misconceptions'] = matchMisconceptions.group(2)!.trim();
      }

    } catch (e) {
      print('Error parsing specific fields from plain text: $e');
      // Keep default 'Could not parse...' messages
    }


    print('Parsed Plain Text Result: $result'); // Log the parsed result
    return result;
  }


  Future<void> _classifyImage() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return; // Don't proceed if no image is selected
    }

    setState(() {
      _isLoading = true;
      _classificationResult = null; // Clear previous results
      _confidence = null;
      _explanation = null;
      _disposalInstructions = null;
    });

    try {
      // 1. Upload image to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_images/${widget.user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = storageRef.putFile(_image!);

      // Optional: Listen to upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        print('Upload progress: ${snapshot.bytesTransferred / snapshot.totalBytes * 100} %');
      });

      await uploadTask; // Wait for upload to complete
      final imageUrl = await storageRef.getDownloadURL();

      // 2. Call Gemini API
      final result = await _callGeminiAPI(_image!);
      print('API Classification Result: $result'); // Log the result received

      // 3. Save result to Firestore
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

      // 4. Update UI state
      setState(() {
        // Use the category from the result, defaulting if needed
        final category = result['category'] ?? 'Unknown';
        _classificationResult = category.toUpperCase(); // Display category

        // Also show if it's compostable specifically if category is Compostable
        if (result['is_compostable'] == true && _classificationResult != 'COMPOSTABLE') {
          _classificationResult = 'COMPOSTABLE ($category)';
        } else if (result['is_compostable'] == false && _classificationResult == 'COMPOSTABLE') {
          // Edge case: API says compostable is false but category is compostable
          _classificationResult = 'NOT COMPOSTABLE ($category)';
        }


        _confidence = result['confidence'] ?? 'Unknown';
        _explanation = result['explanation'] ?? 'No detailed analysis provided.';
        _disposalInstructions = result['disposal'] ?? 'Disposal information not available.';
        _isLoading = false;
      });

      // 5. Reload history to show the new scan
      _loadHistory();

    } catch (e) {
      print('Classification Error: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Classification failed: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Color _getResultColor() {
    if (_classificationResult == null) return Colors.grey;
    final resultLower = _classificationResult!.toLowerCase();
    if (resultLower.contains('compostable')) return Colors.green;
    if (resultLower.contains('recyclable')) return Colors.blue;
    if (resultLower.contains('hazardous')) return Colors.deepOrange;
    return Colors.red; // Default for Landfill or Unknown
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    // Use a switch statement to determine the body content based on the selected index
    switch (_selectedIndex) {
      case 0:
        bodyContent = _buildClassificationContent();
        break;
      case 1:
        bodyContent = const MarketplaceScreen(); // Display Marketplace screen
        break;
      case 2:
        bodyContent = const NearByStoreScreen(); // Display NearBy Store screen
        break;
      default:
      // Fallback to classification screen if index is unexpected
        bodyContent = _buildClassificationContent();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoSort AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Ensure you have an AuthService provided higher up in your widget tree
              await Provider.of<AuthService>(context, listen: false).signOut();
            },
          ),
        ],
      ),
      body: bodyContent, // The body content is now dynamic
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
        unselectedItemColor: Colors.grey, // Add unselected color for clarity
        onTap: _onItemTapped,
        // Optional: Adjust type based on number of items
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
                foregroundColor: Colors.white, // Text color
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 5, // Add elevation
              ),
              child: _isLoading
                  ? const SizedBox( // Use SizedBox to constrain the indicator size
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
          if (_classificationResult != null && !_isLoading) ...[ // Only show results when not loading
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
                            : Icons.delete_sweep, // Icon for Landfill/Unknown
                        color: _getResultColor(),
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded( // Use Expanded to prevent overflow
                        child: Text(
                          _classificationResult!,
                          style: TextStyle(
                            fontSize: 24, // Slightly smaller font for better fit
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
                  // Optionally display misconceptions if available
                  // if (item['misconceptions'] != null && item['misconceptions'] != 'No common misconceptions noted.') ...[
                  //    const SizedBox(height: 8),
                  //     const Text(
                  //       'Common Misconceptions:',
                  //       style: TextStyle(
                  //         fontSize: 14,
                  //         fontWeight: FontWeight.bold,
                  //       ),
                  //     ),
                  //     Text(
                  //       item['misconceptions'],
                  //       style: const TextStyle(fontSize: 13),
                  //     ),
                  //  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Button to Schedule Pickup
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SchedulePickupScreen(
                      user: widget.user,
                      // Pass the actual category, not just COMPOSTABLE/NOT COMPOSTABLE
                      wasteType: _classificationResult!.replaceAll('COMPOSTABLE (', '').replaceAll(')', ''), // Simple way to get category
                      amountKg: 1.0, // Default or allow user input?
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
          const SizedBox(height: 30), // Add space below results or buttons
          if (_history.isNotEmpty) ...[
            const Divider(), // Add a divider before history
            const SizedBox(height: 10),
            const Text(
              'RECENT SCANS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87, // Use a darker color
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ..._history.map((item) {
              final String category = item['category'] ?? 'Unknown';
              final bool isCompostable = item['is_compostable'] == true; // Use the boolean flag
              final Color itemColor = isCompostable ? Colors.green : (category == 'Recyclable' ? Colors.blue : (category == 'Hazardous' ? Colors.deepOrange : Colors.red));

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3, // Add card elevation
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
                            const Icon(Icons.broken_image, size: 100, color: Colors.grey), // Show error icon if image fails to load
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start, // Align items at the top
                        children: [
                          Icon(
                            isCompostable ? Icons.eco : (category == 'Recyclable' ? Icons.recycling : (category == 'Hazardous' ? Icons.warning : Icons.delete_sweep)),
                            color: itemColor,
                            size: 20, // Smaller icon in history
                          ),
                          const SizedBox(width: 8),
                          Expanded( // Use Expanded for the category text
                            child: Text(
                              category.toUpperCase(), // Display category prominently
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: itemColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8), // Space between category and confidence
                          if (item['confidence'] != null && item['confidence'] != 'Unknown')
                            Text(
                              item['confidence'],
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600, // Slightly bolder
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                      if (isCompostable && category != 'Compostable') // Indicate if it's compostable based on flag but category is different
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
                          style: const TextStyle(fontSize: 14, color: Colors.black54), // Use a slightly lighter color
                          maxLines: 3, // Allow up to 3 lines
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
                          maxLines: 2, // Allow up to 2 lines
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // Optionally display misconceptions in history
                      // if (item['misconceptions'] != null && item['misconceptions'] != 'No common misconceptions noted.') ...[
                      //    const SizedBox(height: 8),
                      //     const Text(
                      //       'Misconceptions:',
                      //       style: TextStyle(
                      //         fontSize: 14,
                      //         fontWeight: FontWeight.bold,
                      //       ),
                      //     ),
                      //     Text(
                      //       item['misconceptions'],
                      //       style: const TextStyle(fontSize: 13),
                      //       maxLines: 2,
                      //       overflow: TextOverflow.ellipsis,
                      //     ),
                      //  ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
          if (_image == null && _history.isEmpty) // Message when no image picked and no history
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