import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/hotel_data.dart';
import 'details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final HotelData data;
  final bool personalOnly;
  const NotificationsScreen({
    super.key,
    required this.data,
    this.personalOnly = false,
  });
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<HotelNotification> get items => widget.personalOnly
      ? widget.data.personalNotifications
      : widget.data.notifications;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.data.addListener(updated);
  }

  void updated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.data.removeListener(updated);
    super.dispose();
  }

  Future<bool> read(List<HotelNotification> items) async {
    if (saving) return false;
    items = items.where((n) => !n.read).toList();
    if (items.isEmpty) return true;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.data.markRead(items);
      return true;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Tout marquer comme lu',
          icon: const Icon(Icons.done_all),
          onPressed: saving || !items.any((n) => !n.read)
              ? null
              : () => read(List.of(items)),
        ),
      ],
    ),
    body: Column(
      children: [
        if (saving) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.red)),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: EmptyState(
                    'Tout est à jour',
                    'Les informations concernant vos chambres apparaîtront ici.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = items[index];
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      child: ListTile(
                        leading: Icon(
                          n.read
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: n.read
                                ? FontWeight.w400
                                : FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          n.message,
                          style: const TextStyle(fontSize: 11),
                        ),
                        // Stock alerts are not about a room: nothing to open.
                        trailing: n.roomNumber.isEmpty
                            ? null
                            : const Icon(Icons.chevron_right),
                        onTap: () async {
                          if (!await read([n]) || !context.mounted) return;
                          if (n.roomNumber.isEmpty) return;
                          final room = widget.data.rooms
                              .where((r) => r.number == n.roomNumber)
                              .firstOrNull;
                          if (room == null ||
                              (widget.personalOnly &&
                                  !widget.data.canClean(room))) {
                            setState(
                              () => error = 'Cette chambre n’est plus disponible. Actualisez le planning.',
                            );
                            return;
                          }
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DetailsScreen(data: widget.data, room: room),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
