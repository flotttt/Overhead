# SonyBridge dans l'encoche — spec de design (étape 1)

- **Date :** 2026-09-11
- **Statut :** validé en discussion, à relire avant le plan d'implémentation
- **Casque de référence :** WH-1000XM6 (protocole v2)
- **Découpage :** étape 1 (cette spec) = encoche + onglet Casque + Spotify local ; étape 2 (spec séparée, plus
  tard) = connexion Spotify (SSO) + source Web + changement d'appareil.

## 1. Objectif

Ajouter à SonyBridge une **encoche interactive** en haut de l'écran, dans l'esprit de « Dynamic Island » :
au repos, elle montre discrètement la musique en cours et le mode du casque ; au survol, elle s'ouvre et
permet de piloter la musique (Spotify) et le mode du casque sans ouvrir le menu.

Le menu de la barre des menus reste l'interface complète ; l'encoche est un accès rapide.

## 2. Périmètre

**Inclus (étape 1)**
- L'encoche (panneau au-dessus de la barre des menus), sur l'écran intégré à encoche, ou une pastille
  simulée sur un écran sans encoche.
- Onglet **Musique** : pochette, titre, artiste, barre de progression avec temps écoulé et restant (on peut
  la glisser pour avancer), précédent / lecture-pause / suivant, volume Spotify, appareil (« Ce Mac »).
- Onglet **Casque** : NC / Ambiant / Off, curseur de niveau ambiant, Focus voix.
- La source **Spotify local** : l'app Spotify du Mac, lue et pilotée sans compte.
- L'option « Afficher l'encoche » dans les options de SonyBridge.
- Le français et l'anglais (mécanisme `tr()` existant).

**Exclu de l'étape 1**
- Connexion au compte Spotify (SSO), source Web, changement d'appareil Spotify Connect → étape 2 (§10).
- « J'aime » (ajout aux Titres likés) : non retenu.
- Autres lecteurs (Apple Music, navigateurs…) : l'API privée d'Apple (MediaRemote) est verrouillée depuis
  macOS 15.4, trop fragile.
- Batterie et égaliseur dans l'encoche : restent dans le menu.

## 3. Décisions

| Sujet | Décision | Raison |
|---|---|---|
| Licence | Implémentation originale à partir de la documentation Apple ; aucun code ni visuel copié de boring.notch (GPL-3.0) | SonyBridge reste sous licence MIT ; l'idée d'une encoche n'est pas protégée, le code l'est |
| Disposition ouverte | Onglets **Musique \| Casque** (maquette « B ») | Encoche compacte |
| Ouverture | Au survol, fermeture quand la souris sort | Rapide, comme boring.notch |
| Écran sans encoche | Pastille simulée en haut au centre de l'écran principal | Même comportement partout |
| Source musique | Spotify local (AppleScript + signaux Spotify) à l'étape 1 ; Spotify Web (SSO) à l'étape 2, avec repli local | Utilisable par tous sans compte développeur ; le SSO n'est possible qu'avec un Client ID par utilisateur (§10) |
| Extras Musique | Volume, avancer dans le morceau ; changer d'appareil à l'étape 2 | Choix de l'utilisateur |
| Réglages casque dans l'encoche | Mode NC/Ambiant/Off, niveau ambiant + Focus voix | Choix de l'utilisateur ; le reste est dans le menu |
| Technique | `NSPanel` sans bordure, non activant, contenu SwiftUI (`NSHostingView`) | Pas de vol du focus clavier ; SwiftUI déjà utilisé pour les lignes du menu |

## 4. L'encoche

### 4.1 États au repos

« Musique présente » = Spotify est ouvert **et** son état est lecture ou pause avec un morceau courant.
« Casque connecté » = `HeadphonesModel.connectionState == .connected` (« Connexion… » compte comme non connecté).

| # | Musique | Casque | Au repos |
|---|---|---|---|
| 1 | oui | oui | Pochette à gauche, mode du casque à droite (◉ NC, ◎ Ambiant, ○ Off) |
| 2 | oui | non | Pochette à gauche, petites barres à droite, animées en lecture, figées en pause |
| 3 | non | oui | Icône casque à gauche, mode à droite |
| 4 | non | non | Encoche nue, sans extension. Sur un écran **sans** encoche, la pastille simulée est masquée |

Dans les états 1 à 3, l'encoche s'élargit d'environ 36 pt de chaque côté pour loger ces éléments.
Le survol ouvre l'encoche dans tous les états où elle est visible, y compris l'état 4 sur un écran à encoche.

### 4.2 État ouvert

