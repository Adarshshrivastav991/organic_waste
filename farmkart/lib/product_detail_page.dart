import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'marketplace_provider.dart';

class ProductDetailPage extends StatefulWidget {
  final CompostProduct product;

  const ProductDetailPage({Key? key, required this.product}) : super(key: key);

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  double quantity = 1;
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final totalPrice = quantity * product.pricePerKg;

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.grey[200],
                    image: product.imageUrl.isNotEmpty
                        ? DecorationImage(
                      image: NetworkImage(product.imageUrl),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: product.imageUrl.isEmpty
                      ? const Icon(Icons.image, size: 100, color: Colors.grey)
                      : null),
            ),
            const SizedBox(height: 24),
            Text(
              product.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.type,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '₹${product.pricePerKg.toStringAsFixed(2)} per kg',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Available: ${product.availableQuantity} kg',
              style: TextStyle(
                fontSize: 16,
                color: product.availableQuantity > 0
                    ? Colors.green
                    : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Description',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.description.isNotEmpty
                  ? product.description
                  : 'No description provided',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            const Text(
              'Seller Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(product.sellerName),
            ),
            if (product.sellerEmail.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.email),
                title: Text(product.sellerEmail),
              ),
            if (product.sellerPhone.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.phone),
                title: Text(product.sellerPhone),
              ),
            const SizedBox(height: 24),
            if (product.availableQuantity > 0) _buildPurchaseSection(totalPrice),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseSection(double totalPrice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Purchase',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Quantity (kg):',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Slider(
                value: quantity,
                min: 1,
                max: widget.product.availableQuantity > 100
                    ? 100
                    : widget.product.availableQuantity,
                divisions: widget.product.availableQuantity > 10 ? 10 : null,
                label: quantity.round().toString(),
                onChanged: (value) {
                  setState(() {
                    quantity = value;
                  });
                },
              ),
            ),
            Container(
              width: 50,
              alignment: Alignment.center,
              child: Text(
                quantity.round().toString(),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Total Price: ₹${totalPrice.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Message to Seller (Optional)',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _messageController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Add any special requests or questions...',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _handlePurchase,
            child: const Text(
              'Proceed to Purchase',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  void _handlePurchase() {
    if (quantity > widget.product.availableQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Requested quantity exceeds available stock'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Purchase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product: ${widget.product.name}'),
            Text('Quantity: ${quantity.round()} kg'),
            Text('Total Price: ₹${(quantity * widget.product.pricePerKg).toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            const Text('This will notify the seller and initiate the purchase process.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _completePurchase();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _completePurchase() {
    final provider = Provider.of<MarketplaceProvider>(context, listen: false);

    provider.createOrder(
      productId: widget.product.id,
      productName: widget.product.name,
      sellerId: widget.product.sellerId,
      sellerName: widget.product.sellerName,
      quantity: quantity,
      pricePerKg: widget.product.pricePerKg,
      totalPrice: quantity * widget.product.pricePerKg,
      message: _messageController.text,
    ).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order placed successfully!'),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.pop(context); // Return to previous screen
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to place order: $error'),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }
}