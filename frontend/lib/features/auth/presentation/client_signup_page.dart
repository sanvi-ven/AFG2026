// made with help of chatgpt 4.0: create a flutter client signup page outline with a form. include fields for first name, last name, email, phone, and searchable address

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/address_autocomplete_service.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';
import '../../../models/legal_document.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/legal_link.dart';

/// signup page for new client registration with address autocomplete
class ClientSignupPage extends StatefulWidget {
  const ClientSignupPage({super.key});

  @override
  State<ClientSignupPage> createState() => _ClientSignupPageState();
}

class _ClientSignupPageState extends State<ClientSignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingAddressSuggestions = false;
  bool _agreedToTerms = false;
  String? _error;
  Timer? _addressDebounce;
  List<String> _addressSuggestions = const [];

  bool _looksLikeEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) {
      return false;
    }
    final parts = trimmed.split('@');
    if (parts.length != 2) {
      return false;
    }
    if (parts.first.isEmpty || parts.last.isEmpty) {
      return false;
    }
    if (!parts.last.contains('.')) {
      return false;
    }
    if (trimmed.contains(',')) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _addressDebounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    // debounce address search and fetch suggestions
    _addressDebounce?.cancel();

    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _addressSuggestions = const [];
        _isLoadingAddressSuggestions = false;
      });
      return;
    }

    setState(() => _isLoadingAddressSuggestions = true);
    _addressDebounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await AddressAutocompleteService.search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _addressSuggestions = suggestions;
        _isLoadingAddressSuggestions = false;
      });
    });
  }

  /// select an address suggestion and clear the suggestions list
  void _pickAddressSuggestion(String value) {
    _addressController.text = value;
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
  }

  /// submit the signup form with validation
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _error = 'Please agree to the Privacy Policy and Terms of Service to continue.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final email = _emailController.text.trim();
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final idToken = await credential.user!.getIdToken(true);

      final response = await AuthApiService.completeSignup(
        idToken: idToken!,
        role: 'client',
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        address: _addressController.text.trim(),
      );
      final savedProfile = ClientProfile.fromMap(response);
      ClientSession.setProfile(savedProfile);

      // completeSignup just set the role/profile_id custom claims
      // server-side — the token fetched above predates that, so Firestore
      // would keep using it (no role claim) until its own next refresh.
      // Force one more refresh now so the dashboard's first reads/writes
      // already carry the new claims instead of hitting permission-denied.
      final freshToken = await credential.user!.getIdToken(true);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {'role': 'client', 'authToken': freshToken},
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not create your account.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text('Client Sign Up'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 56)),
                  const SizedBox(height: 12),
                  const Text('Enter your details to continue.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(labelText: 'First name', border: OutlineInputBorder()),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'First name is required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(labelText: 'Last name', border: OutlineInputBorder()),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Last name is required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final input = value?.trim() ?? '';
                      if (input.isEmpty) {
                        return 'Email is required';
                      }
                      if (!_looksLikeEmail(input)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Phone is required' : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'By providing your phone number, you agree to receive appointment and invoice '
                    'text reminders. Message and data rates may apply.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (value) {
                      final input = value ?? '';
                      if (input.isEmpty) {
                        return 'Password is required';
                      }
                      if (input.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if ((value ?? '').isEmpty) {
                        return 'Confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isLoadingAddressSuggestions
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    onChanged: _onAddressChanged,
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Address is required' : null,
                  ),
                  if (_addressSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _addressSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _addressSuggestions[index];
                            return ListTile(
                              dense: true,
                              title: Text(suggestion),
                              onTap: () => _pickAddressSuggestion(suggestion),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreedToTerms,
                        onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            children: [
                              const Text('I agree to the '),
                              const LegalLink(
                                  label: 'Privacy Policy', documentId: LegalDocumentIds.privacyPolicy),
                              const Text(' and '),
                              const LegalLink(
                                  label: 'Terms of Service', documentId: LegalDocumentIds.termsOfService),
                              const Text('.'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
