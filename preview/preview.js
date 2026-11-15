/* Browser-side replica of the Windows 7 Aero Explorer UI plus a walk-through of
   the setup wizard. The download links point at the real native binaries that
   the Python preview server streams out of releases/. */
(() => {
  "use strict";

  // ---------------------------------------------------------------- helpers
  const $ = (sel, root = document) => root.querySelector(sel);
  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const pad = (n) => String(n).padStart(2, "0");
  const stamp = (date) =>
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  const ago = (minutes) => stamp(new Date(Date.now() - minutes * 60000));
  const bytes = (n) => {
    if (n < 1024) return `${n} bytes`;
    const units = ["KB", "MB", "GB", "TB"];
    let value = n;
    let i = -1;
    do { value /= 1024; i += 1; } while (value >= 1024 && i < units.length - 1);
    return `${value >= 100 ? value.toFixed(0) : value >= 10 ? value.toFixed(1) : value.toFixed(2)} ${units[i]}`;
  };

  // ------------------------------------------------------------------ state
  const state = {
    path: "computer://",
    crumbs: [{ label: "Computer", target: "computer://" }],
    history: ["computer://"],
    historyIndex: 0,
    items: [],
    selected: new Set(),
    view: "details",
    sort: { column: "name", asc: true },
    search: "",
    ftpConnected: false,
    busyPct: 0,
  };

  // ---------------------------------------------------------------- mock FS
  const drives = [
    { kind: "drive", name: "Windows (C:)", icon: "💾", type: "Local Disk", total: 500107862016, free: 138512695296, group: "Hard Disk Drives" },
    { kind: "drive", name: "Data (D:)", icon: "💾", type: "Local Disk", total: 2000398934016, free: 1298795298816, group: "Hard Disk Drives" },
    { kind: "drive", name: "Removable (E:)", icon: "🧷", type: "Removable Disk", total: 32010928128, free: 28991029248, group: "Devices with Removable Storage" },
    { kind: "folder", name: "Network", icon: "🌐", type: "Network Location", mod: "", group: "Network Locations & FTP Sites" },
    { kind: "ftp", name: "Rebex Public Demo FTP", icon: "🌐", type: "FTP Site", mod: "", group: "Network Locations & FTP Sites",
      host: "test.rebex.net", path: "/pub/example" },
  ];

  const cRoot = [
    { kind: "folder", name: "Users", icon: "📁", type: "File folder", mod: ago(120) },
    { kind: "folder", name: "Program Files", icon: "📁", type: "File folder", mod: ago(2400) },
    { kind: "folder", name: "Program Files (x86)", icon: "📁", type: "File folder", mod: ago(2400) },
    { kind: "folder", name: "Windows", icon: "📁", type: "File folder", mod: ago(600) },
    { kind: "file", name: "pagefile.sys", icon: "🗄", type: "System file", size: 8589934592, mod: ago(30) },
    { kind: "file", name: "hiberfil.sys", icon: "🗄", type: "System file", size: 6442450944, mod: ago(3000) },
    { kind: "file", name: "DumpStack.log.tmp", icon: "📄", type: "TMP File", size: 8192, mod: ago(5) },
    { kind: "file", name: "BOOTNXT", icon: "📄", type: "File", size: 1, mod: ago(9000) },
  ];

  const usersRoot = [
    { kind: "folder", name: "Public", icon: "📁", type: "File folder", mod: ago(180) },
    { kind: "folder", name: "hamza", icon: "📁", type: "File folder", mod: ago(12) },
    { kind: "file", name: "desktop.ini", icon: "⚙", type: "Configuration settings", size: 174, mod: ago(4000) },
  ];

  const homeRoot = [
    { kind: "folder", name: "Desktop", icon: "🖥", type: "File folder", mod: ago(30) },
    { kind: "folder", name: "Documents", icon: "📁", type: "File folder", mod: ago(140) },
    { kind: "folder", name: "Downloads", icon: "📁", type: "File folder", mod: ago(4) },
    { kind: "folder", name: "Pictures", icon: "🖼", type: "File folder", mod: ago(700) },
    { kind: "folder", name: "Music", icon: "🎵", type: "File folder", mod: ago(1200) },
    { kind: "folder", name: "Videos", icon: "🎬", type: "File folder", mod: ago(400) },
    { kind: "folder", name: "AppData", icon: "📁", type: "File folder", mod: ago(9) },
    { kind: "file", name: "NTUSER.DAT", icon: "🗄", type: "DAT File", size: 18874368, mod: ago(11) },
    { kind: "file", name: "ntuser.ini", icon: "⚙", type: "Configuration settings", size: 20, mod: ago(4400) },
    { kind: "file", name: "AeroExplorer.lnk", icon: "🔗", type: "Shortcut", size: 1432, mod: ago(3) },
  ];

  const downloadsRoot = [
    { kind: "folder", name: "FTP Transfers", icon: "📁", type: "File folder", mod: ago(7) },
    { kind: "file", name: "AeroExplorerSetup.exe", icon: "🛠", type: "Application", size: 1676800, mod: ago(6) },
    { kind: "file", name: "AeroExplorer.exe", icon: "🪟", type: "Application", size: 1204736, mod: ago(6) },
    { kind: "file", name: "readme.txt", icon: "📄", type: "Text Document", size: 2841, mod: ago(120) },
    { kind: "file", name: "screenshot-aero.png", icon: "🖼", type: "PNG File", size: 486203, mod: ago(45) },
    { kind: "file", name: "ftp-sites-backup.ini", icon: "⚙", type: "Configuration settings", size: 412, mod: ago(19) },
    { kind: "file", name: "ftp-test-plan.docx", icon: "📝", type: "Word Document", size: 33914, mod: ago(90) },
  ];

  const documentsRoot = [
    { kind: "folder", name: "Projects", icon: "📁", type: "File folder", mod: ago(60) },
    { kind: "file", name: "Aero-Explorer-Spec.md", icon: "📝", type: "Markdown File", size: 8123, mod: ago(52) },
    { kind: "file", name: "budget-2026.xlsx", icon: "📊", type: "Excel Worksheet", size: 24912, mod: ago(240) },
    { kind: "file", name: "notes.txt", icon: "📄", type: "Text Document", size: 1204, mod: ago(15) },
  ];

  const ftpRoot = [
    { kind: "folder", name: "pub", icon: "📁", type: "File folder", mod: ago(2000), remote: true },
    { kind: "folder", name: "uploads", icon: "📁", type: "File folder", mod: ago(30), remote: true },
    { kind: "file", name: ".ftpquota", icon: "📄", type: "File", size: 12, mod: ago(20), remote: true },
  ];

  const ftpPub = [
    { kind: "folder", name: "example", icon: "📁", type: "File folder", mod: ago(4000), remote: true },
    { kind: "file", name: "changelog.txt", icon: "📄", type: "Text Document", size: 1842, mod: ago(4000), remote: true },
  ];

  const ftpExample = [
    { kind: "file", name: "readme.txt", icon: "📄", type: "Text Document", size: 432, mod: ago(5000), remote: true },
    { kind: "file", name: "client-logo.png", icon: "🖼", type: "PNG File", size: 91884, mod: ago(5000), remote: true },
    { kind: "file", name: "release-notes.pdf", icon: "📕", type: "PDF Document", size: 246310, mod: ago(3000), remote: true },
  ];

  const ftpUploads = [
    { kind: "file", name: "aero-explorer-build.zip", icon: "🗜", type: "ZIP File", size: 726171, mod: ago(30), remote: true },
  ];

  const fileSystem = {
    "computer://": drives,
    "C:\\": cRoot,
    "C:\\Users": usersRoot,
    "C:\\Users\\hamza": homeRoot,
    "C:\\Users\\hamza\\Downloads": downloadsRoot,
    "C:\\Users\\hamza\\Documents": documentsRoot,
    "ftp://test.rebex.net/": ftpRoot,
    "ftp://test.rebex.net/pub": ftpPub,
    "ftp://test.rebex.net/pub/example": ftpExample,
    "ftp://test.rebex.net/uploads": ftpUploads,
  };

  // ------------------------------------------------------------------ views
  const explorerEl = $("#explorer");
  const crumbsEl = $("#crumbs");
  const fileHeaderEl = $("#file-header");
  const fileCanvasEl = $("#file-canvas");
  const emptyStateEl = $("#empty-state");
  const treeEl = $("#tree");
  const statusEl = $("#status-text");
  const statusRightEl = $("#status-right");
  const detailsEl = $("#details-pane");
  const addressProgressEl = $("#address-progress");
  const windowTitleEl = $("#window-title");

  function toast(message) {
    let node = $(".toast");
    if (!node) {
      node = el("div", "toast");
      document.body.appendChild(node);
    }
    node.textContent = message;
    node.classList.add("show");
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => node.classList.remove("show"), 2400);
  }

  function sortedItems(items) {
    const dir = state.sort.asc ? 1 : -1;
    const key = state.sort.column;
    return items.slice().sort((a, b) => {
      const aDir = a.kind !== "file";
      const bDir = b.kind !== "file";
      if (aDir !== bDir) return aDir ? -1 : 1;
      if (key === "mod") return (a.mod || "").localeCompare(b.mod || "") * dir;
      if (key === "type") return (a.type || "").localeCompare(b.type || "") * dir;
      if (key === "size") return ((a.size || 0) - (b.size || 0)) * dir;
      return a.name.localeCompare(b.name, undefined, { numeric: true }) * dir;
    });
  }

  function visibleItems() {
    const needle = state.search.trim().toLowerCase();
    const items = fileSystem[state.path] || [];
    const filtered = needle ? items.filter((i) => i.name.toLowerCase().includes(needle)) : items;
    return sortedItems(filtered);
  }

  function setPath(path, { push = true } = {}) {
    state.path = path;
    state.search = "";
    $("#search-input").value = "";
    state.selected.clear();
    state.crumbs = buildCrumbs(path);
    if (push) {
      state.history = state.history.slice(0, state.historyIndex + 1);
      state.history.push(path);
      state.historyIndex = state.history.length - 1;
    }
    if (path.startsWith("ftp://") && !state.ftpConnected) {
      simulateFtpConnect(path);
      return;
    }
    state.items = visibleItems();
    render();
  }

  function buildCrumbs(path) {
    const crumbs = [{ label: "Computer", target: "computer://" }];
    if (path === "computer://") return crumbs;
    if (path.startsWith("ftp://")) {
      const rest = path.slice("ftp://".length);
      const host = rest.split("/")[0];
      crumbs.push({ label: `FTP (${host})`, target: `ftp://${host}/` });
      const parts = rest.split("/").slice(1).filter(Boolean);
      let acc = `ftp://${host}`;
      parts.forEach((part) => {
        acc += `/${part}`;
        crumbs.push({ label: part, target: acc });
      });
      return crumbs;
    }
    const parts = path.replace(/\\+$/, "").split("\\");
    const drive = parts[0];
    crumbs.push({ label: `Local Disk (${drive})`, target: `${drive}\\` });
    let acc = drive;
    parts.slice(1).forEach((part) => {
      acc += `\\${part}`;
      crumbs.push({ label: part, target: acc });
    });
    return crumbs;
  }

  function simulateFtpConnect(path) {
    state.busyPct = 0;
    addressProgressEl.style.width = "0%";
    statusEl.textContent = "Connecting to test.rebex.net:21...";
    windowTitleEl.textContent = "Connecting... - Windows 7 Aero Explorer";
    let pct = 0;
    const timer = setInterval(() => {
      pct = Math.min(100, pct + 14 + Math.random() * 16);
      state.busyPct = pct;
      addressProgressEl.style.width = `${pct}%`;
      if (pct >= 100) {
        clearInterval(timer);
        state.ftpConnected = true;
        addressProgressEl.style.width = "0%";
        statusEl.textContent = "";
        state.items = visibleItems();
        render();
        toast("Connected to FTP server (demo)");
      }
    }, 130);
  }

  // --------------------------------------------------------------- renderers
  function render() {
    renderTree();
    renderBreadcrumbs();
    renderHeader();
    renderItems();
    renderDetails();
    renderStatus();
    const display = state.path === "computer://" ? "Computer" : state.path;
    windowTitleEl.textContent = `${display} - Windows 7 Aero Explorer`;
    $("#btn-back").disabled = state.historyIndex <= 0;
    $("#btn-forward").disabled = state.historyIndex >= state.history.length - 1;
    $("#btn-up").disabled = state.path === "computer://";
    statusRightEl.textContent = state.path.startsWith("ftp://")
      ? "FTP"
      : state.path === "computer://"
      ? "Computer"
      : "Local";
  }

  function renderTree() {
    treeEl.textContent = "";
    const groups = [
      { title: "Favorites", nodes: [
        { label: "Desktop", icon: "🖥", target: "C:\\Users\\hamza" },
        { label: "Downloads", icon: "📁", target: "C:\\Users\\hamza\\Downloads" },
        { label: "Documents", icon: "📁", target: "C:\\Users\\hamza\\Documents" },
      ]},
      { title: "Computer", nodes: [
        { label: "Windows (C:)", icon: "💾", target: "C:\\" },
        { label: "Users", icon: "📁", target: "C:\\Users" },
      ]},
      { title: "FTP Servers", nodes: [
        { label: "Rebex Public Demo FTP", icon: "🌐", target: "ftp://test.rebex.net/" },
      ]},
    ];

    groups.forEach((group) => {
      const heading = el("div", "tree-node", group.title);
      heading.style.fontWeight = "600";
      heading.style.paddingLeft = "8px";
      treeEl.appendChild(heading);
      group.nodes.forEach((node) => {
        const row = el("div", "tree-node child");
        row.innerHTML = `<span class="ti">${node.icon}</span><span>${node.label}</span>`;
        if (state.path === node.target) row.classList.add("active");
        row.addEventListener("click", () => setPath(node.target));
        treeEl.appendChild(row);
      });
    });
  }

  function renderBreadcrumbs() {
    crumbsEl.textContent = "";
    state.crumbs.forEach((crumb, index) => {
      const chip = el("span", "crumb", crumb.label);
      chip.title = crumb.target;
      chip.addEventListener("click", (event) => {
        event.stopPropagation();
        setPath(crumb.target);
      });
      crumbsEl.appendChild(chip);
      if (index < state.crumbs.length - 1) {
        crumbsEl.appendChild(el("span", "crumb-sep", "❯"));
      }
    });
  }

  function renderHeader() {
    fileHeaderEl.textContent = "";
    fileHeaderEl.hidden = state.view !== "details";
    const spec = [
      ["name", "Name", "h-name"],
      ["mod", "Date modified", "h-mod"],
      ["type", "Type", "h-type"],
      ["size", "Size", "h-size"],
    ];
    spec.forEach(([column, label, cls]) => {
      const cell = el("div", cls, label);
      if (state.sort.column === column) {
        cell.classList.add("h-sort");
        cell.textContent = `${label} ${state.sort.asc ? "▲" : "▼"}`;
      }
      cell.addEventListener("click", () => {
        if (state.sort.column === column) state.sort.asc = !state.sort.asc;
        else { state.sort.column = column; state.sort.asc = true; }
        render();
      });
      fileHeaderEl.appendChild(cell);
    });
  }

  function groupKey(item) {
    return item.group || null;
  }

  function attachItemHandlers(node, item) {
    node.addEventListener("click", () => {
      state.selected.clear();
      state.selected.add(item.name);
      render();
    });
    node.addEventListener("dblclick", () => openItem(item));
    node.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      state.selected.clear();
      state.selected.add(item.name);
      render();
      showContextMenu(event.clientX, event.clientY, item);
    });
  }

  function openItem(item) {
    if (item.kind === "drive") {
      const letter = (item.name.match(/\(([A-Z]):\)/) || [])[1];
      const target = letter === "C" ? "C:\\" : null;
      if (target && fileSystem[target]) setPath(target);
      else toast(`${item.name} is a demo placeholder - open Windows (C:) instead`);
      return;
    }
    if (item.kind === "ftp") {
      setPath(`ftp://${item.host}/`);
      return;
    }
    if (item.kind === "folder") {
      if (item.remote) {
        const target = `${state.path}/${item.name}`.replace(/\/+$/, "/").replace(/([^:])\/{2,}/g, "$1/");
        setPath(target);
        return;
      }
      const candidate =
        state.path === "computer://" ? `C:\\${item.name}` : `${state.path}\\${item.name}`;
      if (fileSystem[candidate]) setPath(candidate);
      else toast(`"${item.name}" is a demo placeholder folder - try Users, Downloads or Documents`);
      return;
    }
    if (item.remote) {
      toast(`Downloading ${item.name} from FTP... (demo)`);
      return;
    }
    toast(`Opening ${item.name} with the default Windows application (demo)`);
  }

  function renderItems() {
    fileCanvasEl.textContent = "";
    emptyStateEl.hidden = true;

    const items = state.items;
    if (!items.length) {
      emptyStateEl.hidden = false;
      emptyStateEl.textContent = state.search
        ? "No items match your search."
        : state.path === "computer://"
        ? "No drives were found."
        : "This folder is empty.";
      return;
    }

    if (state.view === "details") {
      let currentGroup = null;
      items.forEach((item) => {
        const key = groupKey(item);
        if (key && key !== currentGroup) {
          currentGroup = key;
          fileCanvasEl.appendChild(el("div", "group-header", key));
        }
        const row = el("div", "row");
        if (state.selected.has(item.name)) row.classList.add("selected");
        const icon = el("span", "icon", item.icon);
        const name = el("span", "name", item.name);
        const mod = el("span", "mod", item.mod || "");
        const type = el("span", "type", item.type || "");
        const size = el("span", "size", item.kind === "file" ? bytes(item.size || 0) : "");
        row.append(icon, name, mod, type, size);
        attachItemHandlers(row, item);
        fileCanvasEl.appendChild(row);
      });
      return;
    }

    if (state.view === "tiles" || state.view === "large") {
      const wrap = el("div", state.view === "tiles" ? "tiles" : "large-icons");
      items.forEach((item) => {
        const node = el("div", state.view === "tiles" ? "tile" : "li");
        if (state.selected.has(item.name)) node.classList.add("selected");
        const sub =
          item.kind === "drive"
            ? `${bytes(item.free || 0)} free of ${bytes(item.total || 0)}`
            : item.kind === "file"
            ? bytes(item.size || 0)
            : item.type || "";
        node.innerHTML =
          state.view === "tiles"
            ? `<span class="big">${item.icon}</span><span class="tile-text"><div class="t-name">${item.name}</div><div class="t-sub">${sub}</div></span>`
            : `<span class="big">${item.icon}</span><span class="l-name">${item.name}</span>`;
        attachItemHandlers(node, item);
        wrap.appendChild(node);
      });
      fileCanvasEl.appendChild(wrap);
      return;
    }

    // List / Content fall back to compact rows.
    items.forEach((item) => {
      const row = el("div", "row");
      if (state.selected.has(item.name)) row.classList.add("selected");
      row.innerHTML = `<span class="icon">${item.icon}</span><span class="name">${item.name}</span><span class="size">${
        item.kind === "file" ? bytes(item.size || 0) : ""
      }</span>`;
      attachItemHandlers(row, item);
      fileCanvasEl.appendChild(row);
    });
  }

  function renderDetails() {
    detailsEl.textContent = "";
    const selected = state.items.filter((item) => state.selected.has(item.name));

    if (selected.length === 1) {
      const item = selected[0];
      const icon = el("div", "d-icon", item.icon);
      const body = el("div");
      body.appendChild(el("div", "d-title", item.name));
      if (item.kind === "drive") {
        body.appendChild(el("div", "d-line", item.type));
        const used = 1 - item.free / item.total;
        const bar = el("div", `capacity${used > 0.9 ? " warn" : ""}`);
        const fill = el("span");
        fill.style.width = `${Math.round(used * 100)}%`;
        bar.appendChild(fill);
        body.appendChild(bar);
        body.appendChild(el("div", "d-line", `${bytes(item.free)} free of ${bytes(item.total)}`));
      } else {
        body.appendChild(el("div", "d-line", item.type || "File folder"));
        if (item.kind === "file") body.appendChild(el("div", "d-line", `Size: ${bytes(item.size || 0)}`));
        if (item.mod) body.appendChild(el("div", "d-line", `Date modified: ${item.mod}`));
        const path =
          item.kind === "ftp"
            ? `ftp://${item.host}${item.path}`
            : item.remote
            ? `${state.path}/${item.name}`
            : state.path === "computer://"
            ? item.name
            : `${state.path}\\${item.name}`;
        body.appendChild(el("div", "d-path", path));
      }
      detailsEl.append(icon, body);
      return;
    }

    if (selected.length > 1) {
      const total = selected.reduce((sum, i) => sum + (i.size || 0), 0);
      const body = el("div");
      body.appendChild(el("div", "d-title", `${selected.length} items selected`));
      body.appendChild(el("div", "d-line", `Total size: ${bytes(total)}`));
      detailsEl.append(el("div", "d-icon", "🗂"), body);
      return;
    }

    const body = el("div");
    body.appendChild(el("div", "d-title", state.path === "computer://" ? "Computer" : state.path));
    body.appendChild(
      el(
        "div",
        "d-empty",
        state.path.startsWith("ftp://")
          ? "FTP folder - drag files here to upload, or use the FTP menu to download"
          : "Select an item to view its details"
      )
    );
    detailsEl.appendChild(body);
  }

  function renderStatus() {
    if (state.busyPct > 0) {
      statusEl.textContent = "Transferring - " + Math.round(state.busyPct) + "%";
      return;
    }
    if (state.selected.size > 1) {
      const items = state.items.filter((i) => state.selected.has(i.name));
      const total = items.reduce((sum, i) => sum + (i.size || 0), 0);
      statusEl.textContent = `${state.selected.size} items selected   ${bytes(total)}`;
      return;
    }
    if (state.selected.size === 1) {
      statusEl.textContent = "1 item selected";
      return;
    }
    if (state.path.startsWith("ftp://")) {
      statusEl.textContent = `FTP: test.rebex.net  |  ${state.items.length} items`;
      return;
    }
    if (state.path === "computer://") {
      statusEl.textContent = `${state.items.length} drives and locations`;
      return;
    }
    statusEl.textContent = `${state.items.length} items`;
  }

  // ------------------------------------------------------------- popup menus
  let openMenu = null;

  function closeMenu() {
    if (openMenu) {
      openMenu.remove();
      openMenu = null;
      document.removeEventListener("mousedown", outsideClick);
    }
  }

  function outsideClick(event) {
    if (openMenu && !openMenu.contains(event.target)) closeMenu();
  }

  function showMenu(x, y, entries) {
    closeMenu();
    const menu = el("div", "menu");
    entries.forEach((entry) => {
      if (entry.separator) {
        menu.appendChild(el("div", "menu-sep"));
        return;
      }
      const item = el("div", `menu-item${entry.checked ? " checked" : ""}${entry.disabled ? " disabled" : ""}`);
      item.appendChild(el("span", "", entry.label));
      if (entry.hint) item.appendChild(el("span", "hint", entry.hint));
      if (entry.action) item.addEventListener("click", () => { closeMenu(); entry.action(); });
      menu.appendChild(item);
    });
    menu.style.left = `${Math.min(x, window.innerWidth - 240)}px`;
    menu.style.top = `${Math.min(y, window.innerHeight - 40 - entries.length * 26)}px`;
    document.body.appendChild(menu);
    openMenu = menu;
    setTimeout(() => document.addEventListener("mousedown", outsideClick), 0);
  }

  function showContextMenu(x, y, item) {
    const entries = [
      { label: item.remote ? "Download and open" : "Open", hint: "Enter", action: () => openItem(item) },
      { separator: true },
      { label: "Cut", hint: "Ctrl+X", action: () => toast("Cut to clipboard (demo)") },
      { label: "Copy", hint: "Ctrl+C", action: () => toast("Copied to clipboard (demo)") },
      { label: "Copy as path", action: () => { navigator.clipboard?.writeText(item.name); toast("Path copied"); } },
      { separator: true },
      { label: "Rename", hint: "F2", action: () => toast(`Rename "${item.name}" (demo)`) },
      { label: "Delete", hint: "Del", action: () => toast(`Move "${item.name}" to the Recycle Bin (demo)`) },
      { separator: true },
      { label: "Properties", action: () => toast("Windows file properties dialog (demo)") },
    ];
    showMenu(x, y, entries);
  }

  // ------------------------------------------------------------- commands
  const cmdOrganize = $("#cmd-organize");
  const cmdView = $("#cmd-view");
  const cmdFtp = $("#cmd-ftp");

  cmdOrganize.addEventListener("click", (event) => {
    const rect = event.currentTarget.getBoundingClientRect();
    showMenu(rect.left, rect.bottom + 2, [
      { label: "New folder", hint: "Ctrl+Shift+N", action: () => toast("Created \"New folder\" (demo)") },
      { separator: true },
      { label: "Rename", hint: "F2", action: () => toast("Rename (demo)") },
      { label: "Delete", hint: "Del", action: () => toast("Delete (demo)") },
      { separator: true },
      { label: "Layout", disabled: true },
      { label: "Navigation pane", checked: true },
      { label: "Details pane", checked: true },
      { separator: true },
      { label: "Show hidden files", checked: false, action: () => toast("Hidden files toggled (demo)") },
    ]);
  });

  cmdView.addEventListener("click", (event) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const modes = [
      ["details", "Details"],
      ["tiles", "Tiles"],
      ["large", "Large Icons"],
      ["list", "List"],
      ["content", "Content"],
    ];
    showMenu(rect.left, rect.bottom + 2, modes.map(([mode, label]) => ({
      label,
      checked: state.view === mode,
      action: () => { state.view = mode; render(); },
    })));
  });

  cmdFtp.addEventListener("click", (event) => {
    const rect = event.currentTarget.getBoundingClientRect();
    showMenu(rect.left, rect.bottom + 2, [
      { label: "Connect to test.rebex.net (demo)", action: () => setPath("ftp://test.rebex.net/") },
      { label: "FTP Connection Manager...", hint: "Ctrl+K", action: () => showMockFtpManager() },
      { separator: true },
      { label: "Upload files here...", action: () => toast("Upload dialog (demo) - drag & drop works in the real app") },
      { label: "Download selected...", action: () => toast("Download dialog (demo)") },
      { separator: true },
      { label: "Disconnect", disabled: !state.ftpConnected, action: () => {
        state.ftpConnected = false;
        setPath("computer://");
        toast("Disconnected from the FTP server");
      }},
    ]);
  });

  function showMockFtpManager() {
    showMenu(window.innerWidth / 2 - 120, 160, [
      { label: "Saved: Rebex Public Demo FTP", action: () => setPath("ftp://test.rebex.net/") },
      { label: "Saved: My Home NAS (192.168.1.20)", action: () => toast("Demo bookmark - add real servers in the app") },
      { separator: true },
      { label: "New bookmark...", action: () => toast("FTP Connection Manager dialog (desktop app)") },
    ]);
  }

  $("#cmd-new-folder").addEventListener("click", () => {
    toast("Create a new folder here (demo)");
  });

  $("#btn-back").addEventListener("click", () => {
    if (state.historyIndex <= 0) return;
    state.historyIndex -= 1;
    setPath(state.history[state.historyIndex], { push: false });
  });

  $("#btn-forward").addEventListener("click", () => {
    if (state.historyIndex >= state.history.length - 1) return;
    state.historyIndex += 1;
    setPath(state.history[state.historyIndex], { push: false });
  });

  $("#btn-up").addEventListener("click", () => {
    if (state.path === "computer://") return;
    if (state.path.startsWith("ftp://")) {
      const trimmed = state.path.replace(/\/+$/, "");
      const parts = trimmed.split("/");
      if (parts.length <= 4) setPath("computer://");
      else setPath(parts.slice(0, -1).join("/") + "/");
      return;
    }
    const parts = state.path.replace(/\\+$/, "").split("\\");
    if (parts.length === 1) setPath("computer://");
    else setPath(parts.slice(0, -1).join("\\") + "\\");
  });

  $("#search-input").addEventListener("input", (event) => {
    state.search = event.target.value;
    state.selected.clear();
    state.items = visibleItems();
    renderItems();
    renderDetails();
    renderStatus();
  });

  $("#address-box").addEventListener("click", (event) => {
    if (event.target.closest(".crumb")) return;
    const value = window.prompt(
      "Type a path or an FTP URL:\n\nExamples:\n  C:\\Users\n  C:\\Users\\hamza\\Downloads\n  ftp://test.rebex.net/\n  ftp://test.rebex.net/pub/example",
      state.path
    );
    if (!value) return;
    const trimmed = value.trim();
    if (!trimmed) return;
    if (trimmed.startsWith("ftp://")) {
      const normalized = trimmed.replace(/\/+$/, "") + "/";
      setPath(fileSystem[normalized] ? normalized : "ftp://test.rebex.net/");
      return;
    }
    const normalized = trimmed.replace(/\/+$/, "");
    if (fileSystem[normalized]) setPath(normalized);
    else if (fileSystem[`${normalized}\\`]) setPath(`${normalized}\\`);
    else toast("That path is not part of the demo file system");
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMenu();
    if (event.target instanceof HTMLInputElement) return;
    if (event.altKey && event.key === "ArrowLeft") { event.preventDefault(); $("#btn-back").click(); }
    if (event.altKey && event.key === "ArrowRight") { event.preventDefault(); $("#btn-forward").click(); }
    if (event.altKey && event.key === "ArrowUp") { event.preventDefault(); $("#btn-up").click(); }
    if (event.ctrlKey && event.key.toLowerCase() === "k") { event.preventDefault(); showMockFtpManager(); }
  });

  // ------------------------------------------------------------- wizard mock
  const wizard = {
    page: 0,
    title: $("#wizard-title"),
    sub: $("#wizard-sub"),
    body: $("#wizard-body"),
    back: $("#wiz-back"),
    next: $("#wiz-next"),
    cancel: $("#wiz-cancel"),
    accepted: false,
    progress: 0,
  };

  const wizardPages = [
    {
      title: "Welcome to the Windows 7 Aero Explorer Setup Wizard",
      sub: "This wizard will install Windows 7 Aero Explorer 1.0.0 on your computer.",
      render: () => `
        <p>Setup installs a native 64-bit Explorer replacement with Windows 7 Aero chrome and
        integrated FTP support.</p>
        <ul class="fake-list">
          <li>Two files only: <code>AeroExplorer.exe</code> and <code>Uninstall.exe</code></li>
          <li>Optional desktop / Start Menu shortcuts and folder context menu</li>
          <li>Registered in Apps &amp; Features for a clean removal</li>
        </ul>`,
      nextLabel: "Next",
      nextEnabled: () => true,
    },
    {
      title: "License Agreement",
      sub: "Please read the following license agreement carefully.",
      render: () => `
        <div class="license-box">MIT License

Copyright (c) 2026 AeroExplorer Open Source Project

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.</div>
        <label class="check-row"><input type="checkbox" id="wiz-accept" /> I accept the terms in the License Agreement</label>`,
      nextLabel: "Next",
      nextEnabled: () => wizard.accepted,
      after: () => {
        const box = $("#wiz-accept");
        box.checked = wizard.accepted;
        box.addEventListener("change", () => {
          wizard.accepted = box.checked;
          syncWizardButtons();
        });
      },
    },
    {
      title: "Choose Install Location",
      sub: "Setup will install Windows 7 Aero Explorer in the following folder.",
      render: () => `
        <p>Destination folder:</p>
        <div class="path-row">
          <input type="text" id="wiz-path" value="C:\\Program Files\\AeroExplorer" />
          <button type="button" id="wiz-browse">Browse...</button>
        </div>
        <p style="margin:8px 0 2px"><strong>Space required:</strong> 4.2 MB &nbsp;&nbsp; <strong>Space available:</strong> 129 GB</p>
        <p class="muted" style="font-size:11.5px">Shortcuts point straight at AeroExplorer.exe, so moving the folder later
        keeps them working (re-run Setup to repair paths).</p>`,
      nextLabel: "Next",
      nextEnabled: () => true,
      after: () => {
        $("#wiz-browse").addEventListener("click", () => toast("Folder picker (desktop app)"));
      },
    },
    {
      title: "Choose Components and Shortcuts",
      sub: "Select the shortcuts and shell integration you want Setup to create.",
      render: () => `
        <label class="check-row"><input type="checkbox" checked /> Create a desktop shortcut</label>
        <label class="check-row"><input type="checkbox" checked /> Create a Start Menu shortcut</label>
        <label class="check-row"><input type="checkbox" checked /> Add "Open in Windows 7 Aero Explorer" to the folder context menu</label>
        <label class="check-row"><input type="checkbox" checked /> Register Aero Explorer for ftp:// addresses</label>`,
      nextLabel: "Install",
      nextEnabled: () => true,
    },
    {
      title: "Installing Windows 7 Aero Explorer",
      sub: "Setup is extracting the application files and registering the program.",
      render: () => `
        <div class="wizard-progress"><span id="wiz-bar" style="width:0%"></span></div>
        <p id="wiz-status">Preparing...</p>
        <p class="muted" style="font-size:11.5px">Every extracted file is verified against its CRC32
        checksum before registration, so a corrupted download can never produce a broken install.</p>`,
      nextLabel: "",
      nextEnabled: () => false,
      backEnabled: false,
      after: () => {
        const bar = $("#wiz-bar");
        const status = $("#wiz-status");
        const steps = [
          [12, "Extracting AeroExplorer.exe..."],
          [46, "Extracting Uninstall.exe..."],
          [68, "Verifying CRC32 checksums..."],
          [84, "Creating shortcuts..."],
          [94, "Registering Apps & Features entry..."],
          [100, "Installation complete."],
        ];
        let index = 0;
        clearInterval(wizard.timer);
        const timer = setInterval(() => {
          if (index >= steps.length) {
            clearInterval(timer);
            wizard.timer = null;
            wizard.page = 5;
            renderWizard();
            return;
          }
          const [pct, text] = steps[index];
          bar.style.width = `${pct}%`;
          status.textContent = text;
          index += 1;
        }, 620);
        wizard.timer = timer;
      },
    },
    {
      title: "Completing the Windows 7 Aero Explorer Setup Wizard",
      sub: "Windows 7 Aero Explorer has been installed on your computer.",
      render: () => `
        <p><strong>✔ Installed to:</strong> C:\\Program Files\\AeroExplorer<br />
        <strong>Files installed:</strong> 2 (1.6 MB)<br />
        <strong>Shortcuts:</strong> Desktop · Start Menu · Folder context menu</p>
        <label class="check-row"><input type="checkbox" checked /> Launch Windows 7 Aero Explorer now</label>
        <p class="muted" style="font-size:11.5px">Click Finish to close this wizard.</p>`,
      nextLabel: "Finish",
      nextEnabled: () => true,
    },
  ];

  function syncWizardButtons() {
    const page = wizardPages[wizard.page];
    wizard.back.disabled = wizard.page === 0 || page.backEnabled === false;
    wizard.next.disabled = !page.nextEnabled();
    wizard.next.textContent = page.nextLabel;
    wizard.next.hidden = page.nextLabel === "";
    wizard.cancel.textContent = wizard.page === 5 ? "Close" : "Cancel";
  }

  function renderWizard() {
    const page = wizardPages[wizard.page];
    wizard.title.textContent = page.title;
    wizard.sub.textContent = page.sub;
    wizard.body.innerHTML = page.render();
    if (page.after) page.after();
    syncWizardButtons();
  }

  wizard.back.addEventListener("click", () => {
    if (wizard.page > 0) {
      wizard.page -= 1;
      renderWizard();
    }
  });

  wizard.next.addEventListener("click", () => {
    if (wizard.page === 3) {
      wizard.page = 4;
      renderWizard();
      return;
    }
    if (wizard.page === 5) {
      clearInterval(wizard.timer);
      wizard.timer = null;
      toast("Setup finished - AeroExplorer.exe would launch now");
      wizard.page = 0;
      wizard.accepted = false;
      renderWizard();
      return;
    }
    if (wizard.page < 5 && wizardPages[wizard.page].nextEnabled()) {
      wizard.page += 1;
      renderWizard();
    }
  });

  wizard.cancel.addEventListener("click", () => {
    clearInterval(wizard.timer);
    wizard.timer = null;
    toast("Setup cancelled");
    wizard.page = 0;
    wizard.accepted = false;
    renderWizard();
  });

  // ---------------------------------------------------------------- boot
  renderWizard();
  setPath("computer://", { push: false });

  // Pull real sizes / hashes from the preview server.
  fetch("/api/artifacts")
    .then((response) => (response.ok ? response.json() : null))
    .then((data) => {
      if (!data || !Array.isArray(data.artifacts)) return;
      const lookup = {
        "AeroExplorerSetup.exe": ["setup", "[data-hash='setup']"],
        "AeroExplorer.exe": ["portable", "[data-hash='portable']"],
        "AeroExplorer-portable.zip": ["zip", "[data-hash='zip']"],
        "AeroExplorer-v1.0.0-win64.zip": ["bundle", "[data-hash='bundle']"],
      };
      data.artifacts.forEach((artifact) => {
        const entry = lookup[artifact.name];
        if (!entry) return;
        const [sizeKey, hashSelector] = entry;
        const sizeNode = document.querySelector(`[data-size='${sizeKey}']`);
        if (sizeNode) sizeNode.textContent = artifact.prettySize;
        const hashNode = document.querySelector(hashSelector);
        if (hashNode) hashNode.textContent = `SHA-256 ${artifact.sha256}`;
      });
    })
    .catch(() => { /* static hosting without the API */ });
})();
