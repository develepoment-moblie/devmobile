# Services clients et restauration

## Navigation

- Client: Services clients > Room service, Mes commandes, Restaurant, Spa ou Demandes et réclamations.
- Réception / Direction: Services clients > Commandes, Restaurant, Spa, Chambres des clients ou Demandes et réclamations. La direction dispose aussi de Carte et Créneaux du spa.
- Cuisine: Services clients > Commandes cuisine ou Stock. Agent d’étage: Services clients ouvre Mes livraisons.
- Direction: Carte > Catégories pour organiser le menu.
- Réception / Direction: Chambres des clients pour vérifier et associer un séjour avant les commandes en chambre.

## Fonctionnalités

| Domaine | Client | Réception et direction |
|---|---|---|
| Room service | Carte, panier enregistré, commande, suivi, annulation avant acceptation | Accepter et attribuer à un agent, consulter la livraison et son historique |
| Carte et catégories | Consultation | Direction: création, modification, archivage et restauration |
| Restaurant et spa | Réservation, modification et annulation en attente | Confirmation, progression, annulation motivée et archivage |
| Créneaux | Consultation des capacités et tarifs | Direction: création, modification sans réservation active, archivage et restauration |
| Demandes spéciales | Création, consultation, modification et annulation en attente | Attribution au personnel, progression, clôture, archivage et restauration |
| Réclamations | Création et suivi dans un dossier dédié | Traitement, réponses, motif de refus, clôture et historique |
| Messagerie | Messages, modification et suppression de ses propres messages | Réponses dans chaque dossier; aucune modification des messages du client |
| Avis | Création après service terminé, consultation, modification et suppression de son avis | Consultation |

## Règles métier

- Les réservations en attente réservent déjà des places. Les contrôles de capacité et les écritures sont transactionnels.
- Deux rendez-vous actifs du même client ne peuvent pas se chevaucher.
- Une ressource nommée ne peut pas avoir deux créneaux actifs qui se chevauchent.
- Les réservations conservent les horaires, le nom et le tarif du créneau à la création/modification.
- Les dossiers et messages fermés ne peuvent plus être modifiés; les avis restent sous contrôle de leur auteur.
- Les changements de statut, messages, avis et réservations utilisent des contrôles de version pour rejeter les formulaires obsolètes.
- Les archives remplacent la suppression des données opérationnelles; messages supprimés et historique des actions restent identifiables.
- Les montants des commandes passées restent inchangés après modification de la carte.
- Une catégorie contenant des articles actifs ne peut pas être archivée.
- Les commandes en chambre exigent une association client/chambre vérifiée par réception et une date de départ future.

## Plan de salle

- Dans Services clients → Restaurant → Ouvrir le plan de salle, le personnel voit les tables fixes 101 à 109. La direction peut choisir « Réserver une table » et confirmer pour un compte client ou saisir le nom d’un visiteur extérieur.
- Avec « Réserver une table », le client et la direction choisissent directement une date et une heure futures, puis la taille du groupe et la table. Chaque nouvelle réservation bloque la table pendant deux heures. « Suggérer une table » met en évidence la plus petite table disponible qui convient. La note est facultative.
- Les anciennes réservations restent consultables. À l’arrivée, la réception peut placer leurs groupes à une table disponible du plan actuel. Les services déjà en cours sur les anciennes tables peuvent être clôturés.
- La réception confirme la réservation, enregistre l’arrivée et installe le groupe à la table réservée ou à une autre table disponible et adaptée. Les réservations existantes sans table se placent à l’arrivée.
- SQLite vérifie la disponibilité lors de l’enregistrement. Une demande en attente bloque déjà la table pour la période. Une annulation ou une clôture retire ce blocage. Le placement vérifie également l’occupation réelle, et « Terminer et libérer » libère la table au départ.

## Livraison en chambre

- La réception accepte la commande et choisit un agent d’étage dans l’annuaire.
- La cuisine prépare les articles et marque la commande « Prête à livrer » dans Services clients → Cuisine · Commandes. Le bouton « Gérer le stock » ouvre les portions.
- L’agent ouvre Services clients → Mes livraisons. Seul l’agent attribué peut confirmer la remise, une fois la commande prête.
- La réception consulte le nom de l’agent et l’heure de remise sous « Terminées ». Les données se rechargent à l’ouverture, à l’actualisation ou chaque minute sur cet écran.
- Les commandes en cours antérieures à la version 6 doivent être attribuées. Les anciennes livraisons gardent leur historique sans inventer d’agent.