```
╭──────────────────────────────────╮      Onglet Musique
│        Musique    Casque         │
│  ┌────┐  Midnight City           │
│  │ ♪  │  M83                     │
│  └────┘  ━━━━━━━●────── 1:32 −2:31│  ← barre de progression (glissable)
│         ⏮     ⏸     ⏭           │
│  🔈 ───────●──── 🔊              │  ← volume Spotify
│  🔊 Ce Mac                       │  ← appareil
╰──────────────────────────────────╯

╭──────────────────────────────────╮      Onglet Casque
│        Musique    Casque         │
│   [  NC  | Ambiant |  Off  ]     │  ← choix exclusifs
│   Niveau  ─────●───── 12         │  ← grisé hors mode Ambiant
│   Focus voix              [ ● ]  │  ← grisé hors mode Ambiant
╰──────────────────────────────────╯
```

- Taille ouverte fixe (environ 380 × 190 pt, encoche comprise, à ajuster à la vérification visuelle), la même pour les deux
  onglets : pas de saut de taille en changeant d'onglet.
- Coins inférieurs arrondis ; le haut se confond avec l'encoche.
- **Casque non connecté** : « Non connecté » + bouton « Connecter », qui appelle `HeadphonesModel.connect()`
  (même comportement que « Connecter… » dans le menu). Pendant la connexion : « Connexion… ».
- **Spotify non ouvert** : « Spotify n'est pas ouvert » + bouton « Ouvrir Spotify » (lance l'app).
- **Autorisation refusée** : « SonyBridge n'a pas l'autorisation de contrôler Spotify » + bouton
  « Ouvrir les réglages » (Réglages Système › Confidentialité et sécurité › Automatisation).
- **Spotify ouvert mais rien en cours** (état stopped) : « Rien en cours de lecture ».
- Le curseur de niveau va de 1 à `maxAmbientLevel` (20, ou 19 sur les anciens modèles), comme dans le menu.

### 4.3 Comportement

- **Ouverture** après ~0,15 s de survol ; **fermeture** ~0,4 s après la sortie de la souris. Ces délais sont
  des constantes, testées dans la logique pure (§8).
