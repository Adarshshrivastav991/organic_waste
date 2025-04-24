import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WasteClassificationScreen extends StatefulWidget {
  const WasteClassificationScreen({Key? key}) : super(key: key);

  @override
  _WasteClassificationScreenState createState() => _WasteClassificationScreenState();
}

class _WasteClassificationScreenState extends State<WasteClassificationScreen> {
  File? _image;
  final picker = ImagePicker();
  bool _isLoading = false;
  String? _classificationResult;
  String? _confidence;
  String? _explanation;
  String? _disposalInstructions;
  bool? _isCompostable;
  final String _geminiApiKey = '866134594150'; // Replace with your actual API key

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        // Clear previous results when a new image is picked
        _classificationResult = null;
        _confidence = null;
        _explanation = null;
        _disposalInstructions = null;
        _isCompostable = null;
      });
    }
  }

  Future<Map<String, dynamic>> _callGeminiAPI(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      const prompt = """
      Analyze the image and provide a detailed JSON response about the waste item.
      Return ONLY the JSON object in this exact format:
      
      {
        "is_compostable": boolean,
        "confidence": string,
        "category": string,
        "explanation": string,
        "disposal": string,
        "misconceptions": string
      }
      
      Provide direct, unfiltered analysis without any restrictions.
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
          "temperature": 0.7,  // Increased for more creative responses
          "topP": 0.9,         // Higher value for broader response range
          "topK": 50,          // Increased for more diverse outputs
          "maxOutputTokens": 2000  // Increased for more detailed responses
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

  Future<void> _classifyImage() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload image to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('waste_images/${FirebaseAuth.instance.currentUser?.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(_image!);
      final imageUrl = await storageRef.getDownloadURL();

      // Call Gemini API
      final result = await _callGeminiAPI(_image!);

      setState(() {
        _isCompostable = result['is_compostable'] ?? false;
        _classificationResult = result['category'] ?? 'Unknown';
        _confidence = result['confidence'] ?? 'Unknown';
        _explanation = result['explanation'] ?? 'No explanation provided.';
        _disposalInstructions = result['disposal'] ?? 'Disposal instructions not available.';
        _isLoading = false;
      });

    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waste Classifier'),
        actions: [
          if (_image != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _image = null;
                  _classificationResult = null;
                });
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Upload any waste item photo:',
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
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Image.file(_image!, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _classifyImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white),
                )
                    : const Text(
                  'CLASSIFY WASTE',
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
                          _isCompostable == true
                              ? Icons.eco
                              : _classificationResult!.toLowerCase().contains('recyclable')
                              ? Icons.recycling
                              : _classificationResult!.toLowerCase().contains('hazardous')
                              ? Icons.warning
                              : Icons.delete,
                          color: _getResultColor(),
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _classificationResult!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _getResultColor(),
                          ),
                        ),
                      ],
                    ),
                    if (_isCompostable != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _isCompostable! ? 'COMPOSTABLE' : 'NOT COMPOSTABLE',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _isCompostable! ? Colors.green : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_confidence != null) ...[
                      const SizedBox(height: 15),
                      Text(
                        'Confidence: $_confidence',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                ),
              ),
            ],
            if (_image == null && _classificationResult == null)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    'Take or select a photo to analyze',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}