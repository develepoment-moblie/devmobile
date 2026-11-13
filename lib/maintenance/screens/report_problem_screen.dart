import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/intervention.dart';
import '../services/ai_diagnosis_service.dart';
import '../../shared/services/app_session.dart';
import '../services/maintenance_store.dart';
import '../custom/maintenance_theme.dart';
import '../custom/add_photo_card.dart';
import '../custom/maintenance_header.dart';
import '../custom/photo_picker.dart';

/// Formulaire « Signaler un problème » (crée une intervention en base).
class ReportProblemScreen extends StatefulWidget {
  /// Ouvre directement le sélecteur de photo (bouton « Ajouter une photo »).
  final bool startWithPhoto;
  final AppSession session;
  const ReportProblemScreen({
    super.key,
    required this.session,
    this.startWithPhoto = false,
  });

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  late final _store = MaintenanceStore(widget.session.database.database);
  final _formKey = GlobalKey<FormState>();
  final _room = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();

  InterventionCategory _category = InterventionCategory.climatisation;
  InterventionPriority _priority = InterventionPriority.normal;
  final List<Uint8List> _photos = [];
  bool _saving = false;

  // IA : on ne remplace jamais ce que l'utilisateur a déjà choisi.
  bool _categoryTouched = false;
  bool _priorityTouched = false;
  bool _aiAnalyzed = false;

  @override
  void initState() {
    super.initState();
    if (widget.startWithPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addPhoto());
    }
  }

  @override
  void dispose() {
    _room.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final bytes = await pickInterventionPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() => _photos.add(bytes));
    if (!_aiAnalyzed) _analyzePhoto(bytes);
  }

  /// Diagnostic IA de la 1re photo : pré-remplit titre, description,
  /// catégorie et priorité (champs encore vides / non touchés uniquement).
  /// Inactif si aucune clé n'est configurée (AI_API_KEY).
  Future<void> _analyzePhoto(Uint8List bytes) async {
    if (!AiDiagnosisService.isConfigured) return;
    _aiAnalyzed = true;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Analyse de la photo par l'IA…"),
        duration: Duration(seconds: 30),
      ),
    );

    final result = await AiDiagnosisService.analyze(
      image: bytes,
      hint: _title.text,
    );

    messenger.hideCurrentSnackBar();
    if (!mounted) return;

    if (result == null) {
      _aiAnalyzed = false; // permet de réessayer avec une autre photo
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Analyse IA indisponible : remplissez le formulaire.'),
        ),
      );
      return;
    }
    if (!result.isMaintenanceIssue) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Aucun problème de maintenance détecté sur la photo.'),
        ),
      );
      return;
    }

    setState(() {
      if (_title.text.trim().isEmpty) _title.text = result.title;
      if (_description.text.trim().isEmpty) {
        _description.text = result.description;
      }
      if (!_categoryTouched) _category = result.category;
      if (!_priorityTouched) _priority = result.priority;
    });
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Champs pré-remplis par l'IA. Vérifiez avant d'envoyer."),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    try {
      await _store.create(
        title: _title.text,
        room: _room.text,
        category: _category,
        priority: _priority,
        description: _description.text,
        reporter: widget.session.user,
        photos: _photos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Problème signalé. Merci !')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur lors de l'envoi du signalement.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MaintenanceHeader(backTitle: 'Signaler un problème'),
                const SizedBox(height: 24),
                _label('Chambre'),
                TextFormField(
                  controller: _room,
                  textInputAction: TextInputAction.next,
                  decoration: mcInput('Ex : 305'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Indiquez le numéro de chambre'
                      : null,
                ),
                const SizedBox(height: 18),
                _label('Titre du problème'),
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: mcInput('Ex : Climatisation en panne'),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Indiquez un titre (3 caractères min.)'
                      : null,
                ),
                const SizedBox(height: 18),
                _label('Catégorie'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in InterventionCategory.values)
                      _Pill(
                        label: c.label,
                        selected: c == _category,
                        selectedBg: MC.dark,
                        selectedFg: Colors.white,
                        onTap: () => setState(() {
                          _category = c;
                          _categoryTouched = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label('Priorité'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in InterventionPriority.values)
                      _Pill(
                        label: p.label,
                        selected: p == _priority,
                        selectedBg: p.background,
                        selectedFg: p.foreground,
                        onTap: () => setState(() {
                          _priority = p;
                          _priorityTouched = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label('Description (facultatif)'),
                TextFormField(
                  controller: _description,
                  maxLines: 4,
                  decoration: mcInput('Décrivez le problème…'),
                ),
                const SizedBox(height: 18),
                _label('Photos'),
                if (_photos.isNotEmpty) ...[
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _photos[i],
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setState(() => _photos.removeAt(i)),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                AddPhotoCard(onTap: _addPhoto),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: MC.terra,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Envoyer le signalement',
                            style: mt(
                              14,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: mt(13, weight: FontWeight.w700)),
  );
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedBg;
  final Color selectedFg;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.selectedBg,
    required this.selectedFg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? selectedFg : MC.border),
        ),
        child: Text(
          label,
          style: mt(
            12,
            weight: FontWeight.w600,
            color: selected ? selectedFg : MC.text,
          ),
        ),
      ),
    );
  }
}
