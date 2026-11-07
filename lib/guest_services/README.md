# Services clients et restauration

## Navigation

- Client: Services clients > Services et réservations (cloche dans la barre supérieure).
- Réception / Direction: même accès pour gérer les dossiers de tous les clients.
- Direction: Gestion de la carte > Catégories pour organiser le menu.
- Direction: Gestion des services > Gérer les créneaux pour ouvrir les réservations restaurant et spa.
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

## Livraison en chambre

- La réception accepte la commande et choisit un agent d’étage dans l’annuaire.
- La cuisine prépare les articles et marque la commande « Prête à livrer » dans Services clients → Cuisine · Commandes. Le bouton « Gérer le stock » ouvre les portions.
- L’agent ouvre Services clients → Mes livraisons. Seul l’agent attribué peut confirmer la remise, une fois la commande prête.
- La réception consulte le nom de l’agent et l’heure de remise sous « Terminées ». Les données se rechargent à l’ouverture, à l’actualisation ou chaque minute sur cet écran.
- Les commandes en cours antérieures à la version 6 doivent être attribuées. Les anciennes livraisons gardent leur historique sans inventer d’agent.

## Stock et traitement des commandes

- Le rôle Cuisine gère les portions libres et peut suspendre les commandes d’un plat. La direction gère le contenu et la publication de la carte.
- Les plats épuisés ou en pause restent visibles mais indisponibles. Les quantités sont réservées lors de la confirmation, dans la même transaction que la commande.
- La file « À traiter » conserve les commandes après acceptation. Une annulation exceptionnelle, avec motif, est accessible sous « Autres actions ».
- Une annulation avant acceptation restitue les portions réservées. Une fois la préparation lancée, la cuisine décide du stock réellement récupérable.
- Au premier passage en version 5, renseignez les portions libres de chaque plat dans Cuisine → Services clients → Gérer le stock. Les anciennes commandes ne sont pas décomptées une seconde fois et leur annulation ne crée pas de stock.
- Le stock est partagé par les commandes de cette base locale uniquement.

## Installation et migration

Schéma du module: version 6. Tables exclusivement préfixées guest_services_.
Une installation neuve ne contient ni plats, ni créneaux, ni réservations, ni associations automatiques de chambre.
La direction configure la carte et les créneaux. La réception vérifie les chambres dans son registre.
Une mise à jour conserve les commandes et la carte existantes. Les anciennes associations automatiques sont désactivées.
Les anciennes commandes sans séjour restent consultables et peuvent être annulées avec un motif.

## Intégrations et limites de déploiement

Les données utilisent la base SQLite de l’application. Les appareils ne synchronisent pas leurs données.
L’authentification et l’annuaire proviennent du module Utilisateurs, inchangé.
L’association de chambre est vérifiée manuellement par réception; aucun séjour n’est créé dans Réservations.
Aucun paiement, aucune notification externe ni aucune écriture de facture n’est déclenché.
Un déploiement hôtelier multi-appareils nécessite donc les contrats d’authentification, de synchronisation et de facturation correspondants.

## Validation

flutter analyze
flutter test test/guest_services test/app/app_shell_test.dart
