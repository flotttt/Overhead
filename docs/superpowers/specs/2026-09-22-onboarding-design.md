# Première mise en route d'Overhead — design

Date : 2026-09-22 · Statut : validé, prêt pour le plan d'implémentation

## Problème

Aujourd'hui la fenêtre de configuration est un pense-bête posé par-dessus une application
déjà démarrée. `AppDelegate.applicationDidFinishLaunching` crée `StatusItemController` et
`NotchController`, démarre `DeviceWatcher`, `MusicController` et `UpdateChecker`, **puis**
affiche la fenêtre si `setupDone` est faux (`AppDelegate.swift:22`). L'icône de barre de
menus et le notch existent donc avant que l'utilisateur ait choisi quoi que ce soit, et
l'accès Bluetooth peut être demandé à quelqu'un qui allait choisir le mode notch — le mode
dont l'argument est précisément que « Bluetooth n'est jamais utilisé ».

Second défaut, plus discret : `setupDone` est posé dans `windowWillClose`
(`SetupWindowController.swift:37`), donc **fermer** et **terminer** sont indiscernables.

## Décisions validées

1. Pendant la configuration : ni icône de barre de menus, ni notch. Fermer la fenêtre avant
   la fin **quitte l'application** — pas de processus fantôme sans aucun moyen de le rouvrir.
2. L'assistant couvre le mode, les permissions, les réglages visuels principaux du notch et
   la connexion automatique du casque. Les gestes, l'haptique et les autres lecteurs restent
   dans le menu.
3. Rouvrir via `Setup…` donne les mêmes étapes, mais toutes accessibles librement.
4. Un panneau **Réglages rapides** séparé, accessible depuis le notch et depuis le menu,
   porte les bascules du quotidien et renvoie vers l'assistant complet.
5. L'aperçu de l'étape notch est le **vrai notch**, pas un rendu de démonstration.

## 1. Séquence de démarrage

`setupDone` reste la source de vérité, sans nouvelle clé.

`applicationDidFinishLaunching` crée ce qui est inerte — `model`, `settings`, `music`,
`updates`, `NotchController` — puis bifurque :

| `setupDone` | Comportement |
|---|---|
| `true` | `startApp()` immédiatement : identique à aujourd'hui |
| `false` | `setupWindow.show()` seul. Pas d'icône, pas de `DeviceWatcher`, pas de `updates.start()` |

```swift
// cible
if settings.setupDone {
    startApp()
} else {
    setupWindow?.show()   // startApp() sera appelé par le bouton final de l'assistant
}
```

`startApp()` est **idempotent** (drapeau `appStarted`) et fait trois choses :

1. créer `StatusItemController` et brancher `onOpenSetup` / `onOpenQuickSettings` ;
2. `applyHeadphones(settings.usageMode.usesHeadphones)` — c'est-à-dire `DeviceWatcher.start()`
   et l'auto-connexion, uniquement si le mode utilise le casque ;
3. `updates.start()`.

Les deux abonnements Combine existants (`music` piloté par `showNotch` + `usageMode`,
`otherPlayers`) ne sont branchés que dans `startApp()`, à une exception près décrite en §2.

Quitter pendant l'assistant laisse donc `setupDone` à faux : au lancement suivant, la
configuration repart du début. C'est voulu — tant que l'utilisateur n'a rien choisi, il n'y a
rien à démarrer.

**Terminé ≠ fermé.** `settings.setupDone = true` quitte `windowWillClose` et passe sur le
bouton final de la dernière étape, qui appelle ensuite `startApp()`. `windowWillClose` devient :

```swift
func windowWillClose(_ notification: Notification) {
    checks.stop()
    settings.notchPreviewing = false
    if !settings.setupDone { NSApp.terminate(nil) }
}
```

## 2. L'assistant

### SetupFlow

Nouveau `SetupFlow: ObservableObject`, dans `Client/macos/Setup/SetupFlow.swift` :

```swift
enum SetupStep { case mode, permissions, notch, headphones, done }

enum SetupMode { case onboarding, revisit }   // choisi à l'ouverture selon setupDone
```

`static func steps(for mode: UsageMode) -> [SetupStep]` est **pure** :

| Mode d'usage | Étapes |
|---|---|
| `notchOnly` | mode, permissions, notch, done |
| `headphonesOnly` | mode, permissions, headphones, done |
| `both` | mode, permissions, notch, headphones, done |

Changer de mode à l'étape 1 recalcule la liste. Si l'étape courante disparaît de la nouvelle
liste, `SetupFlow` retombe sur la première étape suivante encore présente — c'est le cas
limite à ne pas rater, et il est couvert par les tests.

### Navigation

- **onboarding** (`setupDone == false`) : Suivant / Retour, barre latérale en lecture seule
  qui montre la progression. Le bouton de la dernière étape est « Commencer à utiliser Overhead ».
- **révision** (`setupDone == true`) : toutes les étapes cliquables dans la barre latérale,
  pas de Suivant imposé, bouton « Terminé » qui ferme simplement.

Une seule vue, deux comportements : pas de second rendu à maintenir.

### Contenu des étapes

