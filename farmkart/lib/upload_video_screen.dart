import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class UploadVideoScreen extends StatefulWidget {
  @override
  _UploadVideoScreenState createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  File? _video;
  TextEditingController _titleController = TextEditingController();
  TextEditingController _descriptionController = TextEditingController();
  bool _isUploading = false;
  double _uploadProgress = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  /// Picks a video from the gallery
  Future<void> _pickVideo() async {
    try {
      final pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );

      if (pickedFile != null) {
        setState(() {
          _video = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking video: ${e.toString()}")),
      );
    }
  }

  /// Uploads video to Firebase Storage and stores metadata in Firestore
  Future<void> _uploadVideo() async {
    if (_video == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please select a video first")),
      );
      return;
    }

    if (_titleController.text.isEmpty || _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter both title and description")),
      );
      return;
    }

    User? user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You need to be logged in to upload videos")),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      // Create a unique filename
      String fileName = "video_${user.uid}_${DateTime.now().millisecondsSinceEpoch}.mp4";
      Reference storageRef = _storage.ref().child("user_videos/${user.uid}/$fileName");

      // Set metadata for the video
      final metadata = SettableMetadata(
        contentType: 'video/mp4',
        customMetadata: {
          'uploaded_by': user.uid,
          'original_filename': _video!.path.split('/').last,
        },
      );

      // Start the upload task
      UploadTask uploadTask = storageRef.putFile(_video!, metadata);

      // Listen to the upload stream
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      }, onError: (e) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: ${e.toString()}")),
        );
      });

      // Wait for the upload to complete
      TaskSnapshot taskSnapshot = await uploadTask.whenComplete(() {});
      String videoUrl = await taskSnapshot.ref.getDownloadURL();

      // Store video details in Firestore
      await _firestore.collection("videos").add({
        "title": _titleController.text,
        "description": _descriptionController.text,
        "videoUrl": videoUrl,
        "userId": user.uid,
        "username": user.displayName ?? "Anonymous",
        "userEmail": user.email,
        "timestamp": FieldValue.serverTimestamp(),
        "likes": 0,
        "views": 0,
        "commentsCount": 0,
      });

      // Reset the form
      setState(() {
        _isUploading = false;
        _video = null;
        _uploadProgress = 0;
        _titleController.clear();
        _descriptionController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Video uploaded successfully!")),
      );

    } catch (error) {
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error uploading video: ${error.toString()}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Upload Video"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video preview section
            if (_video != null)
              Container(
                height: 200,
                color: Colors.black.withOpacity(0.1),
                child: Center(
                  child: Icon(Icons.videocam, size: 50, color: Colors.grey),
                ),
              )
            else
              Container(
                height: 200,
                color: Colors.black.withOpacity(0.05),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.video_library, size: 50, color: Colors.grey),
                      SizedBox(height: 8),
                      Text("No video selected", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),

            SizedBox(height: 20),

            // Video selection button
            ElevatedButton.icon(
              icon: Icon(Icons.video_library),
              label: Text("Select Video"),
              onPressed: _isUploading ? null : _pickVideo,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
              ),
            ),

            SizedBox(height: 20),

            // Title field
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: "Title",
                border: OutlineInputBorder(),
                hintText: "Enter video title",
              ),
              enabled: !_isUploading,
              maxLength: 100,
            ),

            SizedBox(height: 15),

            // Description field
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: "Description",
                border: OutlineInputBorder(),
                hintText: "Enter video description",
              ),
              enabled: !_isUploading,
              maxLines: 3,
              maxLength: 500,
            ),

            SizedBox(height: 25),

            // Upload button or progress indicator
            if (_isUploading)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.grey[200],
                    minHeight: 10,
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Uploading: ${(_uploadProgress * 100).toStringAsFixed(1)}%",
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 5),
                  Text(
                    "Please wait...",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              )
            else
              ElevatedButton(
                onPressed: _uploadVideo,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Text(
                    "Upload Video",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}