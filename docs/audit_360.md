# Audit 360° — RitajPOS (café-restaurant)

Audit métier réalisé du point de vue d'un propriétaire de café-restaurant voulant
piloter son affaire sur tous les détails. Ce fichier est la **référence** de nos
tâches à venir : chaque besoin est tracé et son statut y est suivi.

Date : 2026-08-10. Pile : Flutter, local-first (SQLite) + Supabase (miroir),
Sunmi printer, RTL arabe. 82 tests, `flutter analyze` 0 issue.

---

## Déjà couvert ✅

- Encaissement cash / carte / mobile / آجل (آجل sans suivi — voir P0#2/#5)
- Monnaie rendue, validation stricte des montants (C6)
- Modes : caisse (comptoir) + tables (6 seedées)
- Menu CRUD (7 catégories) local-first + sync idempotente (C1)
- Shifts : ouverture/fermeture, Z-report imprimé, écart de caisse (C2)
- Rapports jour/semaine/mois civils + toutes (C5)
- Tickets : reçu, rapport, Z-report shift, kitchen (Sunmi)
- Multi-caisse : ordres idempotents (local_key), file de retry (C3),
  statut des tables pull/push (C1)
- Devise : défaut `MAD` conservé ; symboles éditables = feature future (C4)

> Mise à jour 2026-08-11 : P0#5 (coût + dépenses + profit) ✅ — champ coût produit
> (formulaire, SQLite, sync), coût figé sur les lignes de vente, table `expenses`
> locale + Supabase (migration `20260812000000_expenses.sql`, RLS member-read/admin-delete,
> realtime), sync push + file de retry, page « المصروفات » (Admin, manager),
> rapports : CA / coût des ventes / dépenses / profit net. 60 tests, analyze 0.
>
> Mise à jour 2026-08-11 (suite) : P0#2 + P0#3 ✅ — vente bloquée sans shift ouvert
> (`ShiftRequiredException` backstop + SnackBar «يجب فتح الدوام أولاً» au comptoir et
> tables), client آجل : nom requis + tél optionnel dans le dialogue de paiement, stockés
> localement (`orders.customer_name/phone`), synchro Supabase (migration
> `20260812010000_order_customer.sql`), imprimés sur le reçu. 67 tests, analyze 0.
>
> Mise à jour 2026-08-11 (fin) : P0#1 ✅ — fallback offline (le rôle caché n'est plus
> écrasé quand la requête réseau échoue), rôle restauré dès le démarrage, verrous UI
> owner/manager/cashier couverts par des tests (auth_controller + AdminPage + PosPage).
> 77 tests, analyze 0.
>
> Note : la révocation d'un rôle ne se propage pas tant que `myRole` ne retourne
> pas une valeur non nulle (hors-ligne, le rôle caché fait foi) — compromis assumé
> offline-correctness ; à revoir quand la gestion d'utilisateurs existera.
>
> Mise à jour 2026-08-11 (suite) : P0#7 ✅ — le menu se tire désormais depuis le miroir
> (pull LWW par `updated_at`) : produits/prix/suppressions propagés entre appareils,
> pull au chargement et avant chaque push, `syncMenu` corrigé (`active` réel + `updated_at`).
> 82 tests, analyze 0.
>
> Note : le trigger Supabase `trg_products_updated` ré-estampe `updated_at` à l'écriture
> serveur pour les lignes déjà existantes — le LWW compare l'horloge de l'appareil (push)
> à l'horloge du serveur (pull). Convergence correcte pour des appareils NTP ; à documenter/affiner (suivi).

---

## 🔴 P0 — Priorité business (argent, sécurité, légalité, pilotage)

