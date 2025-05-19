FROM alpine:latest

# Installer les paquets nécessaires
RUN apk add --no-cache \
    powershell \
    subversion \
    subversion-tools \
    ncurses-terminfo-base \
    less \
    bash \
    curl

# Créer le dossier de configuration de PowerShell
RUN mkdir -p /root/.config/powershell

# Ajouter une configuration PSReadLine propre
RUN echo 'Set-PSReadLineOption -EditMode Emacs' > /root/.config/powershell/Microsoft.PowerShell_profile.ps1

# Installer le module POSH-SSH
RUN pwsh -Command "Install-Module -Name Posh-SSH -Force -Scope AllUsers"

# Copy des fichier source de l'application
COPY app /app

# Exposition du port
EXPOSE 8080

# Définir PowerShell comme commande par défaut
CMD ["pwsh", "/app/bootstrap.ps1"]

