import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'marketplace_provider.dart';

class ProductDetailScreen extends StatelessWidget {
  final CompostProduct product;

  const ProductDetailScreen({Key? key, required this.product}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16/9,
              child: product.imageUrl.isNotEmpty
                  ? Image.network(product.imageUrl, fit: BoxFit.cover)
                  : const Placeholder(),
            ),
            const SizedBox(height: 16),
            Text(
              product.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(label: Text(product.type)),
                const Spacer(),
                Text(
                  '${product.pricePerKg.toStringAsFixed(2)}/kg',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Seller: ${product.sellerName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (product.sellerEmail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Email: ${product.sellerEmail}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (product.sellerPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Phone: ${product.sellerPhone}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Description',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(product.description),
            const SizedBox(height: 16),
            Text(
              'Available Quantity: ${product.availableQuantity}kg',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            if (product.sellerPhone.isNotEmpty || product.sellerEmail.isNotEmpty)
              Row(
                children: [
                  if (product.sellerPhone.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.phone),
                        label: const Text('Call'),
                        onPressed: () => _callSeller(context),
                      ),
                    ),
                  if (product.sellerPhone.isNotEmpty && product.sellerEmail.isNotEmpty)
                    const SizedBox(width: 8),
                  if (product.sellerEmail.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.email),
                        label: const Text('Email'),
                        onPressed: () => _emailSeller(context),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _callSeller(BuildContext context) async {
    final phoneUrl = Uri.parse('tel:${product.sellerPhone}');
    if (await canLaunchUrl(phoneUrl)) {
      await launchUrl(phoneUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone app')),
      );
    }
  }

  Future<void> _emailSeller(BuildContext context) async {
    final emailUrl = Uri.parse('mailto:${product.sellerEmail}');
    if (await canLaunchUrl(emailUrl)) {
      await launchUrl(emailUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch email app')),
      );
    }
  }
}