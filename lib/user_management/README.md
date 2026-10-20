# Module Utilisateurs

Responsable : **Skander256** · Dossier : `lib/user_management/` · Tests : `test/user_management/`

Comptes, connexion, profils et droits d’accès par rôle.

## Fonctionnalités (cahier des charges)

- [ ] Connexion et inscription
- [ ] Profils et rôles
- [ ] Gestion des utilisateurs par le Manager

## Structure

- `user_management_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `user_management_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `user_management_` (voir CONTRIBUTING.md).