- **Animation** : ouverture et fermeture en ressort, à partir de la forme de l'encoche ; fondu simple si
  « Réduire les animations » est activé (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`).
- **Focus** : le panneau ne devient jamais la fenêtre active (non activant) ; les clics y fonctionnent
  sans voler le clavier à l'app courante.
- **Zone de clic** : repliée, la fenêtre fait exactement la taille de l'encoche (élargie ou non) ; elle ne
  prend la taille ouverte que pendant l'ouverture. Elle ne bloque donc jamais la barre des menus en dehors
  de l'encoche.
- **Onglet à l'ouverture** : au premier survol de la session, Musique si une musique est présente, sinon
  Casque ; ensuite le dernier onglet choisi (en mémoire seulement, pas enregistré).
- **Écrans** : l'écran intégré à encoche s'il existe, sinon l'écran principal avec la pastille simulée.
  L'encoche se replace à chaque changement d'écrans (`NSApplication.didChangeScreenParametersNotification`) :
  écran branché/débranché, capot fermé, résolution changée.
- **Bureaux et plein écran** : visible sur tous les bureaux et par-dessus les apps en plein écran.
- **Option** « Afficher l'encoche » décochée : le panneau est retiré ; aucune lecture Spotify n'est faite.
- **Synchronisation** avec le menu : les deux lisent le même `HeadphonesModel` ; un changement de mode dans
  l'encoche apparaît aussitôt dans le menu et l'icône, et inversement.

## 5. Architecture

### 5.1 Fichiers (`Client/macos/`)

Nouveaux dossiers `Notch/` et `Music/`. Les fichiers marqués **pur** n'importent que Foundation : ils sont
compilés dans `LogicTests`.

| Fichier | Rôle | Dépend de |
|---|---|---|
| `Notch/NotchGeometry.swift` | **Pur.** À partir du cadre de l'écran, de `safeAreaInsets.top` et des zones `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (passés en valeurs), calcule le rectangle de l'encoche, sa version élargie, le rectangle ouvert, ou la pastille simulée | — |
| `Notch/NotchContent.swift` | **Pur.** Choisit l'état au repos (§4.1) à partir de « musique présente » et « casque connecté », et l'onglet à l'ouverture ; contient les délais d'ouverture/fermeture | — |
| `Notch/NotchPanel.swift` | `NSPanel` sans bordure, transparent, non activant, niveau au-dessus de la barre des menus, présent sur tous les bureaux et en plein écran | AppKit |
| `Notch/NotchController.swift` | Possède le panneau ; choisit l'écran ; suit les changements d'écrans ; gère le survol (zone de suivi + délais) et la taille du panneau ; suit `AppSettings.showNotch` | `NotchPanel`, `NotchGeometry`, `NotchContent`, `HeadphonesModel`, `MusicController`, `AppSettings` |
| `Notch/NotchView.swift` | Vue SwiftUI racine : état au repos, état ouvert avec les onglets | `MusicTab`, `HeadphonesTab` |
| `Notch/MusicTab.swift` | Onglet Musique (§4.2) | `MusicController` |
| `Notch/HeadphonesTab.swift` | Onglet Casque (§4.2) ; appelle `setMode` / `setLevel(_:final:)` / `setFocusOnVoice` / `connect` du modèle | `HeadphonesModel` |
| `Music/NowPlaying.swift` | **Pur.** Structure : titre, artiste, album, identifiant du morceau, URL de la pochette, durée, position + date de cette position, lecture/pause, volume, nom de l'appareil, capacités (`canSeek`, `canSetVolume`, `canChangeDevice`) | — |
| `Music/PlaybackClock.swift` | **Pur.** Position affichée à un instant donné : avance pendant la lecture, figée en pause, bornée à la durée | `NowPlaying` |
| `Music/SpotifyPlaybackInfo.swift` | **Pur.** Transforme le `userInfo` du signal Spotify en `NowPlaying` (durée en ms → s, champs manquants, état « Stopped ») | `NowPlaying` |
| `Music/MusicSource.swift` | Protocole commun : état publié (`NowPlaying?` + état de la source : non ouvert / autorisation refusée / prêt), `playPause`, `next`, `previous`, `seek(to:)`, `setVolume(_:)`, `refresh()` | `NowPlaying` |
| `Music/SpotifyLocalSource.swift` | Implémentation locale (§6) | `MusicSource`, `SpotifyPlaybackInfo`, AppKit |
| `Music/MusicController.swift` | `ObservableObject` lu par l'encoche : expose l'état de la source active, la pochette téléchargée, et relaie les commandes (avec `SendThrottle` pour le volume et la position). Étape 1 : une seule source, la locale | `MusicSource`, `SendThrottle` |

**Fichiers modifiés**
- `AppSettings.swift` : `showNotch` (`UserDefaults`, **activé** par défaut).
- `AppDelegate.swift` : crée `MusicController` et `NotchController`.
- `HeadphonesMenu.swift` : case « Afficher l'encoche » dans « Options de SonyBridge ».
- `scripts/build.sh` : ajoute `Notch/*.swift` et `Music/*.swift` aux sources Swift.
- `scripts/test.sh` : compile les fichiers purs avec `LogicTests`.
- `Client/tests/LogicTests/main.swift` : nouveaux tests (§8).
- `fr.lproj/Localizable.strings` : nouveaux textes.
- `SonyHeadphonesClient.entitlements` et `info.plist` (§5.2).

### 5.2 Bac à sable et autorisations

- `com.apple.security.temporary-exception.apple-events` = `["com.spotify.client"]` : envoyer des Apple Events
  à Spotify depuis l'app en bac à sable. (Si le runtime renforcé est activé un jour, il faudra aussi
  `com.apple.security.automation.apple-events`.)
- `com.apple.security.network.client` : télécharger la pochette (et, à l'étape 2, parler à l'API Spotify).
- `info.plist` : `NSAppleEventsUsageDescription`, texte affiché par macOS à la première demande.

### 5.3 Flux de données

```
Spotify (app du Mac) ──signal PlaybackStateChanged──▶ SpotifyLocalSource ──NowPlaying──▶ MusicController ──▶ NotchView
          ▲                                                 │                                   │
          └──────────── Apple Events (lecture, volume…) ◀───┴──────────── commandes ◀───────────┘

HeadphonesModel (existant) ◀──── setMode / setLevel / setFocusOnVoice ──── HeadphonesTab
          └──────── @Published mode, niveau, voix, connexion ──────────▶ NotchView + menu
```

## 6. Source Spotify locale

### 6.1 Lecture de l'état

- **Signal** `com.spotify.client.PlaybackStateChanged` (`DistributedNotificationCenter`) : Spotify l'émet à
  chaque changement de morceau, lecture ou pause. Si le signal contient ses informations (`userInfo` :
  titre, artiste, album, durée, position, état), `SpotifyPlaybackInfo` les décode ; sinon (par exemple si le
  bac à sable les retire), le signal sert seulement de déclencheur et on relit l'état par Apple Events.
