# Nova Paris — application fusionnée locale

Application Flutter/Dart scolaire : gestion utilisateur, chambres et ménage.
Le Figma fourni, le logo et la structure models/custom/screens du professeur
font autorité. Interface française pour un usage opérationnel sur téléphone.

Le lancement normal utilise SQLite avec sqflite. Les données sont locales et
persistantes ; aucun serveur, compte cloud, synchronisation ou push. La base
n'est pas chiffrée. Les comptes fictifs initiaux servent au cours. Voir SQLITE.md.

Manager/admin gère les profils et le catalogue des chambres. La gouvernante
attribue, valide et gère le stock. Chaque agent modifie uniquement ses tâches.
Guest ouvre l'accueil client ; maintenance garde son espace d'attente fourni.
L'inscription publique crée un client et le connecte immédiatement. La création
par le Manager conserve sa session. La suppression logique d'un profil retire
son accès et conserve ses références historiques.

Une mutation relit état, rôle et version dans une transaction SQLite. Une erreur
annule toute la mutation ; les formulaires conservent les saisies. La navigation
de session disparaît à la déconnexion ou au changement de rôle. Les chambres
créées et restaurées doivent être nettoyées.

Conserver setState, Form, TextFormField, Navigator et les conventions Material.
Réservations, interventions, paiements, restaurant et autres modules restent
chez les autres membres du groupe.
