// Changement de révision sans rechargement : le contenu est récupéré via /api/conf
function showRevision(select) {
    const section = select.closest('.revision-section');
    const device = section.closest('.tabcontent').id;
    const rev = select.value;
    localStorage.setItem("storage_" + device, rev || "latest");

    const pre = document.getElementById("cnt_" + device).querySelector('pre');
    const status = section.querySelector('.rev-status');
    if (status) {
        status.style.display = "";
        status.textContent = "Chargement…";
    }

    fetch("/api/conf?device=" + encodeURIComponent(device) + (rev ? "&rev=" + encodeURIComponent(rev) : ""))
        .then(response => {
            if (!response.ok) throw new Error("HTTP " + response.status);
            return response.text();
        })
        .then(text => {
            pre.textContent = text;
            pre.dataset.rev = rev || "latest";
            if (status) status.style.display = "none";
        })
        .catch(err => {
            if (status) status.textContent = "Erreur de chargement (" + err.message + ")";
        });
}

function diffRevision(button) {
    const tab = button.closest('.tabcontent');
    const select = tab.querySelector('#revisionSelect');
    const rev = select ? select.value : "";
    if (!rev) {
        alert("Sélectionnez d'abord une révision à comparer avec la version actuelle.");
        return;
    }
    saveConfig();
    window.location.href = "/diff?device=" + encodeURIComponent(tab.id) + "&rev=" + encodeURIComponent(rev);
}

// Les filtres ne touchent qu'à la liste des onglets : la config affichée reste
// celle sélectionnée, et si elle sort du filtre on invite à en choisir une autre.
function filterConfigs() {
    const siteFilter = document.getElementById("filterSite").value;
    const typeFilter = document.getElementById("filterType").value;

    const visibleIds = [];
    document.querySelectorAll(".tablinks").forEach(button => {
        const target = button.dataset.target || button.textContent.trim();
        const tab = document.getElementById(target);
        const matches = tab &&
            (siteFilter === "all" || tab.classList.contains(siteFilter)) &&
            (typeFilter === "all" || tab.classList.contains(typeFilter));
        button.style.display = matches ? "" : "none";
        if (matches) visibleIds.push(target);
    });

    const activeButton = document.querySelector(".tablinks.active");
    const activeId = activeButton ? (activeButton.dataset.target || activeButton.textContent.trim()) : null;

    if (activeId && visibleIds.includes(activeId)) {
        setNoSelection(false);
        return;
    }

    // La config active ne correspond plus au filtre : on la masque sans en ouvrir une autre
    document.querySelectorAll(".tabcontent").forEach(tab => tab.style.display = "none");
    if (activeButton) activeButton.className = activeButton.className.replace(" active", "");
    setNoSelection(true);
}

function setNoSelection(show) {
    const placeholder = document.getElementById("noSelection");
    if (placeholder) placeholder.style.display = show ? "" : "none";
}

function initPageState() {
    const activeTabName = localStorage.getItem("activeTab");

    if (activeTabName) {
        const tablinks = document.getElementsByClassName("tablinks");
        let foundTab = false;

        Array.from(tablinks).forEach(link => {
            if ((link.dataset.target || link.textContent.trim()) === activeTabName) {
                link.click();
                foundTab = true;
            }
        });

        if (!foundTab && tablinks.length > 0) {
            tablinks[0].click();
        }
    } else if (document.getElementsByClassName("tablinks").length > 0) {
        document.getElementsByClassName("tablinks")[0].click();
    }

    const tabcontents = document.getElementsByClassName("tabcontent");
    Array.from(tabcontents).forEach(tab => {
        const configName = tab.id;
        const savedRevision = localStorage.getItem("storage_" + configName);

        if (savedRevision && savedRevision !== "latest") {
            const revisionSelect = tab.querySelector('#revisionSelect');
            if (revisionSelect) {
                revisionSelect.value = savedRevision;
            }
        }
    });
}

function saveActiveTab() {
    let activeTab = document.querySelector(".tablinks.active");
    if (activeTab) {
        let tabName = activeTab.dataset.target || activeTab.textContent.trim();
        localStorage.setItem("activeTab", tabName);
    }
}

function getActiveTab() {
    return localStorage.getItem("activeTab");
}

function saveRevision() {
    document.querySelectorAll(".tabcontent").forEach(tab => {
        const select = tab.querySelector("#revisionSelect");
        if (select) {
            localStorage.setItem("storage_" + tab.id, select.value || "latest");
        }
    });
}

function getRevision(sectionName) {
    return localStorage.getItem("storage_" + sectionName);
}

function saveConfig() {
    saveActiveTab();
    saveRevision();
}

