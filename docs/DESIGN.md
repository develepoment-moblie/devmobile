---
version: alpha
name: Nova Paris
description: Reproduction du module Housekeeping du prototype Figma fourni
colors:
  primary: '#183C35'
  accent: '#C66F55'
  background: '#F7F3EA'
  surface: '#FFFFFF'
  ink: '#25322F'
  muted: '#77837F'
  border: '#E1E5E3'
  tabs: '#E9EAE5'
  gold: '#E9D5AD'
  danger: '#BA5D51'
  warning: '#C88945'
  success: '#5E8D75'
typography:
  sans:
    fontFamily: Manrope
rounded:
  DEFAULT: 14px
  banner: 18px
  number: 12px
  tabs: 13px
spacing:
  page: 18px
  row-gap: 8px
  row-padding: 10px
components:
  button: {}
  card: {}
  tabs: {}
  header: {}
  navigation: {}
  dialog: {}
---

# Nova Paris Design System

Local SQLite variant: keep the existing merged screens and housekeeping design.
Show a compact persistent green local-mode label above navigation. Login adds
native account chips to fill fictional test credentials. No automatic sign-in.
Registration creates and signs in a local guest immediately. The deletion message
explains local access removal and retained historical references. The default
startup uses sqflite; LOCAL_JSON_DEMO=true opens the isolated legacy JSON demo.
See SQLITE.md and UX-CONTRACT.md.

## Overview
### Creative North Star
Le prototype Figma de l'utilisateur, écran p-Housekeeping, est l'autorité visuelle.
Lien : https://www.figma.com/make/Os026couJjAQay0W5ISp2Z/
Mesures extraites du DOM rendu le 15 octobre 2026. Le cadre iPhone de présentation,
le faux horaire 9:41 et la barre d'accueil iOS ne font pas partie de l'app native.
Le système et SafeArea gèrent ces éléments sur téléphone.

### Product context and register
Personnel hôtelier francophone, gestion opérationnelle sur téléphone, mode Operate.
Le marché n'est pas établi par les supports. Aucun contexte japonais.
Conserver le bandeau vert, les numéros de chambre teintés et le bouton terracotta.
Ne pas appliquer l'ancienne palette bleu/or du DOCX.
L'identité est fixée par le Figma : aucune nouvelle direction créative à inventer.

## Colors
Les valeurs canoniques exécutables sont AppColors dans lib/shared/custom/app_theme.dart.
Ce fichier les documente (modèle B). NovaTheme adapte les couleurs à ThemeData,
les composants partagés les consomment. Les tons de statut viennent de roomTone.
Surfaces de statut : rouge #F5E4E0, orange #F7EBDC, vert #E5EFE8, gris #ECEFED.
Les libellés accompagnent toujours les couleurs. Thème clair uniquement.

## Typography
Manrope variable embarquée dans assets/fonts/Manrope.ttf avec sa licence OFL.
Mesures Figma conservées : titre bandeau 18, chambre 9, sous-titre et badge 7,
numéro 11, bouton 10, onglets 8, marque 10, navigation 6.5 pixels logiques.
Ces petites tailles viennent explicitement de la maquette et limitent la lisibilité.
Les nouvelles pages de formulaire utilisent 12 à 16 pixels pour rester utilisables.
Le facteur de texte système est respecté ; les cartes grandissent avec leur texte.

## Layout
Référence Figma : écran 402 × 874. Contenu avec marges 18, cartes séparées de 8,
numéros 47 × 47. Bandeau min-height 88, padding 17, icône 43, gap 12.
Onglets : padding 4, hauteur de bouton 37. CTA : hauteur minimale 46.
Navigation inférieure fixe, cinq destinations, hauteur de bouton 56 + padding 13.
Largeur plafonnée à 402 sur ordinateur. Le téléphone utilise toute sa largeur.
Les listes et formulaires défilent ; pas de hauteur d'écran figée.

## Elevation & Depth
Cartes blanches à bord fin, aucune ombre forte. Retour d'action via SnackBar flottant.
Le CTA utilise la faible élévation native, sans halo décoratif.

## Shapes
Carte 14, numéro 12, bandeau 18, onglets 13 et boutons 14.
Badges en pilule. Icônes de navigation et de notification à trait 1.8 sur grille 24.

## Components
Logo fourni par l'utilisateur : assets/images/nova_paris_logo.png, affiché via
NovaLogo dans l'en-tête et le profil. Il remplace la lettre N de la maquette.
Conserver le fichier original, ses proportions et ses couleurs. Le damier est
intégré aux pixels RGB et n'est pas une transparence.
NovaHeader, StaffBanner, NovaButton, EmptyState et showFeedback : app_widgets.dart.
Roomcard et StatusBadge : roomcard.dart. Icônes géométriques : nova_icon.dart.
Formulaires : Form + TextFormField + DropdownButtonFormField natifs Flutter.
Sélection, survol, focus, pression et désactivation : widgets Material natifs.
Les erreurs sont en ligne. Les retours d'action utilisent un seul helper.
Animations limitées aux transitions et interactions Material, pas d'effet décoratif.