| Étape | Contenu | Source |
|---|---|---|
| mode | les trois `ModeCard` actuelles | `SetupView.swift:24-31`, inchangé |
| permissions | Bluetooth, casque, Spotify, Musique | lignes actuelles, `SetupChecks` **non modifié** |
| notch | largeur, hauteur, taille du notch fermé, halo, anneau de progression | mêmes clés `AppSettings`, sliders de `MenuRows` réutilisés |
| headphones | connexion automatique, reconnexion automatique | `autoConnect`, `autoReconnect` |
| done | lancer à l'ouverture de session + bouton final | `launchAtLogin` |

### L'aperçu du notch

L'étape notch pose `settings.notchPreviewing = true` à l'entrée et `false` à la sortie — le
même mécanisme que le sous-menu Notch Size (`NotchController.swift:124-127` et `:339-340`),
qui devra être joignable depuis l'assistant et plus seulement depuis le menu.

Pendant cette étape **et seulement elle**, `music.start()` est appelé, puis `music.stop()` en
sortie si `startApp()` n'a pas encore eu lieu. Sans ça on règle la taille d'une pochette
qu'on ne voit pas. C'est la seule entorse au principe « rien ne démarre », et elle est bornée
à une étape.

## 3. Le panneau Réglages rapides

Une fenêtre courte, distincte de l'assistant, dans `Client/macos/Setup/QuickSettingsView.swift`.

Contenu :

- Afficher le notch (`showNotch`)
- Mode d'usage : les trois choix, en contrôle segmenté
- Spotify et Musique : état de l'autorisation et bouton Autoriser, via `SetupChecks`
- Casque : état de connexion et bouton Connecter, via le même chemin que `Connect…` du menu
- un lien « Configuration complète… » qui ouvre l'assistant en mode révision

Deux accès :

- **depuis le menu** : un item `Réglages rapides…` au-dessus de `Setup…` ;
- **depuis le notch** : un bouton engrenage dans la page secondaire (`HeadphonesTab.swift`,
  qui porte déjà son chevron de retour), lequel active l'application et ouvre le panneau.

Ce panneau ne remplace pas l'assistant : il porte ce qu'on veut rebrancher en dix secondes,
l'assistant porte le parcours complet.

## 4. Persistance et migration

Aucune nouvelle clé `UserDefaults`. Les installations existantes ont `setupDone = true` et
`usageMode` déjà écrits (vérifié sur une machine de développement : les deux clés datent du
premier passage dans l'assistant), donc elles démarrent directement par `startApp()` et ne
revoient jamais l'assistant. Rien à migrer.

## 5. Traductions

Toutes les nouvelles chaînes passent par `tr()` et doivent être ajoutées à
`Client/macos/fr.lproj/Localizable.strings`, sinon `scripts/check_localization.py` fait
échouer `make test`. L'anglais n'a pas de fichier `Localizable.strings` : la clé est le texte
source.

À corriger au passage, trois élisions fautives déjà présentes :

| Clé | Actuel | Correct |
|---|---|---|
| `Overhead Options` | Options de Overhead | Options d'Overhead |
| `Updating Overhead…` | Mise à jour de Overhead… | Mise à jour d'Overhead… |
| `Overhead Setup` | Configuration de Overhead | Configuration d'Overhead |

## 6. Tests

`LogicTests/main.swift` est déjà du Swift et tourne dans `make test`. On y ajoute :

- `SetupFlow.steps(for:)` pour les trois modes ;
- le repli d'étape quand le mode change et fait disparaître l'étape courante ;
- l'idempotence de `startApp()` (drapeau, sans effets de bord réels).

Le reste — fenêtre, aperçu, engrenage du notch — se vérifie à la main : premier lancement sur
un profil neuf (supprimer `setupDone` du plist avec PlistBuddy puis relancer `cfprefsd`,
`defaults` n'étant pas fiable sur ce point), les trois modes, et la réouverture via `Setup…`.

## 7. Fichiers touchés

| Fichier | Nature |
|---|---|
| `Client/macos/AppDelegate.swift` | bifurcation de démarrage, `startApp()` |
| `Client/macos/Setup/SetupWindowController.swift` | `terminé ≠ fermé`, mode onboarding/révision |
| `Client/macos/Setup/SetupView.swift` | éclaté en conteneur + une vue par étape |
| `Client/macos/Setup/SetupFlow.swift` | **nouveau** |
| `Client/macos/Setup/QuickSettingsView.swift` | **nouveau** |
| `Client/macos/Notch/NotchController.swift` | aperçu pilotable hors menu |
| `Client/macos/Notch/HeadphonesTab.swift` | bouton engrenage |
| `Client/macos/HeadphonesMenu.swift` | item `Réglages rapides…` |
| `Client/macos/fr.lproj/Localizable.strings` | nouvelles chaînes + trois élisions |
| `Client/tests/LogicTests/main.swift` | tests de `SetupFlow` |

## 8. Hors périmètre

- Les gestes, l'haptique, les autres lecteurs et la taille détaillée restent dans le menu.
- Aucun rappel, aucune relance de l'assistant après coup.
- Pas de fenêtre Réglages générale à onglets : l'assistant et le panneau rapide suffisent.
- L'écriture de l'égaliseur sur le WH-1000XM6 reste un chantier séparé.
