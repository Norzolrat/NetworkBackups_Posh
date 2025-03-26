# 📦 NetBackup-PowerShell

NetBackup-PowerShell est un projet PowerShell embarqué dans un conteneur Docker léger basé sur Alpine, permettant d'automatiser la récupération, la sauvegarde et le suivi de version des configurations d'équipements réseau (switchs, routeurs, etc.).

---

## 🚀 Fonctionnalités principales

- 🔐 Authentification sécurisée via fichier `credentials.xml` généré automatiquement
- 📡 Connexion SSH aux équipements (via Posh-SSH)
- 📝 Exécution de commandes personnalisées pour chaque équipement
- 💾 Sauvegarde des configurations dans `/app/NetworkBackups/configs`
- 📁 Suivi des versions avec `svn`
- 🌐 Interface web locale sur le port `8080` pour visualiser les configurations et leurs révisions
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
│   ├── styles/style.css         # Style de l’interface Web
│   ├── src/
│   │   ├── Handle-Conf.ps1       # Logique de rendu des configs
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
docker run -e DEVICE_USER="admin" -e DEVICE_PASSWORD="changeme" -p 8080:8080 -v ./NetworkBackups:/app/NetworkBackups -v ./devices.json /app/devices.json bckp_posh-alpine
```

### 3. 📝 Vérifiez les logs
```bash
docker exec -it <container_id> tail -f /var/log/backup.log
```

Cela effectue :
- Génération du fichier `credentials.xml`
- Lancement du script de backup initial (`Backup-Network.ps1`)
- Planification d’un cron pour l’exécuter toutes les heures
- Lancement de l’interface Web sur `http://0.0.0.0:8080`

---

## 🌐 Interface Web

Accessible via : [http://localhost:8080](http://localhost:8080)

Fonctionnalités :
- Liste des équipements sauvegardés
- Visualisation des configurations actuelles
- Sélecteur de révisions SVN

- #TODO Filtre pour les équipement (selectionner par site ou par os)
- #TODO Afficher seulement les différences entre une version et la plus actuelle
- #TODO Améliorer l'interface

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