- **Relecture par Apple Events** (`player state`, `current track` : nom, artiste, album, id, durée,
  `artwork url` ; `player position` ; `sound volume`) :
  - au lancement de SonyBridge si Spotify est déjà ouvert ;
  - quand Spotify s'ouvre (`NSWorkspace.didLaunchApplicationNotification`) ;
  - toutes les 5 s **uniquement quand l'encoche est ouverte** (le volume ne déclenche pas de signal) ;
  - juste après une commande de position ou de volume.
- **Position** : `PlaybackClock` calcule la position affichée à partir de la dernière position connue et de
  l'heure ; l'interface se redessine environ une fois par seconde **seulement quand l'encoche est ouverte**.
- **Pochette** : téléchargée depuis `artwork url` (`URLSession`), gardée en mémoire pour les derniers morceaux.
- Spotify quitte (`NSWorkspace.didTerminateApplicationNotification`) → état « non ouvert », `NowPlaying` vidé.

### 6.2 Commandes

- `playpause`, `next track`, `previous track`, `set player position`, `set sound volume` (volume de Spotify,
  0–100, pas celui du Mac).
- Volume et position : la valeur affichée change tout de suite ; l'envoi passe par `SendThrottle`
  (au plus une commande par 150 ms pendant qu'on glisse, la valeur finale toujours envoyée).
- Les Apple Events partent d'une file série en arrière-plan, avec un délai maximal de 2 s : l'interface ne se
  fige jamais si Spotify ne répond pas.

### 6.3 Protections et erreurs

- **Aucun Apple Event n'est envoyé si Spotify n'est pas ouvert** (vérifié avec
  `NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")`) : un Apple Event
  vers une app fermée la lancerait. Seul le bouton « Ouvrir Spotify » lance l'app.
- **Autorisation** : la première commande ou relecture déclenche la demande de macOS. Si elle est refusée
  (`errAEEventNotPermitted`, -1743), la source passe à l'état « autorisation refusée » (§4.2) et arrête ses
  relectures ; elle réessaie une seule fois à chaque ouverture de l'encoche (macOS ne redemande pas, l'échec
  est immédiat), pour voir si l'autorisation a été accordée entre-temps dans les réglages.
- **Échec ou délai dépassé** : on garde le dernier état connu et on relit au prochain signal ; aucune
  alerte, les erreurs sont seulement écrites dans le journal (stderr).

## 7. Réglages et traductions

- « Options de SonyBridge » gagne une case **Afficher l'encoche** (activée par défaut).
- Tous les nouveaux textes passent par `tr()` et ont leur traduction dans `fr.lproj/Localizable.strings` ;
  `make test` le vérifie (`check_localization.py` parcourt déjà tous les `.swift` sous `Client/macos/`).

## 8. Tests

**Automatiques** (ajoutés à `LogicTests`, lancés par `make test`)
- `NotchGeometry` : écran avec encoche → rectangle de l'encoche, version élargie et rectangle ouvert centrés
  sous le haut de l'écran ; écran sans encoche → pastille centrée ; cas limites (zones auxiliaires absentes,
  écran décalé dans l'espace global).
- `NotchContent` : les 4 états au repos ; onglet à l'ouverture (premier survol puis dernier onglet) ; délais.
- `PlaybackClock` : avance en lecture, figée en pause, bornée à la durée, remise à zéro au changement de morceau.
- `SpotifyPlaybackInfo` : décodage complet, champs manquants, durée en ms, état « Stopped » → pas de musique.

**Manuels** (par l'utilisateur, sur son Mac et son WH-1000XM6)
1. Survol : ouverture, fermeture, pas de clignotement ; l'app active garde le clavier.
2. Les 4 états au repos.
3. Onglet Casque : changer de mode → le casque change, le menu et l'icône suivent ; bouton NC du casque →
   l'encoche suit.
4. Onglet Musique : lecture/pause, suivant, précédent, glisser la position, volume ; changer de morceau dans
   Spotify → l'encoche suit.
5. Demande d'autorisation Spotify ; refus → message et bouton des réglages.
6. Spotify fermé → message et bouton « Ouvrir Spotify » ; SonyBridge ne relance jamais Spotify tout seul.
7. Écran externe, capot fermé, rebranchement : l'encoche se replace (pastille simulée sur l'écran externe).
8. Option « Afficher l'encoche » décochée → plus d'encoche ; recochée → elle revient.

## 9. Risques

- **Autorisation redemandée après chaque `make`** : macOS rattache l'autorisation d'automatisation à la
  signature de l'app, qui change à chaque build ad hoc. Gênant en développement, pas pour l'app installée.
