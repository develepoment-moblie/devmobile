import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _darkGreen = Color(0xFF1B3A32);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Center of Paris
  static const _parisCenter = LatLng(48.8566, 2.3522);

  GoogleMapController? _controller;

  // Add a few markers for your experiences
  final Set<Marker> _markers = {
    const Marker(
      markerId: MarkerId('nova_hotel'),
      position: LatLng(48.8566, 2.3522),
      infoWindow: InfoWindow(
        title: 'NOVA PARIS',
        snippet: 'Votre refuge contemporain',
      ),
    ),
    const Marker(
      markerId: MarkerId('spa'),
      position: LatLng(48.8606, 2.3376),
      infoWindow: InfoWindow(title: 'Spa & Détente'),
    ),
    const Marker(
      markerId: MarkerId('restaurant'),
      position: LatLng(48.8530, 2.3499),
      infoWindow: InfoWindow(title: 'Dîner aux chandelles'),
    ),
  };

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _darkGreen),
        title: const Text(
          'Carte',
          style: TextStyle(
            color: _darkGreen,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: _parisCenter,
          zoom: 13.5,
        ),
        markers: _markers,
        onMapCreated: (controller) {
          _controller = controller;
        },
        myLocationEnabled: true,          // Shows the blue dot (requires permission)
        myLocationButtonEnabled: true,    // Shows the button to center on user
        zoomControlsEnabled: false,       // Hides the +/- buttons for a cleaner look
      ),
    );
  }
}