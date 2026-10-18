import 'package:flutter/material.dart';

import '../housekeeping/models/hotel_data.dart';
import '../housekeeping/services/housekeeping_api.dart';
import '../app/main_screen.dart';

// Standalone launch adapter. The merged app supplies its own authenticated token.
class ConnectedScreen extends StatefulWidget {
  final String url;
  final String token;
  const ConnectedScreen({super.key, required this.url, required this.token});
  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen> {
  HotelData? data;
  HousekeepingApi? api;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.token.isEmpty || widget.url.isEmpty) {
        throw const HousekeepingException('Adresse API et session requises.');
      }
      api ??= HousekeepingApi(
        baseUrl: Uri.parse(widget.url),
        tokenProvider: () async => widget.token,
      );
      data ??= HotelData(api: api);
      await data!.refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    api?.close();
    data?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loading && error == null) return MainScreen(data: data!);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Connexion au service ménage…'),
                ] else ...[
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: load, child: const Text('Réessayer')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