- **API Spotify locale non documentée** : le signal et le dictionnaire AppleScript de Spotify n'ont pas de
  garantie officielle (stables depuis des années). En cas de casse, seul l'onglet Musique local est touché.
- **`userInfo` du signal en bac à sable** : non garanti ; le design relit l'état par Apple Events si besoin (§6.1).
- **Extension au repos** : les ~36 pt de chaque côté de l'encoche peuvent recouvrir un élément de la barre
  des menus collé à l'encoche ; à vérifier visuellement, largeur ajustable.
- **Pastille simulée** : elle recouvre le centre de la barre des menus sur un écran sans encoche (zone
  habituellement vide) ; masquée quand il n'y a rien à afficher.

## 10. Étape 2 (aperçu, spec séparée)

Connexion au compte Spotify (Authorization Code + PKCE, sans secret ; jetons dans le Trousseau), source
`SpotifyWebSource` (`/me/player`, interrogé pendant la lecture), changement d'appareil (Spotify Connect),
fenêtre « Spotify… » pour saisir le Client ID. `MusicController` choisira la source Web si l'utilisateur est
connecté, sinon la locale.

Contraintes Spotify vérifiées le 2026-09-11 :
- une app en mode développement accepte **5 utilisateurs** au plus, ajoutés à la main, et son propriétaire
  doit avoir **Premium** (depuis février 2026) ;
- le quota étendu est réservé aux entreprises (≥ 250 000 utilisateurs actifs par mois) depuis mai 2025 ;
- les commandes de lecture restent disponibles en mode développement ;
- adresse de retour : `http://127.0.0.1:<port>` ou un schéma personnalisé (`localhost` refusé).

Conséquence : pour un repo public, **chaque utilisateur crée sa propre app développeur Spotify** et colle son
Client ID dans SonyBridge ; sans cela, l'encoche reste sur la source locale.

Sources : [quotas Spotify](https://developer.spotify.com/documentation/web-api/concepts/quota-modes),
[migration février 2026](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide),
[adresses de retour](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri).

## 11. Ordre de construction (indicatif, le plan fait foi)

1. Logique pure + tests (`NotchGeometry`, `NotchContent`, `NowPlaying`, `PlaybackClock`, `SpotifyPlaybackInfo`).
2. Panneau + contrôleur : l'encoche apparaît au bon endroit, s'ouvre et se ferme au survol, suit les écrans.
3. Onglet Casque branché sur `HeadphonesModel` + option « Afficher l'encoche ».
4. Source Spotify locale + `MusicController` + onglet Musique + autorisations.
5. États au repos complets, animations, vérification visuelle et matérielle.

## 12. Changements pendant l'implémentation (2026-09-17)

Décidés avec l'utilisateur sur l'app en marche ; ils remplacent §4.2 et une partie de §4.3.

- **Plus d'onglets.** L'encoche ouverte est un lecteur façon « Dynamic Island » (maquette fournie par
  l'utilisateur) : pochette, titre, artiste et petites barres à la couleur de la pochette ; temps écoulé, barre
  plate, durée totale ; boutons 🎧 ⏮ ⏯ ⏭ 🔀 🔊. 🎧 fait glisser le lecteur vers le panneau Casque (‹ retour) ;
  🔊 remplace la progression par la barre de volume Spotify, repliée après 4 s sans action. Le lecteur
  s'ouvre sur la page choisie en dernier (première ouverture : Musique s'il y a une musique, sinon Casque).
- **Lecture aléatoire** : ajoutée puis retirée (le bouton décentrait lecture/pause). « J'aime » n'existe pas
  en local (étape 2).
- **Taille ouverte 300 × 166 pt** ; coins du haut évasés vers la barre des menus.
- **Aucun contrôle AppKit dans l'encoche** (sélecteur segmenté, `Slider`, `Toggle`, bouton bordé) : ils
  ignorent l'échelle et le découpage SwiftUI et débordaient à l'ouverture, au changement de page et à la
  fermeture. Remplacés par `ModePicker`, `FlatSlider`, `NotchSwitch`, `NotchPillButton`.
- **Fenêtre de taille fixe** : le panneau garde la taille ouverte, seule la forme s'anime ; fermé, il laisse
  passer les clics (`ignoresMouseEvents`) et le survol suit la position du pointeur (moniteurs d'événements
  global et local). Redimensionner la fenêtre affichait une image de contenu décalé.
- **Animations** (`NotchMotion`) : le contenu grandit et rétrécit avec la forme (même ressort, sans flou) ;
  il reste monté pendant la fermeture puis est retiré ; la bande du repos a une largeur fixe et revient en
  fondu. Vérifié par captures d'écran à 60/120 images par seconde.
