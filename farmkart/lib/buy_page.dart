import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final FirebaseAuth _auth = FirebaseAuth.instance;

Future<void> addCompostProduct({
  required String name,
  required String type,
  required String description,
  required double pricePerKg,
  required double availableQuantity,
  String? imageUrl,
  String? contactPhone,
  String? contactEmail,
}) async {
  try {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Use provided email or fallback to user's email
    final sellerEmail = contactEmail ?? user.email ?? '';

    final productData = {
      'name': name,
      'type': type,
      'description': description,
      'pricePerKg': pricePerKg,
      'availableQuantity': availableQuantity,
      'imageUrl': imageUrl ?? '',
      'sellerId': user.uid,
      'sellerName': user.displayName ?? 'Anonymous Seller',
      'sellerEmail': sellerEmail,
      'sellerPhone': contactPhone ?? '',
      'isAvailable': availableQuantity > 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('compost_products').add(productData);
    print('Product added successfully');
  } catch (e) {
    print('Error adding product: $e');
    rethrow;
  }
}

// Example usage:
void addSampleProduct() {
  addCompostProduct(
    name: "Premium Vermicompost",
    type: "Vermicompost",
    description: "High quality worm compost made from organic waste...",
    pricePerKg: 1.50,
    availableQuantity: 200,
    imageUrl: "https://example.com/vermicompost.jpg",
    contactPhone: "+1234567890",
    contactEmail: "seller@example.com",
  );
}