| # | Besoin | Statut |
|---|--------|--------|
| 1 | **Rôles & permissions** : `branch_members.role` inutilisé → tout le monde a accès Admin (un caissier peut modifier le menu / tables). Verrouiller menu/tables/rapports aux `owner`/`manager` ; PIN caisse plus tard | ✅ 2026-08-11 |
| 2 | **Ventes hors shift** : une vente sans shift ouvert est invisible des rapports shift (argent non tracé). Bloquer la vente sans shift | ✅ 2026-08-11 |
| 3 | **آجل sans client** : le mode `credit` ne mémorise aucun client → impossible de savoir qui doit. Exiger nom (+tél) à la vente et les stocker | ✅ 2026-08-11 |
| 4 | **En-tête légal sur le ticket** : reçu imprime « RitajPOS » en dur. Ajouter nom resto, adresse, tél, RC/patente, TVA (obligation légale) | ⏳ |
| 5 | **Aucun coût ni dépense ni profit** : `products.cost` toujours 0, pas de dépenses → pas de marge/profit réel | ✅ 2026-08-11 |
| 6 | **Pas de dashboard pilotage** : rapports = simple liste. Manque CA, ticket moyen, nb tickets, par moyen, top produits, profit | ⏳ en cours |
| 7 | **Menu cross-caisse : pull manquant** : `syncMenu` pousse mais ne rapatrie jamais les produits/prix des autres appareils → divergence | ✅ 2026-08-11 |
| 8 | **Historique des shifts** : le Z-report est imprimé puis perdu ; aucun écran pour consulter les shifts passés / écarts | ⬜ P1 |
| 9 | **Void / remboursement** : erreur de saisie impossible à corriger ; l'ordre reste `paid` à jamais | ⬜ P1 |
| 10 | **Inventaire / stock** : aucune notion d'ingrédients/quantités/alertes stock bas | ⬜ P1 |
| 11 | **Suivi créances (آجل)** : liste des clients endettés, relances | ⬜ P1 |

## 🟠 P1 — Opérationnel quotidien

| # | Besoin | Statut |
|---|--------|--------|
| 12 | Détail du ticket avant paiement (vérification par le caissier) | ⬜ |
| 13 | Distinction sur place / à emporter | ⬜ |
| 14 | Paiement fractionné (cash + carte sur la même note) | ⬜ |
| 15 | Réimpression du dernier reçu | ⬜ |
| 16 | Kitchen ticket pour les commandes comptoir (à emporter) | ⬜ |
| 17 | Statut table « réservé » (schema: reserved/billed inutilisés) | ⬜ |
| 18 | Temps d'occupation des tables | ⬜ |
| 19 | Déplacer / fusionner / splitter des tables | ⬜ |
| 20 | Ventes par employé (cashier_id stocké, jamais affiché) | ⬜ |
| 21 | Remises (%, montant) | ⬜ |
| 22 | Export CSV/PDF pour le comptable | ⬜ |

## 🟡 P2 — Confort & évolutivité

| # | Besoin | Statut |
|---|--------|--------|
| 23 | Catégories libres (قهوة، حلويات…) au lieu de 7 enums hardcodées | ⬜ |
| 24 | Modificateurs / options (sans salade, extra fromage, sauce) | ⬜ |
| 25 | Code-barres (champ exists) | ⬜ |
| 26 | Images produits | ⬜ |
| 27 | Recherche produit dans la grille | ⬜ |
| 28 | Audit trail (qui a modifié/supprimé quoi) | ⬜ |
| 29 | Realtime multi-caisse (publish existe, app ne s'abonne pas) | ⬜ |
| 30 | Retry sync périodique / sur reconnexion (actuellement login/startup) | ⬜ |
| 31 | Backup SQLite / export données | ⬜ |
| 32 | Indicateur « X commandes en attente de sync » | ⬜ |

---

## Ordre d'exécution P0 (recommandé)

1. Rôles + verrouillage admin (#1) — ✅ 2026-08-11
2. Ventes bloquées hors shift + آجل exige client (#2 #3) — ✅ 2026-08-11
3. En-tête resto + TVA (#4)
4. Coût + dépenses → profit (#5) ✅ 2026-08-11
5. Dashboard pilotage (#6) — profit dispo, reste CA/ticket moyen/nb tickets/moyen/top produits
6. Pull menu cross-caisse (#7) ✅ 2026-08-11
