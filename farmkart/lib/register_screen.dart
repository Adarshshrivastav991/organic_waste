import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _companyRegNumberController = TextEditingController();

  bool _isLoading = false;
  bool _isCompanyRegistration = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _companyRegNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('EcoSort AI - Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Registration Type Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Register as:'),
                  SizedBox(width: 20),
                  ToggleButtons(
                    isSelected: [
                      !_isCompanyRegistration,
                      _isCompanyRegistration
                    ],
                    onPressed: (index) {
                      setState(() {
                        _isCompanyRegistration = index == 1;
                      });
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Individual'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Company'),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20),

              // Common Fields
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Please enter your email' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: _isCompanyRegistration ? 'Contact Person Name' : 'Full Name',
                ),
                validator: (value) =>
                value == null || value.isEmpty ? 'This field is required' : null,
              ),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  if (value.length < 10) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),

              // Company-Specific Fields
              if (_isCompanyRegistration) ...[
                SizedBox(height: 20),
                Text('Company Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextFormField(
                  controller: _companyNameController,
                  decoration: InputDecoration(labelText: 'Company Name'),
                  validator: (value) =>
                  _isCompanyRegistration && (value == null || value.isEmpty)
                      ? 'Please enter company name'
                      : null,
                ),
                TextFormField(
                  controller: _companyAddressController,
                  decoration: InputDecoration(labelText: 'Company Address'),
                  maxLines: 2,
                  validator: (value) =>
                  _isCompanyRegistration && (value == null || value.isEmpty)
                      ? 'Please enter company address'
                      : null,
                ),
                TextFormField(
                  controller: _companyRegNumberController,
                  decoration: InputDecoration(labelText: 'Registration Number'),
                  validator: (value) =>
                  _isCompanyRegistration && (value == null || value.isEmpty)
                      ? 'Please enter registration number'
                      : null,
                ),
              ],

              SizedBox(height: 20),
              if (_isLoading)
                CircularProgressIndicator()
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _register,
                      child: Text(_isCompanyRegistration ? 'Register Company' : 'Register'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => LoginScreen()),
                        );
                      },
                      child: Text('Already have an account? Login'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final authService = Provider.of<AuthService>(context, listen: false);

      try {
        final user = await authService.registerWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        if (user != null) {
          // Save additional user data to Firestore
          await _saveUserData(user.uid);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Registration successful! Please login.')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => LoginScreen()),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${e.toString()}')),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveUserData(String userId) async {
    final userData = {
      'email': _emailController.text.trim(),
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'userType': _isCompanyRegistration ? 'company' : 'individual',
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (_isCompanyRegistration) {
      userData.addAll({
        'companyName': _companyNameController.text.trim(),
        'companyAddress': _companyAddressController.text.trim(),
        'registrationNumber': _companyRegNumberController.text.trim(),
        'verified': false, // Company accounts need verification
      });
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .set(userData);
  }
}