/// Shared persisted shape; feature models adapt it without cross-module imports.
class TaskSchema {
  static const labels = [
    'Changer le linge de lit',
    'Nettoyer la salle de bain',
    'Nettoyer les surfaces et le sol',
    'Vérifier les produits d’accueil',
  ];
  static List<Map<String, dynamic>> defaults() => [
    for (var i = 0; i < labels.length; i++)
      {'id': 'standard-$i', 'label': labels[i], 'photoId': null},
  ];
  static void ensure(Map<String, dynamic> room) {
    room.putIfAbsent('tasks', defaults);
  }
}
