function showRevision(button) {
    let rev_sel = button.closest('.revision-section');
    let parentid = rev_sel.closest('.tabcontent').id;
    let rev = rev_sel.querySelector('#revisionSelect').value;
    if (!rev) return;
    localStorage.setItem("storage_" + parentid, rev);
    const configContent = document.getElementById("cnt_" + parentid).querySelector('pre');
    configContent.innerHTML = "Chargement...";
    let url = window.location.href;
    if(url.includes("?")){
        if(url.includes(parentid)) {
            window.location.href = url.replace(new RegExp(parentid + "=\\d+(&|$)"), parentid + "=" + rev + "$1");
        } else {
            window.location.href = url + "&"+parentid+"="+rev;
        }
    } else {
        window.location.href = url + "?"+parentid+"="+rev;
    }
    //location.reload();
}

function diffRevision(button) {
    let rev_sel = button.closest('.revision-section');
    let parentid = rev_sel.closest('.tabcontent').id;
    let rev = rev_sel.querySelector('#revisionSelect').value;
    if (!rev) return;
    saveConfig();
    window.location.href = "/diff?device="+parentid+"&rev="+rev;
}

function filterConfigs() {
    let value = document.getElementById("filterSelect").value;
    let allTabs = document.querySelectorAll(".tabcontent");
    let visibleIds = [];

    allTabs.forEach(tab => {
        if (value === "all" || tab.classList.contains(value)) {
            tab.style.display = "block";
            visibleIds.push(tab.id);
        } else {
            tab.style.display = "none";
        }
    });

    let allButtons = document.querySelectorAll(".tablinks");
    allButtons.forEach(button => {
        let configName = button.dataset.target || button.textContent.trim();
        if (visibleIds.includes(configName)) {
            button.style.display = "inline-block";
        } else {
            button.style.display = "none";
        }
    });

    let activeTab = document.querySelector(".tablinks.active");
    if (!activeTab || activeTab.style.display === "none") {
        let firstVisible = document.querySelector(".tablinks:not([style*='display: none'])");
        if (firstVisible) firstVisible.click();
    }
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

        if (savedRevision) {
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

    let tabContents = document.querySelectorAll(".revision-controls");
    tabContents.forEach(tab => {
        const sectionName = tab.parentElement.parentElement.id;
        const revision = tab.querySelector("#revisionSelect").value;

        if (revision) {
            localStorage.setItem("storage_" + sectionName, revision);
        }else{
            localStorage.setItem("storage_" + sectionName, "latest");
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

        localStorage.setItem("activeTab", configName);

        const savedRevision = localStorage.getItem("storage_" + configName);
        if (savedRevision) {
            const revisionSelect = selectedTab.querySelector('#revisionSelect');
            if (revisionSelect) {
                revisionSelect.value = savedRevision;
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

function initDeviceManager() {
    const dataEl = document.getElementById("devicesData");
    if (!dataEl) return;

    try {
        deviceState = JSON.parse(dataEl.textContent);
    } catch (e) {
        deviceState = { devices: [] };
    }
    if (!Array.isArray(deviceState.devices)) deviceState.devices = [];

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

    document.getElementById("devicesPreview").textContent = JSON.stringify(deviceState, null, 2);
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
    const commands = document.getElementById("devCommands").value
        .split("\n")
        .map(line => line.trim())
        .filter(line => line.length > 0)
        .map(line => line.replace(/\\n/g, "\n"));

    if (!name) return showDeviceFormError("Le nom est obligatoire.");
    if (!ip) return showDeviceFormError("L'adresse IP est obligatoire.");
    if (!site) return showDeviceFormError("Choisissez un site ou saisissez-en un nouveau.");
    if (!type) return showDeviceFormError("Choisissez un type ou saisissez-en un nouveau.");
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

document.addEventListener('DOMContentLoaded', function() {
    initPageState();
    initDeviceManager();
    // Auto-rafraîchissement uniquement sur la page des configurations :
    // ailleurs (édition de devices.json notamment) un reload perdrait la saisie en cours.
    if (window.location.pathname === '/conf') {
        setInterval(() => {
            saveConfig();
            location.reload();
        }, 120000);
    }
});
