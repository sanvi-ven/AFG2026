import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// deep-links to the device's default maps app for an address, same
/// url_launcher pattern already used for external links in appointments_page.dart.
/// No geocoding/lat-lng is available anywhere in this app, so this opens a
/// map search on the free-text address rather than plotting an exact point.
class GetDirectionsButton extends StatelessWidget {
  const GetDirectionsButton({required this.address, super.key});

  final String address;

  Future<void> _open() async {
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: address.trim().isEmpty ? null : _open,
      icon: const Icon(Icons.directions_outlined),
      label: const Text('Get Directions'),
    );
  }
}