function openConfig(evt, configName) {
    const tabcontents = document.getElementsByClassName("tabcontent");
    Array.from(tabcontents).forEach(tab => tab.style.display = "none");

    const tablinks = document.getElementsByClassName("tablinks");
    Array.from(tablinks).forEach(link => link.className = link.className.replace(" active", ""));

    const selectedTab = document.getElementById(configName);
    if (selectedTab) {
        selectedTab.style.display = "block";
        evt.currentTarget.className += " active";
        setNoSelection(false);

        localStorage.setItem("activeTab", configName);

        const revisionSelect = selectedTab.querySelector('#revisionSelect');
        if (revisionSelect) {
            const savedRevision = localStorage.getItem("storage_" + configName);
            if (savedRevision && savedRevision !== "latest") {
                revisionSelect.value = savedRevision;
            }
            // Si le contenu affiché ne correspond pas à la révision sélectionnée, on le charge
            const pre = selectedTab.querySelector('.content pre');
            const wanted = revisionSelect.value || "latest";
            if (pre && (pre.dataset.rev || "latest") !== wanted) {
                showRevision(revisionSelect);
            }
        }
    }
}

/* ===================================================================
   Gestion des équipements (/admin/devices)
   État client : deviceState est modifié par le formulaire et la liste,
   puis sérialisé en JSON complet lors de l'enregistrement (POST).
   =================================================================== */
let deviceState = null;
let deviceEditIndex = null;
let devicesDirty = false;
let connectorNames = [];

function initDeviceManager() {
    const dataEl = document.getElementById("devicesData");
    if (!dataEl) return;

    try {
        deviceState = JSON.parse(dataEl.textContent);
    } catch (e) {
        deviceState = { devices: [] };
    }
    if (!Array.isArray(deviceState.devices)) deviceState.devices = [];

    const connectorsEl = document.getElementById("connectorsData");
    if (connectorsEl) {
        try {
            connectorNames = JSON.parse(connectorsEl.textContent) || [];
        } catch (e) {
            connectorNames = [];
        }
        if (!Array.isArray(connectorNames)) connectorNames = [connectorNames];
    }

    renderDevices();

    window.addEventListener("beforeunload", (e) => {
        if (devicesDirty) {
            e.preventDefault();
            e.returnValue = "";
        }
    });
}

function collectDeviceValues(field) {
    const values = [];
    deviceState.devices.forEach(d => {
        const v = (d[field] || "").trim();
        if (v && !values.includes(v)) values.push(v);
    });
    return values.sort((a, b) => a.localeCompare(b));
}

function buildCombo(selectId, inputId, values, current) {
    const select = document.getElementById(selectId);
    const input = document.getElementById(inputId);
    select.innerHTML = "";
    values.forEach(v => select.appendChild(new Option(v, v)));
    select.appendChild(new Option("➕ Nouveau…", "__new__"));

    if (current && values.includes(current)) {
        select.value = current;
    } else if (values.length === 0) {
        select.value = "__new__";
    }

    const sync = () => {
        const isNew = select.value === "__new__";
        input.style.display = isNew ? "" : "none";
        if (isNew && document.activeElement === select) input.focus();
    };
    select.onchange = sync;
    sync();
}

function comboValue(selectId, inputId) {
    const select = document.getElementById(selectId);
    return select.value === "__new__"
        ? document.getElementById(inputId).value.trim()
        : select.value;
}

function markDevicesDirty() {
    devicesDirty = true;
    document.getElementById("dirtyIndicator").style.visibility = "visible";
}

