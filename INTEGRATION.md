# Intégration Nova Paris

Les modules gestion utilisateur et ménage sont composés par `lib/main.dart` et
`lib/app/auth_gate.dart`. Le lancement normal ouvre `nova_paris.db` avec sqflite.
Voir SQLITE.md pour la création initiale, les comptes et les limites locales.

## Frontières des modules

`lib/user_management` contient modèles, écrans et services utilisateur.
`lib/housekeeping` contient modèles, écrans, widgets et transports du ménage.
`lib/shared` contient les contrats, la base locale, les erreurs et le thème.
Chaque module conserve la structure du professeur et reste indépendant de l'autre,
de app et de demo. L'application possède un seul MaterialApp.

`UserRepository` définit connexion, inscription et gestion des profils.
`SqliteUserRepository` l'implémente avec un identifiant de session persistant dans
SQLite et le stockage local. La déconnexion efface cet identifiant ; le rôle et
la validité du profil sont relus depuis la base à chaque ouverture.
`HousekeepingBackend` et `RoomCatalogBackend` restent les interfaces des écrans.
`SqliteHousekeeping` et `SqliteRoomCatalog` utilisent `LocalSessionStore`, sans
importer le module utilisateur. app injecte les instances partageant la même base.

Les identifiants stables relient les profils aux chambres. Le rôle staff est
adapté en agent pour le modèle du ménage. Manager/admin gèrent le catalogue et
les utilisateurs ; seule la gouvernante attribue, valide et modifie le stock.
Les mutations relisent l'état et les permissions dans une transaction SQLite ;
les versions empêchent les écrasements périmés. Les archives sont réversibles.

AuthGate détruit la navigation de session à la déconnexion ou au changement de rôle.
Les nouveaux modules doivent respecter ces interfaces et ces frontières.
L'ancienne API Node/SQLite est une démonstration séparée, pas le stockage par défaut.
