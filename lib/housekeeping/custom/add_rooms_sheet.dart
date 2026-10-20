import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/catalog_data.dart';
import '../services/room_catalog_backend.dart';
import 'draft_guard.dart';

// Creates one room or a range of rooms on a floor, e.g. 501 to 510.
// Returns the number of rooms created.
class AddRoomsSheet extends StatefulWidget {
  final CatalogData catalog;
  final int? floor;
  const AddRoomsSheet({super.key, required this.catalog, this.floor});
  @override
  State<AddRoomsSheet> createState() => _AddRoomsSheetState();
}

class _AddRoomsSheetState extends State<AddRoomsSheet> {
  final _form = GlobalKey<FormState>();
  late int _floor = widget.floor ?? _firstFreeFloor();
  late final _from = TextEditingController(text: _nextFree());
  late final _to = TextEditingController(text: _from.text);
  // The autocomplete owns the category field's controller.
  TextEditingController? _category;
  String get _categoryText => _category?.text.trim() ?? '';
  bool _busy = false;
  String? _error;

  int _firstFreeFloor() {
    final used = widget.catalog.snapshot?.floors.toSet() ?? {};
    for (var f = 1; f <= 9; f++) {
      if (!used.contains(f)) return f;
    }
    return 1;
  }

  String _nextFree() {
    final taken = {
      for (final r in [
        ...widget.catalog.rooms,
        ...?widget.catalog.snapshot?.archivedRooms,
      ])
        if (r.floor == _floor) int.parse(r.number) % 100,
    };
    for (var i = 1; i < 100; i++) {
      if (!taken.contains(i)) return i.toString().padLeft(2, '0');
    }
    return '01';
  }

  int? _value(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return v == null || v < 0 || v > 99 ? null : v;
  }

  String get _preview {
    final from = _value(_from), to = _value(_to);
    if (from == null || to == null || from > to) return '';
    final count = to - from + 1;
    final first = _floor * 100 + from, last = _floor * 100 + to;
    return count == 1
        ? 'Chambre $first'
        : 'Chambres $first à $last · $count chambres';
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final from = _value(_from)!, to = _value(_to)!;
    try {
      await widget.catalog.change(RoomCatalogAction.createRange, {
        'floor': _floor,
        'from': from,
        'to': to,
        'category': _categoryText,
      });
      if (mounted) Navigator.pop(context, to - from + 1);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _number(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < 0 || n > 99 ? 'De 00 à 99.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.catalog.snapshot?.categories ?? const <String>[];
    return DraftGuard(
      dirty: _categoryText.isNotEmpty,
      busy: _busy,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ajouter des chambres',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Les chambres créées sont à nettoyer avant leur mise à disposition.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ),
                ),
              DropdownButtonFormField<int>(
                initialValue: _floor,
                decoration: const InputDecoration(labelText: 'Étage'),
                items: [
                  for (var f = 1; f <= 9; f++)
                    DropdownMenuItem(
                      value: f,
                      child: Text(widget.catalog.floorName(f)),
                    ),
                ],
                onChanged: _busy || widget.floor != null
                    ? null
                    : (v) => setState(() {
                        _floor = v!;
                        _from.text = _nextFree();
                        _to.text = _from.text;
                      }),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _from,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      decoration: InputDecoration(
                        labelText: 'De',
                        prefixText: '$_floor',
                      ),
                      validator: _number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _to,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      decoration: InputDecoration(
                        labelText: 'À',
                        prefixText: '$_floor',
                      ),
                      validator: (v) {
                        final base = _number(v);
                        if (base != null) return base;
                        final from = _value(_from), to = _value(_to)!;
                        if (from != null && to < from) return 'Après le début.';
                        if (from != null && to - from >= 50) {
                          return '50 au maximum.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              Autocomplete<String>(
                optionsBuilder: (value) => [
                  for (final c in categories)
                    if (c.toLowerCase().contains(value.text.toLowerCase())) c,
                ],
                onSelected: (_) => setState(() {}),
                fieldViewBuilder: (context, controller, focus, submit) {
                  _category = controller;
                  return TextFormField(
                    controller: controller,
                    focusNode: focus,
                    enabled: !_busy,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie',
                      hintText: 'Chambre Deluxe, Suite…',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Renseignez la catégorie.'
                        : null,
                  );
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  key: ValueKey(_preview),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _preview,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Créer'),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.maybePop(context),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