function renderDevices() {
    const list = document.getElementById("deviceList");
    list.innerHTML = "";

    document.getElementById("deviceCount").textContent = deviceState.devices.length;

    if (deviceState.devices.length === 0) {
        const empty = document.createElement("div");
        empty.className = "card empty-state";
        empty.textContent = "Aucun équipement pour le moment — ajoutez-en un via le formulaire ci-dessus.";
        list.appendChild(empty);
    }

    deviceState.devices.forEach((device, index) => {
        const row = document.createElement("div");
        row.className = "card device-row" + (index === deviceEditIndex ? " editing" : "");

        const main = document.createElement("div");
        main.className = "device-row-main";

        const title = document.createElement("div");
        title.className = "device-row-title";
        const name = document.createElement("strong");
        name.textContent = device.Name || "(sans nom)";
        const ip = document.createElement("span");
        ip.className = "device-ip";
        ip.textContent = device.IP || "";
        title.appendChild(name);
        title.appendChild(ip);

        const badges = document.createElement("div");
        badges.className = "device-row-badges";
        if (device.Site) {
            const site = document.createElement("span");
            site.className = "badge";
            site.textContent = device.Site;
            badges.appendChild(site);
        }
        if (device.Type) {
            const type = document.createElement("span");
            type.className = "badge badge-muted";
            type.textContent = device.Type;
            badges.appendChild(type);
        }
        const connectorBadge = document.createElement("span");
        if (device.Connector) {
            connectorBadge.className = "badge badge-outline";
            connectorBadge.textContent = "🔑 " + device.Connector;
        } else {
            connectorBadge.className = "badge badge-alert";
            connectorBadge.textContent = "⚠ aucun connecteur";
        }
        badges.appendChild(connectorBadge);

        const cmds = document.createElement("div");
        cmds.className = "device-row-cmds";
        const commands = Array.isArray(device.Commands) ? device.Commands : [];
        cmds.textContent = commands.map(c => String(c).replace(/\n/g, "\\n")).join("  ·  ") || "Aucune commande";

        main.appendChild(title);
        main.appendChild(badges);
        main.appendChild(cmds);

        const actions = document.createElement("div");
        actions.className = "device-row-actions";
        const editBtn = document.createElement("button");
        editBtn.className = "btn btn-secondary btn-sm";
        editBtn.textContent = "Modifier";
        editBtn.onclick = () => editDevice(index);
        const deleteBtn = document.createElement("button");
        deleteBtn.className = "btn btn-danger btn-sm";
        deleteBtn.textContent = "Supprimer";
        deleteBtn.onclick = () => deleteDevice(index);
        actions.appendChild(editBtn);
        actions.appendChild(deleteBtn);

        row.appendChild(main);
        row.appendChild(actions);
        list.appendChild(row);
    });

    const currentDevice = deviceEditIndex !== null ? deviceState.devices[deviceEditIndex] : null;
    buildCombo("devSite", "devSiteNew", collectDeviceValues("Site"), currentDevice ? currentDevice.Site : document.getElementById("devSite").value);
    buildCombo("devType", "devTypeNew", collectDeviceValues("Type"), currentDevice ? currentDevice.Type : document.getElementById("devType").value);
    buildConnectorSelect(currentDevice ? currentDevice.Connector : document.getElementById("devConnector").value);

    document.getElementById("devicesPreview").textContent = JSON.stringify(deviceState, null, 2);
}

function buildConnectorSelect(current) {
    const select = document.getElementById("devConnector");
    if (!select) return;
    select.innerHTML = "";
    select.appendChild(new Option("— Sélectionner un connecteur —", ""));
    connectorNames.forEach(n => select.appendChild(new Option(n, n)));
    // Connecteur assigné mais disparu du store : on l'affiche quand même pour ne pas le perdre en silence
    if (current && !connectorNames.includes(current)) {
        select.appendChild(new Option(current + " (introuvable)", current));
    }
    select.value = current || "";
}

function showDeviceFormError(message) {
    const el = document.getElementById("deviceFormError");
    el.textContent = message;
    el.style.display = message ? "" : "none";
}

function submitDeviceForm() {
    const name = document.getElementById("devName").value.trim();
    const ip = document.getElementById("devIp").value.trim();
    const site = comboValue("devSite", "devSiteNew");
    const type = comboValue("devType", "devTypeNew");
    const connector = document.getElementById("devConnector").value;
    const commands = document.getElementById("devCommands").value
        .split("\n")
        .map(line => line.trim())
        .filter(line => line.length > 0)
        .map(line => line.replace(/\\n/g, "\n"));

    if (!name) return showDeviceFormError("Le nom est obligatoire.");
    if (!ip) return showDeviceFormError("L'adresse IP est obligatoire.");
    if (!site) return showDeviceFormError("Choisissez un site ou saisissez-en un nouveau.");
    if (!type) return showDeviceFormError("Choisissez un type ou saisissez-en un nouveau.");
    if (!connector) return showDeviceFormError("Choisissez un connecteur (créez-en un dans la page Connecteurs si besoin).");
    if (commands.length === 0) return showDeviceFormError("Au moins une commande est nécessaire.");

    const duplicate = deviceState.devices.findIndex((d, i) => d.Name === name && i !== deviceEditIndex);
    if (duplicate !== -1) return showDeviceFormError("Un équipement porte déjà ce nom.");

    // Conserve les éventuelles propriétés inconnues de l'équipement d'origine
    const base = deviceEditIndex !== null ? deviceState.devices[deviceEditIndex] : {};
    const updated = Object.assign({}, base, {
        Name: name,
        IP: ip,
        Type: type,
        Site: site,
        Commands: commands
    });
    if (connector) {
        updated.Connector = connector;
    } else {
        delete updated.Connector;
    }

    if (deviceEditIndex !== null) {
        deviceState.devices[deviceEditIndex] = updated;
    } else {
        deviceState.devices.push(updated);
    }

    markDevicesDirty();
    cancelDeviceEdit();
}