## Aide à la répartition et plan de cuisine

- La réception voit les agents classés par nombre de livraisons ouvertes (en préparation, prêtes ou en livraison). La commande en cours d’attribution est exclue du calcul. À charge égale, le nom puis l’identifiant départagent les agents. La suggestion ne tient pas compte des tâches de ménage; la réception garde le choix.
- La cuisine voit d’abord la préparation démarrée, puis les commandes à lancer par objectif de fin le plus proche. Cet objectif correspond à l’heure de commande plus la durée estimée du plat le plus long; les plats d’une même commande sont supposés préparables en parallèle.
- Le plan estime une commande à la fois. Le bouton « Démarrer la préparation » enregistre l’heure réelle et le plan utilise le temps restant. « Marquer prête à livrer » libère la file. Les anciennes commandes sans durée et les préparations qui dépassent leur estimation rendent incertaines les heures suivantes. Les horaires sont indicatifs.

## Stock et traitement des commandes

- Le rôle Cuisine gère les portions libres et peut suspendre les commandes d’un plat. La direction gère le contenu et la publication de la carte.
- Les plats épuisés ou en pause restent visibles mais indisponibles. Les quantités sont réservées lors de la confirmation, dans la même transaction que la commande.
- La file « À traiter » conserve les commandes après acceptation. Une annulation exceptionnelle, avec motif, est accessible sous « Autres actions ».
- Une annulation avant acceptation restitue les portions réservées. Une fois la préparation lancée, la cuisine décide du stock réellement récupérable.
- Au premier passage en version 5, renseignez les portions libres de chaque plat dans Cuisine → Services clients → Gérer le stock. Les anciennes commandes ne sont pas décomptées une seconde fois et leur annulation ne crée pas de stock.
- Le stock est partagé par les commandes de cette base locale uniquement.

## Installation et migration

Schéma du module: version 11. Tables exclusivement préfixées guest_services_.
Une installation neuve ne contient ni plats, ni créneaux, ni réservations, ni associations automatiques de chambre.
La direction configure la carte et les créneaux. La réception vérifie les chambres dans son registre.
Une mise à jour conserve les commandes et la carte existantes. Les anciennes associations automatiques sont désactivées.
Les anciennes commandes sans séjour restent consultables et peuvent être annulées avec un motif.

## Intégrations et limites de déploiement

- **Taux de change** : dans Room service ou Mon panier, « Devise d’affichage » propose plusieurs devises et accepte un code pris en charge par Frankfurter. SQLite conserve le dernier taux daté pour chaque devise, utilisable hors connexion. La commande conserve son total en euros.
- **Confirmation restaurant** : renseignez l’e-mail facultatif à la réservation. Le passage à « Confirmée » déclenche l’envoi. Si le serveur ou Brevo est indisponible, la réservation reste confirmée et la réception peut réessayer depuis le dossier. L’état « acceptée pour envoi » correspond à la réponse du fournisseur.
- **Configuration Brevo** : sur le serveur, définissez `BREVO_API_KEY`, `BREVO_SENDER_EMAIL` (expéditeur vérifié) et `RESTAURANT_EMAIL_TOKEN` (au moins 32 caractères). Lancez le serveur depuis `server` avec `dart run bin/server.dart`. Configurez le build Flutter avec `RESTAURANT_EMAIL_URL` (URL du serveur) et le même `RESTAURANT_EMAIL_TOKEN`, via un fichier local ignoré ou les arguments Dart. Utilisez HTTPS hors des tests Android debug sur réseau privé. Le jeton partagé sert au test sur réseau de confiance. Pour un déploiement public, protégez l’accès par une authentification serveur par utilisateur.

Les données utilisent la base SQLite de l’application. Les appareils ne synchronisent pas leurs données.
L’authentification et l’annuaire proviennent du module Utilisateurs, inchangé.
L’association de chambre est vérifiée manuellement par réception; aucun séjour n’est créé dans Réservations.
Aucun paiement ni écriture de facture n’est déclenché.
Un déploiement hôtelier multi-appareils nécessite donc les contrats d’authentification, de synchronisation et de facturation correspondants.

## Validation

flutter analyze
flutter test test/guest_services test/app/app_shell_test.dart
