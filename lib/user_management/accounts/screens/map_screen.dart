import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../shared/custom/app_widgets.dart';

// Skander's map: the hotel and nearby experiences. Opened from the "Carte"
// button of the home bar.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Center of Paris
  static const _parisCenter = LatLng(48.8566, 2.3522);

  GoogleMapController? _controller;
  bool _locationAllowed = false;

  // A few markers for the experiences
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
  void initState() {
    super.initState();
    _askLocation();
  }

  // Asks Android for the location once; the blue dot only shows if allowed.
  // A refusal or an error just leaves the map without the dot.
  Future<void> _askLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      setState(() {
        _locationAllowed = permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always;
      });
    } catch (_) {
      // No location service on this device: keep the map without the dot.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          HeroHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 22, 20),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Retour',
                  color: Colors.white,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const Text(
                  'Carte',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _parisCenter,
                zoom: 13.5,
              ),
              markers: _markers,
              onMapCreated: (controller) => _controller = controller,
              // Blue dot and "center on me" button only once allowed.
              myLocationEnabled: _locationAllowed,
              myLocationButtonEnabled: _locationAllowed,
              zoomControlsEnabled: false, // cleaner look, no +/- buttons
            ),
          ),
        ],
      ),
    );
  }
}