Retour Android : conserver les transitions Material et l'état des onglets.
Le message de double Retour réutilise le SnackBar flottant vert existant, avec
une phrase française explicite et un délai de deux secondes. Aucun nouveau
dialogue bloquant ni thème. Une page imbriquée revient à sa page parente ;
une navigation par onglets revient à l'onglet précédent avant de proposer de quitter.

## Do's and Don'ts
- Reprendre les composants et couleurs partagés sur chaque nouvelle page.
- Utiliser le français et des verbes précis sur les actions.
- Garder les données et validations cohérentes entre toutes les pages.
- Ne pas inventer un écran Figma absent : les pages complémentaires sont des extensions.
- Ne pas confondre sélection de rôle pédagogique et contrôle d'accès sécurisé.

## Fusion gestion utilisateur
La fusion du 15 octobre 2026 reprend connexion, inscription, profils, gestion des
utilisateurs et accueil client de devmobile-Gestion-user. Ces écrans consomment
AppColors et novaTheme ; l'en-tête et les formulaires utilisent le logo commun.
Conserver la composition de l'accueil client fourni et la maquette housekeeping.
Les nouveaux écrans d'accès utilisent des champs de 16 px et des boutons de 50 px,
avec une colonne défilante et la même largeur mobile. La navigation authentifiée
est détruite à la déconnexion et lorsqu'un rôle change. Le rôle Gouvernante reste
distinct des rôles Manager / Administrateur.

## Finition des interactions
Le catalogue Manager reprend les listes blanches, champs Material et boutons
du module utilisateur. Recherche et onglets Actives / Archivées restent au sein
d'un défilement unique pour le texte agrandi. Le formulaire en feuille réutilise
DraftGuard et la largeur mobile existante. Aucun changement aux baselines Figma.
Conserver les baselines Figma. Les dialogues de stock réutilisent AlertDialog,
les champs Material et les tons existants ; une erreur apparaît dans le dialogue
sans effacer la saisie. DraftGuard possède la confirmation commune d'abandon,
avec « Continuer la saisie » comme action sûre initiale. Les badges du détail
reviennent à la ligne sur petit écran et texte agrandi. Les onglets conservent
leurs états en mémoire ; aucun nouveau thème, police ou système de navigation.



## Session et sauvegardes locales

La session SQLite survit au relancement ; Déconnexion reste explicite. Le rôle
vient du profil courant. Manager/admin ouvre Sauvegarder et restaurer depuis
Données locales. Les champs de mots de passe restent masqués ; les erreurs et
annulations préservent les saisies. Le sélecteur natif choisit l’emplacement.
Une prévisualisation précède le dialogue de remplacement, dont Annuler reçoit
le focus. L’opération désactive les boutons et protège Retour. Après restauration,
la session se ferme. Mise en page Material existante, liste défilante et texte
200 % sur petit écran ; aucune nouvelle direction visuelle.

## Espace agent — Mon service

Extension du Figma avec AppColors et Manrope existants : bandeau vert StaffBanner,
surfaces blanches à bord fin, rayon 14 et marges 18. AgentRoomCard est la variante
de file personnelle : titre 17, instructions visibles, badges 11, progression de
checklist et action textuelle. Le Roomcard Figma conserve ses dimensions initiales.
Le tableau de bord emploie une grille de quatre accès de statut sur deux colonnes,
puis la chambre à reprendre. Pas de score, de faux service horaire ou de métrique
« aujourd’hui » sans données datées. Mes chambres utilise des ChoiceChip qui
reviennent à la ligne. Navigation agent à trois destinations avec libellés 11 px ;
la navigation de démonstration/gouvernante conserve sa composition.

## Tâches et photos

Les détails gardent les composants Material, le bandeau, AppColors et Manrope.
Les tâches variables utilisent CheckboxListTile à 13 px, accompagnées de l’état
photo et du bouton Voir la photo. Ajouter une tâche reste un AlertDialog défilant
avec DraftGuard. TaskPhotoScreen utilise une page défilante : consigne, sources
natives, aperçu de 280 px maximum et confirmation explicite. Aucun nouvel écran
Figma n’est revendiqué. La photo remplit un cadre arrondi 14 et conserve ses
proportions. Le viewer propose le zoom natif InteractiveViewer. Les états longs,
erreurs et texte 200 % restent défilants.
