# Gestion des chambres par le Manager

Le module est dans lib/housekeeping. Le menu est injecté par lib/app dans l'accueil
Manager : user_management n'importe pas les écrans métier du ménage.

Le catalogue utilise SQLite sur cet appareil. Aucun script serveur à appliquer.
Voir SQLITE.md pour le lancement et les comptes locaux.

## Depuis le téléphone

Relancer lib/main.dart depuis IntelliJ pour installer la dernière version.
Se connecter avec le Manager > **Gérer les chambres** > **Créer une chambre**.

- Numéro unique de 100 à 999. Le premier chiffre indique l'étage, conformément
  à la convention existante de l'application. Les filtres affichent tous les
  étages réellement présents, y compris 5 à 9.
- Catégorie libre, obligatoire, 80 caractères maximum.
- Une nouvelle chambre est « À nettoyer / En attente », sans agent. La
  gouvernante l'attribue puis valide le nettoyage ; le Manager ne contourne
  pas ce processus et ne marque pas une chambre prête lui-même.
- Modifier change la catégorie ; le numéro reste stable pour préserver les
  notifications, les attributions et l'historique.
- Archiver retire une chambre du planning et conserve son historique. Une
  chambre occupée, en maintenance ou avec une tâche active/attribuée ne peut
  pas être archivée. Une chambre déjà validée peut être archivée même si son
  dernier agent figure encore dans l'historique.
- Restaurer remet la chambre dans la file « À nettoyer », sans agent et sans
  approbation. Son numéro reste réservé tant qu'elle est archivée.

Les onglets Actives / Archivées, la recherche, les compteurs, l'actualisation,
les versions contre les conflits et les confirmations de brouillons sont fournis.
Les anciennes chambres de démonstration ne sont pas effacées automatiquement.
Vous pouvez conserver celles utiles ou archiver celles dont vous n'avez plus besoin.

## Permissions et intégration

SqliteRoomCatalog vérifie le rôle dans la transaction SQLite de chaque mutation.
Agent, Gouvernante et Client ne gèrent pas le catalogue. Manager/admin n'obtient
pas l'accès au nettoyage ni au stock. Les chambres archivées ne sont pas exposées
par SqliteHousekeeping. Les opérations conservent la version et l'historique.
Les réservations réelles, départs et interventions restent aux modules du groupe.

## Vérification

sqlite_test.dart vérifie persistance, conflits, permissions et archive/restauration
avec un vrai fichier SQLite. room_catalog_test.dart couvre le catalogue, les
brouillons et les formulaires à 320 px / texte 200 %. Le rendu manager_rooms.png
conserve le Figma, Manrope et les icônes Material.
