// schedule_pickup_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'waste_collection_service.dart';

class SchedulePickupScreen extends StatefulWidget {
  final User user;
  final String wasteType;
  final double amountKg;

  const SchedulePickupScreen({
    Key? key,
    required this.user,
    required this.wasteType,
    this.amountKg = 1.0,
  }) : super(key: key);

  @override
  _SchedulePickupScreenState createState() => _SchedulePickupScreenState();
}

class _SchedulePickupScreenState extends State<SchedulePickupScreen> {
  final WasteCollectionService _collectionService = WasteCollectionService();
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _notes = '';
  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selectedCompany;
  Map<String, dynamic>? _schedulePrediction;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _loadCompanies();
    _predictSchedule();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    try {
      // In a real app, get user's actual location
      const userLat = 37.7749; // Example: San Francisco latitude
      const userLon = -122.4194; // Example: San Francisco longitude

      final companies = await _collectionService.getNearbyCompanies(
        userId: widget.user.uid,
        wasteType: widget.wasteType,
        latitude: userLat,
        longitude: userLon,
        radiusInKm: 10.0,
      );

      setState(() {
        _companies = companies;
        if (companies.isNotEmpty) {
          _selectedCompany = companies.first;
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _predictSchedule() async {
    final prediction = await _collectionService.predictOptimalSchedule(widget.user.uid);
    setState(() => _schedulePrediction = prediction);
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCompany == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a company')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final success = await _collectionService.schedulePickup(
        userId: widget.user.uid,
        companyId: _selectedCompany!['id'],
        wasteType: widget.wasteType,
        amountKg: widget.amountKg,
        preferredDate: dateTime,
        userNotes: _notes,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pickup scheduled successfully!')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to schedule pickup')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Schedule Waste Pickup'),
        ),
        body: _isLoading && _companies.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              if (_schedulePrediction != null &&
              _schedulePrediction!['suggestion'] != null)
              Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Schedule Recommendation',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_schedulePrediction!['suggestion']),
                    if (_schedulePrediction!['nextPickup'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Next suggested pickup: ${DateFormat.yMMMd().format(_schedulePrediction!['nextPickup'])}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Waste Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: Text('Type: ${widget.wasteType}'),
              subtitle: Text('Amount: ${widget.amountKg} kg'),
            ),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              'Select Company',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (_companies.isEmpty)
        const Text('No companies available for this waste type'),
    ..._companies.map((company) => RadioListTile<Map<String, dynamic>>(
    title: Text(company['name']),
    subtitle: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Text(company['address']),
    Text(
    '${company['distance'].toStringAsFixed(1)} km away',
    style: TextStyle(color: Colors.grey[600]),
    ),
    if (company['rating'] != null)
    Row(
    children: [
    const Icon(Icons.star, color: Colors.amber, size: 16),
    Text(' ${company['rating'].toStringAsFixed(1)}'),
    ],
    ),
    ],
    ),
    value: company,
    groupValue: _selectedCompany,
    onChanged: (value) =>
    setState(() => _selectedCompany = value),
    )),
    const SizedBox(height: 20),
    const Text(
    'Pickup Date & Time',
    style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    ),
    ),
    const SizedBox(height: 10),
    Row(
    children: [
    Expanded(
    child: OutlinedButton(
    onPressed: () => _selectDate(context),
    child: Text(DateFormat.yMMMd().format(_selectedDate)),
    ),


    ),
    ],
    ),
    const SizedBox(height: 20),
    TextFormField(
    decoration: const InputDecoration(
    labelText: 'Additional Notes',
    border: OutlineInputBorder(),
    ),
    maxLines: 3,
    onChanged: (value) => _notes = value,
    ),
    const SizedBox(height: 30),
    SizedBox(
    width: double.infinity,
    child: ElevatedButton(
    onPressed: _isLoading ? null : _submitRequest,
    style: ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 16),
    ),
    child: _isLoading
    ? const CircularProgressIndicator()
        : const Text(
    'SCHEDULE PICKUP',
    style: TextStyle(fontSize: 16),
    ),
    ),
    ),
    ],
    ),
    ),
    ),
    );
  }
}