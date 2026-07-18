# 📦 NetBackup-PowerShell

NetBackup-PowerShell est un projet PowerShell embarqué dans un conteneur Docker léger basé sur Alpine, permettant d'automatiser la récupération, la sauvegarde et le suivi de version des configurations d'équipements réseau (switchs, routeurs, etc.).

---

## 🚀 Fonctionnalités principales

- 🔐 Authentification sécurisée via fichier `credentials.xml` généré automatiquement
- 📡 Connexion SSH aux équipements (via Posh-SSH)
- 📝 Exécution de commandes personnalisées pour chaque équipement
- 💾 Sauvegarde des configurations dans `/app/NetworkBackups/configs`
- 📁 Suivi des versions avec `svn`
- 🌐 Interface web locale sur le port `8080` pour visualiser les configurations et leurs révisions, protégée par un login admin
- 🛠️ Espace admin (`/admin`) : gestion de `devices.json`, consultation des logs de backup, déclenchement d'un backup manuel
- 📆 Tâche cron intégrée pour exécuter les backups toutes les heures

---

## 🧰 Structure du projet

```text
.
├── app
│   ├── Backup-Network.ps1        # Script principal de sauvegarde
│   ├── Credentials.ps1           # Génération auto des credentials
│   ├── devices.json              # Liste des équipements à sauvegarder
│   ├── NetworkBackups/          # Dossier de backup SVN
│   ├── assets/
│   │   ├── styles/style.css     # Style de l'interface Web
│   │   ├── scripts/app.js       # Comportement JS de l'interface Web
│   │   └── img/                 # banner.png, favicon.ico, logo.png
│   ├── src/
│   │   ├── Handle-Conf.ps1       # Rendu des configs (/conf)
│   │   ├── Handle-Diff.ps1       # Rendu des diffs (/diff)
│   │   ├── Handle-Auth.ps1       # Sessions, login/logout
│   │   ├── Handle-Admin.ps1      # Espace admin (/admin)
│   │   └── Utils.ps1             # Fonctions utilitaires
│   ├── Web.ps1                   # Serveur HTTP (interface web)
│   └── bootstrap.ps1            # Script de démarrage global
└── Dockerfile
```

---

## ⚙️ Utilisation

### 1. 🔨 Construction de l’image Docker
```bash
docker build -t bckp_posh-alpine .
```

### 2. ▶️ Lancement du conteneur
```bash
docker run --env-file .env -p 8080:8080 -v ./NetworkBackups:/app/NetworkBackups -v ./devices.json:/app/devices.json bckp_posh-alpine
```

fichier .env exemple :
```bash
DEVICE_USER=admin
DEVICE_PASSWORD=changeme
ADMIN_USER=admin
ADMIN_PASSWORD=changeme
WEB_PREFIX=http
WEB_ADDR=127.0.0.1
PUB_URL=http://localhost:8080
WEB_PORT=8080
```

⚠️ `ADMIN_USER`/`ADMIN_PASSWORD` sont désormais **obligatoires** : toute l'interface web (`/conf`, `/diff`, `/admin`) est protégée par un login, sans ces variables la connexion admin est impossible.

### 3. 📝 Vérifiez les logs
```bash
docker exec -it <container_id> tail -f /var/log/backup.log
```

La console du conteneur (`docker logs`) ne montre que l'essentiel (équipement traité, réussite/échec, résumé). Le détail complet (connexions SSH, lectures, tailles...) est écrit dans `/var/log/backup.log` par les runs cron et les backups manuels, exécutés avec `-Verbose`.

Cela effectue :
- Génération du fichier `credentials.xml`
- Lancement du script de backup initial (`Backup-Network.ps1`)
- Planification d’un cron pour l’exécuter toutes les heures
- Lancement de l’interface Web sur `http://0.0.0.0:8080`

---

## 🌐 Interface Web

Accessible via : [http://localhost:8080](http://localhost:8080) — redirige vers `/login` tant qu'aucune session n'est ouverte.

L'interface reprend les codes d'un panneau d'administration moderne (inspiration Cloudflare) : navigation latérale (Sauvegardes / Administration), barre supérieure avec titre de page, contenu en cartes — le tout aux couleurs bleues du logo Aresia.

Fonctionnalités (`/conf`, après connexion) :
- Liste des équipements sauvegardés
- Visualisation des configurations actuelles
- Sélecteur de révisions SVN
- Filtre pour les équipements (selectionner par site ou par os)
- Afficher seulement les différences entre une version et la plus actuelle

### 🔑 Authentification et espace admin

- `/login` : formulaire de connexion (identifiants `ADMIN_USER`/`ADMIN_PASSWORD`), pose un cookie de session.
- `/logout` : invalide la session en cours.
- `/admin` : dashboard donnant accès à :
  - `/admin/devices` : gestion des équipements via un formulaire dynamique (ajout, modification, suppression). Les champs Site et Type proposent les valeurs existantes plus une option « Nouveau… ». Les changements sont appliqués côté navigateur puis persistés d'un bloc via « Enregistrer les modifications » (une sauvegarde `devices.json.bak` est faite avant chaque écriture)
  - `/admin/logs` : consulter les 200 dernières lignes de `/var/log/backup.log`
  - déclenchement d'un backup manuel (lance `Backup-Network.ps1` en arrière-plan)

Sans session valide, toutes les routes (sauf `/login`) redirigent vers la page de connexion.

### Capture d'écran de l'interface

![Interface Config NetBackup-PowerShell](./img/interface_config.png)

*Exemple de l'interface de sauvegarde avec affichage d'une configuration d'équipement réseau*

![Interface Diff NetBackup-PowerShell](./img/interface_diff.png)

*Exemple de l'interface de sauvegarde avec affichage des différences d'un équipement réseau*

---

## 📝 Fichier `devices.json` exemple

```json
{
  "devices": [
    {
      "Name": "SW_PROD_1",
      "IP": "192.168.2.1",
      "Type": "comware",
      "Site": "Paris01",
      "Commands": [
        "screen-length disable\n display current-configuration"
      ]
    },
    {
      "Name": "SW_PROD_2",
      "IP": "192.168.2.2",
      "Type": "aruba",
      "Site": "Paris01",
      "Commands": [
        "no page\n show running-config"
      ]
    }
  ]
}
```

---

## 🛠️ Dépendances

- PowerShell Core (via Alpine)
- `Posh-SSH`
- `subversion` & `svnadmin`
- `cron`

---

## 📬 Contact
Projet maintenu par [Alternants DSI Aresia VLT] 