function editDevice(index) {
    const device = deviceState.devices[index];
    deviceEditIndex = index;

    document.getElementById("devName").value = device.Name || "";
    document.getElementById("devIp").value = device.IP || "";
    const commands = Array.isArray(device.Commands) ? device.Commands : [];
    document.getElementById("devCommands").value = commands.map(c => String(c).replace(/\n/g, "\\n")).join("\n");

    document.getElementById("deviceFormTitle").textContent = "Modifier " + (device.Name || "l'équipement");
    document.getElementById("deviceFormSubmit").textContent = "Mettre à jour";
    document.getElementById("deviceFormCancel").style.display = "";
    showDeviceFormError("");

    renderDevices();
    document.getElementById("deviceFormCard").scrollIntoView({ behavior: "smooth", block: "start" });
}

function cancelDeviceEdit() {
    deviceEditIndex = null;
    document.getElementById("devName").value = "";
    document.getElementById("devIp").value = "";
    document.getElementById("devCommands").value = "";
    document.getElementById("devSiteNew").value = "";
    document.getElementById("devTypeNew").value = "";
    document.getElementById("devConnector").value = "";
    document.getElementById("deviceFormTitle").textContent = "Ajouter un équipement";
    document.getElementById("deviceFormSubmit").textContent = "Ajouter";
    document.getElementById("deviceFormCancel").style.display = "none";
    showDeviceFormError("");
    renderDevices();
}

function deleteDevice(index) {
    const device = deviceState.devices[index];
    if (!confirm("Supprimer " + (device.Name || "cet équipement") + " ?")) return;

    deviceState.devices.splice(index, 1);
    if (deviceEditIndex === index) {
        cancelDeviceEdit();
    } else {
        if (deviceEditIndex !== null && deviceEditIndex > index) deviceEditIndex--;
        renderDevices();
    }
    markDevicesDirty();
}

function saveDevices() {
    document.getElementById("devicesJson").value = JSON.stringify(deviceState, null, 2);
    devicesDirty = false; // évite l'alerte beforeunload pendant la soumission
    document.getElementById("devicesForm").submit();
}

/* ===================================================================
   Connecteurs d'authentification (/admin/connectors)
   Les secrets ne redescendent jamais du serveur : à l'édition, seuls
   nom/type/identifiant sont pré-remplis, les champs secrets restent vides.
   =================================================================== */
function toggleConnectorFields() {
    const typeSelect = document.getElementById("connType");
    if (!typeSelect) return;
    const isKey = typeSelect.value === "sshkey";
    document.querySelectorAll(".conn-password").forEach(el => el.style.display = isKey ? "none" : "");
    document.querySelectorAll(".conn-sshkey").forEach(el => el.style.display = isKey ? "" : "none");
}

function editConnector(btn) {
    document.getElementById("connName").value = btn.dataset.name;
    document.getElementById("connType").value = btn.dataset.type;
    document.getElementById("connUsername").value = btn.dataset.username;
    document.getElementById("connPassword").value = "";
    document.getElementById("connKey").value = "";
    document.getElementById("connPassphrase").value = "";
    document.getElementById("connectorFormTitle").textContent = "Modifier " + btn.dataset.name;
    document.getElementById("connectorFormSubmit").textContent = "Mettre à jour";
    document.getElementById("connectorFormCancel").style.display = "";
    toggleConnectorFields();
    document.getElementById("connectorFormCard").scrollIntoView({ behavior: "smooth", block: "start" });
}

/* ===== Planification des sauvegardes (/admin/settings) ===== */
function applyCronPreset() {
    const preset = document.getElementById("cronPreset");
    if (preset.value) {
        document.getElementById("cronExpression").value = preset.value;
    }
}

function toggleCronFields() {
    const enabled = document.getElementById("cronEnabled");
    if (!enabled) return;
    document.querySelectorAll(".cron-fields").forEach(el => {
        el.style.opacity = enabled.checked ? "" : "0.45";
        el.querySelectorAll("select, input").forEach(field => field.disabled = !enabled.checked);
    });
}

function resetConnectorForm() {
    document.getElementById("connectorForm").reset();
    document.getElementById("connectorFormTitle").textContent = "Ajouter un connecteur";
    document.getElementById("connectorFormSubmit").textContent = "Ajouter";
    document.getElementById("connectorFormCancel").style.display = "none";
    toggleConnectorFields();
}

document.addEventListener('DOMContentLoaded', function() {
    initPageState();
    initDeviceManager();
    toggleConnectorFields();
    toggleCronFields();
    // Auto-rafraîchissement uniquement sur la page des configurations :
    // ailleurs (édition de devices.json notamment) un reload perdrait la saisie en cours.
    if (window.location.pathname === '/conf') {
        setInterval(() => {
            saveConfig();
            location.reload();
        }, 120000);
    }
});
