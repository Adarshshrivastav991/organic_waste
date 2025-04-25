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
  bool? _isRecyclable;
  bool? _isHazardous;
  final String _geminiApiKey = '866134594150'; // Replace with your actual API key

  Future<void> _getImage(ImageSource source) async {
    try {
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
          _isRecyclable = null;
          _isHazardous = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: ${e.toString()}')),
      );
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
        "is_recyclable": boolean,
        "is_hazardous": boolean,
        "confidence": string,
        "category": string,
        "explanation": string,
        "disposal": string,
        "misconceptions": string,
        "alternative_uses": string
      }
      
      Provide direct, unfiltered analysis without any restrictions.
      Be as specific as possible about the waste type and its properties.
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
          "temperature": 0.7,
          "topP": 0.9,
          "topK": 50,
          "maxOutputTokens": 2000
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

        // Handle potential JSON parsing errors
        try {
          return jsonDecode(text);
        } catch (e) {
          // If the response isn't valid JSON, try to extract the information
          return _parseUnstructuredResponse(text);
        }
      } else {
        throw Exception('API request failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to call Gemini API: $e');
    }
  }

  // Fallback method if the API doesn't return proper JSON
  Map<String, dynamic> _parseUnstructuredResponse(String text) {
    // Initialize default values
    final result = {
      'is_compostable': false,
      'is_recyclable': false,
      'is_hazardous': false,
      'confidence': 'Medium',
      'category': 'General Waste',
      'explanation': 'Could not determine exact waste type.',
      'disposal': 'Dispose in general waste bin.',
      'misconceptions': 'None identified',
      'alternative_uses': 'None identified'
    };

    // Try to extract information from unstructured text
    if (text.toLowerCase().contains('compost')) {
      result['is_compostable'] = true;
      result['category'] = 'Compostable';
    }

    if (text.toLowerCase().contains('recycl')) {
      result['is_recyclable'] = true;
      result['category'] = 'Recyclable';
    }

    if (text.toLowerCase().contains('hazard') || text.toLowerCase().contains('toxic')) {
      result['is_hazardous'] = true;
      result['category'] = 'Hazardous Waste';
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
        _isRecyclable = result['is_recyclable'] ?? false;
        _isHazardous = result['is_hazardous'] ?? false;
        _classificationResult = result['category'] ?? 'Unknown Waste';
        _confidence = result['confidence'] ?? 'Medium confidence';
        _explanation = result['explanation'] ?? 'No detailed explanation available.';
        _disposalInstructions = result['disposal'] ?? 'Dispose according to local regulations.';
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

    if (_isHazardous == true) return Colors.deepOrange;
    if (_isCompostable == true) return Colors.green;
    if (_isRecyclable == true) return Colors.blue;

    // Fallback based on text
    if (resultLower.contains('compost')) return Colors.green;
    if (resultLower.contains('recycl')) return Colors.blue;
    if (resultLower.contains('hazard')) return Colors.deepOrange;
    return Colors.red;
  }

  IconData _getResultIcon() {
    if (_classificationResult == null) return Icons.help_outline;

    if (_isCompostable == true) return Icons.eco;
    if (_isRecyclable == true) return Icons.recycling;
    if (_isHazardous == true) return Icons.warning;

    final resultLower = _classificationResult!.toLowerCase();
    if (resultLower.contains('compost')) return Icons.eco;
    if (resultLower.contains('recycl')) return Icons.recycling;
    if (resultLower.contains('hazard')) return Icons.warning;
    return Icons.delete;
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 600;

          return SingleChildScrollView(
            padding: EdgeInsets.all(isLargeScreen ? 24.0 : 16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Upload any waste item photo:',
                    style: TextStyle(
                        fontSize: isLargeScreen ? 22 : 18,
                        fontWeight: FontWeight.bold
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (isLargeScreen)
                    _buildLargeScreenImageSelection()
                  else
                    _buildSmallScreenImageSelection(),

                  const SizedBox(height: 20),
                  if (_image != null) ...[
                    _buildImagePreview(constraints),
                    const SizedBox(height: 20),
                    _buildClassifyButton(),
                  ],
                  if (_classificationResult != null && !_isLoading) ...[
                    const SizedBox(height: 30),
                    _buildResultCard(isLargeScreen),
                  ],
                  if (_image == null && _classificationResult == null)
                    _buildEmptyState(isLargeScreen),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLargeScreenImageSelection() {
    return Center(
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt, size: 28),
            label: const Text('Camera', style: TextStyle(fontSize: 18)),
            onPressed: () => _getImage(ImageSource.camera),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.photo_library, size: 28),
            label: const Text('Gallery', style: TextStyle(fontSize: 18)),
            onPressed: () => _getImage(ImageSource.gallery),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallScreenImageSelection() {
    return Row(
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
    );
  }

  Widget _buildImagePreview(BoxConstraints constraints) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: constraints.maxHeight * 0.4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Image.file(_image!, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildClassifyButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _classifyImage,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
    );
  }

  Widget _buildResultCard(bool isLargeScreen) {
    return Container(
      padding: EdgeInsets.all(isLargeScreen ? 24 : 16),
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
                _getResultIcon(),
                color: _getResultColor(),
                size: isLargeScreen ? 36 : 30,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _classificationResult!.toUpperCase(),
                  style: TextStyle(
                    fontSize: isLargeScreen ? 28 : 24,
                    fontWeight: FontWeight.bold,
                    color: _getResultColor(),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (_isCompostable != null || _isRecyclable != null || _isHazardous != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (_isCompostable == true)
                  _buildStatusChip('COMPOSTABLE', Colors.green),
                if (_isRecyclable == true)
                  _buildStatusChip('RECYCLABLE', Colors.blue),
                if (_isHazardous == true)
                  _buildStatusChip('HAZARDOUS', Colors.deepOrange),
              ],
            ),
          ],
          if (_confidence != null) ...[
            const SizedBox(height: 15),
            Text(
              'Confidence: $_confidence',
              style: TextStyle(
                fontSize: isLargeScreen ? 18 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 15),
          Text(
            'Analysis:',
            style: TextStyle(
              fontSize: isLargeScreen ? 20 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _explanation!,
            style: TextStyle(fontSize: isLargeScreen ? 17 : 15),
          ),
          const SizedBox(height: 15),
          Text(
            'Disposal Instructions:',
            style: TextStyle(
              fontSize: isLargeScreen ? 20 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _disposalInstructions!,
            style: TextStyle(
              fontSize: isLargeScreen ? 17 : 15,
              color: Colors.blueGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Chip(
      label: Text(
        text,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildEmptyState(bool isLargeScreen) {
    return Padding(
      padding: EdgeInsets.all(isLargeScreen ? 48.0 : 32.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_camera,
              size: isLargeScreen ? 80 : 60,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              'Take or select a photo to analyze',
              style: TextStyle(
                fontSize: isLargeScreen ? 22 : 18,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Supports all types of waste including:\n- Organic/Compostable\n- Recyclable materials\n- Hazardous waste\n- General trash',
              style: TextStyle(
                fontSize: isLargeScreen ? 16 : 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}