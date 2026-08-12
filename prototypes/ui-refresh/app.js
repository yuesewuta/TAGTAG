(() => {
  const body = document.body;
  const resourceSearch = document.querySelector("#resourceSearch");
  const searchBox = resourceSearch.closest(".search-box");
  const rows = [...document.querySelectorAll("#resourceRows tr")];
  const resourceView = document.querySelector("#resourceView");
  const tagWorkbench = document.querySelector("#tagWorkbench");
  const filterStrip = document.querySelector("#filterStrip");
  const scopeStrip = document.querySelector("#scopeStrip");
  const viewTitle = document.querySelector("#viewTitle");
  const viewSubtitle = document.querySelector("#viewSubtitle");
  const emptyState = document.querySelector("#emptyState");
  const selectAll = document.querySelector("#selectAll");
  const selectionSummary = document.querySelector("#selectionSummary");
  const tagSelection = document.querySelector("#tagSelection");
  const inspector = document.querySelector("#inspector");
  const statusDrawer = document.querySelector("#statusDrawer");
  const toast = document.querySelector("#toast");
  const spaceSwitcher = document.querySelector("#spaceSwitcher");
  const spaceMenu = document.querySelector("#spaceMenu");
  const tagTreeList = document.querySelector("#tagTreeList");
  const parentTagSelect = document.querySelector("#parentTagSelect");
  const hierarchyFeedback = document.querySelector("#hierarchyFeedback");
  const shortcutRecorder = document.querySelector("#shortcutRecorder");
  const hotkeyValue = document.querySelector("#hotkeyValue");
  const shortcutHint = document.querySelector("#shortcutHint");
  const shortcutError = document.querySelector("#shortcutError");
  let activeView = "all";
  let toastTimer;
  let selectedTagId = "design";
  let shortcutRecording = false;
  let activeShortcut = {
    ctrlKey: true,
    altKey: false,
    shiftKey: true,
    metaKey: false,
    key: "t",
  };

  const tags = [
    {
      id: "design",
      name: "设计",
      parentId: null,
      color: "blue",
      count: 34,
    },
    {
      id: "brand",
      name: "品牌",
      parentId: "design",
      color: "green",
      count: 18,
    },
    {
      id: "inspiration",
      name: "灵感",
      parentId: "design",
      color: "purple",
      count: 9,
    },
    {
      id: "projects",
      name: "项目",
      parentId: null,
      color: "amber",
      count: 42,
    },
    {
      id: "project-a",
      name: "项目 A",
      parentId: "projects",
      color: "blue",
      count: 17,
    },
    {
      id: "autumn",
      name: "秋季活动",
      parentId: "projects",
      color: "red",
      count: 25,
    },
    {
      id: "operations",
      name: "运营",
      parentId: null,
      color: "green",
      count: 28,
    },
    {
      id: "archive",
      name: "归档",
      parentId: null,
      color: "gray",
      count: 61,
    },
  ];

  const views = {
    all: ["全部资源", "当前空间中的 128 个受管资源"],
    inbox: ["待整理", "没有有效标签的受管资源"],
    recent: ["最近", "最近打开、导入和标注的资源"],
    search: ["搜索", "按名称、路径、类型、时间和标签组合检索"],
    tags: ["标签层级", "按标签实体与位置浏览资源"],
  };

  function showToast(message) {
    clearTimeout(toastTimer);
    toast.querySelector("span").textContent = message;
    toast.classList.add("is-open");
    toastTimer = setTimeout(() => toast.classList.remove("is-open"), 2600);
  }

  function createIcon(id) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", id);
    svg.append(use);
    return svg;
  }

  function setSpaceMenu(open) {
    spaceMenu.hidden = !open;
    spaceSwitcher.setAttribute("aria-expanded", String(open));
  }

  function selectSpace(name) {
    document
      .querySelectorAll("[data-active-space]")
      .forEach((item) => (item.textContent = name));
    spaceMenu.querySelectorAll("[data-space-value]").forEach((option) => {
      const selected = option.dataset.spaceValue === name;
      option.classList.toggle("is-selected", selected);
      option.setAttribute("aria-selected", String(selected));
    });
    setSpaceMenu(false);
    showToast(`已切换到“${name}”（演示）`);
  }

  function tagById(id) {
    return tags.find((tag) => tag.id === id);
  }

  function descendantIds(id) {
    const result = new Set();
    const visit = (parentId) => {
      tags
        .filter((tag) => tag.parentId === parentId)
        .forEach((tag) => {
          result.add(tag.id);
          visit(tag.id);
        });
    };
    visit(id);
    return result;
  }

  function tagPath(id) {
    const path = [];
    let current = tagById(id);
    const visited = new Set();
    while (current && !visited.has(current.id)) {
      path.unshift(current.name);
      visited.add(current.id);
      current = current.parentId ? tagById(current.parentId) : null;
    }
    return path.join(" / ");
  }

  function renderTagTree() {
    const fragment = document.createDocumentFragment();
    const renderLevel = (parentId, depth) => {
      tags
        .filter((tag) => tag.parentId === parentId)
        .forEach((tag) => {
          const button = document.createElement("button");
          const hasChildren = tags.some((item) => item.parentId === tag.id);
          button.className = "tree-row";
          button.type = "button";
          button.dataset.tagId = tag.id;
          button.style.setProperty("--tree-depth", depth);
          button.setAttribute("aria-level", String(depth + 1));
          button.setAttribute(
            "aria-current",
            String(tag.id === selectedTagId),
          );
          button.classList.toggle("is-selected", tag.id === selectedTagId);
          button.append(
            hasChildren ? createIcon("#i-chevron-down") : document.createElement("span"),
          );
          const swatch = document.createElement("span");
          swatch.className = `tree-swatch ${tag.color}`;
          const name = document.createElement("strong");
          name.textContent = tag.name;
          const count = document.createElement("span");
          count.textContent = tag.count;
          button.append(swatch, name, count);
          button.addEventListener("click", () => selectTag(tag.id));
          fragment.append(button);
          renderLevel(tag.id, depth + 1);
        });
    };
    renderLevel(null, 0);
    tagTreeList.replaceChildren(fragment);
  }

  function renderParentOptions() {
    const selected = tagById(selectedTagId);
    const excluded = descendantIds(selectedTagId);
    const options = [
      { value: "", label: "无上级（顶层）" },
      ...tags
        .filter((tag) => tag.id !== selectedTagId && !excluded.has(tag.id))
        .map((tag) => ({ value: tag.id, label: tagPath(tag.id) })),
    ];
    parentTagSelect.replaceChildren(
      ...options.map((item) => {
        const option = document.createElement("option");
        option.value = item.value;
        option.textContent = item.label;
        option.selected = item.value === (selected.parentId ?? "");
        return option;
      }),
    );
  }

  function selectTag(id) {
    selectedTagId = id;
    const selected = tagById(id);
    renderTagTree();
    renderParentOptions();
    document.querySelector("#hierarchySelectionHint").textContent =
      `已选择“${selected.name}”`;
    document.querySelector("#selectedTagName").textContent = selected.name;
    document.querySelector("#selectedTagSummary").innerHTML =
      `<span class="tag-chip ${selected.color}"><span></span>层级位置</span> 可在左侧修改上级标签`;
    const placementPaths = document.querySelector(".placement-paths");
    placementPaths.replaceChildren();
    const label = document.createElement("span");
    label.textContent = "当前层级路径";
    const path = document.createElement("button");
    path.type = "button";
    path.textContent = tagPath(id);
    placementPaths.append(label, path);
    hierarchyFeedback.classList.remove("is-success");
    hierarchyFeedback.textContent = "修改后会立即更新左侧层级列表";
  }

  function setStatusDrawer(open) {
    statusDrawer.classList.toggle("is-open", open);
    statusDrawer.setAttribute("aria-hidden", String(!open));
    document.querySelectorAll("[data-toggle-drawer]").forEach((button) => {
      button.setAttribute("aria-expanded", String(open));
    });
  }

  function shortcutLabel(shortcut) {
    const parts = [];
    if (shortcut.ctrlKey) parts.push("Ctrl");
    if (shortcut.altKey) parts.push("Alt");
    if (shortcut.shiftKey) parts.push("Shift");
    if (shortcut.metaKey) parts.push("Win");
    const keyNames = {
      " ": "Space",
      arrowup: "↑",
      arrowdown: "↓",
      arrowleft: "←",
      arrowright: "→",
    };
    parts.push(keyNames[shortcut.key] ?? shortcut.key.toUpperCase());
    return parts.join(" + ");
  }

  function setShortcutRecording(recording) {
    shortcutRecording = recording;
    shortcutRecorder.setAttribute("aria-pressed", String(recording));
    shortcutHint.textContent = recording
      ? "请按下包含 Ctrl、Alt 或 Win 的组合键"
      : "点击后按下新的组合键";
    shortcutError.textContent = "";
  }

  function matchesShortcut(event, shortcut) {
    return (
      event.ctrlKey === shortcut.ctrlKey &&
      event.altKey === shortcut.altKey &&
      event.shiftKey === shortcut.shiftKey &&
      event.metaKey === shortcut.metaKey &&
      event.key.toLowerCase() === shortcut.key
    );
  }

  function visibleRows() {
    return rows.filter((row) => !row.hidden);
  }

  function applyFilters() {
    const query = resourceSearch.value.trim().toLocaleLowerCase("zh-CN");
    rows.forEach((row) => {
      const matchesView =
        activeView === "all" ||
        activeView === "search" ||
        row.dataset.status.split(" ").includes(activeView);
      const haystack =
        `${row.dataset.name} ${row.dataset.path} ${row.textContent}`.toLocaleLowerCase(
          "zh-CN",
        );
      row.hidden = !(matchesView && haystack.includes(query));
    });
    const hasRows = visibleRows().length > 0;
    emptyState.hidden = hasRows;
    document.querySelector(".resource-table").hidden = !hasRows;
    searchBox.classList.toggle("has-value", resourceSearch.value.length > 0);
    updateSelection();
  }

  function setView(view) {
    activeView = view;
    document
      .querySelectorAll("[data-view]")
      .forEach((button) =>
        button.classList.toggle("is-active", button.dataset.view === view),
      );
    viewTitle.textContent = views[view][0];
    viewSubtitle.textContent = views[view][1];
    const tags = view === "tags";
    resourceView.hidden = tags;
    tagWorkbench.hidden = !tags;
    filterStrip.hidden = view !== "search";
    scopeStrip.hidden = view !== "inbox";
    resourceSearch.value = "";
    searchBox.classList.remove("has-value");
    if (!tags) applyFilters();
    if (view === "search") requestAnimationFrame(() => resourceSearch.focus());
    body.classList.remove("nav-open");
  }

  function updateInspector(row) {
    rows.forEach((item) => item.classList.toggle("is-selected", item === row));
    document.querySelector("#inspectorName").textContent = row.dataset.name;
    document.querySelector("#inspectorType").textContent =
      `${row.dataset.type} · ${row.dataset.size}`;
    document.querySelector("#inspectorPath").textContent = row.dataset.path;
    document.querySelector("#metaType").textContent = row.dataset.type;
    document.querySelector("#metaSize").textContent = row.dataset.size;
    document.querySelector("#metaModified").textContent = row.dataset.modified;
    inspector.classList.add("is-open");
  }

  function updateSelection() {
    const checked = rows.filter(
      (row) => row.querySelector('input[type="checkbox"]').checked,
    );
    selectionSummary.textContent = checked.length
      ? `已选 ${checked.length} 项`
      : "";
    tagSelection.disabled = checked.length === 0;
    document.querySelector("#quickCount").textContent = Math.max(
      checked.length,
      1,
    );
    selectAll.checked =
      visibleRows().length > 0 &&
      visibleRows().every(
        (row) => row.querySelector('input[type="checkbox"]').checked,
      );
    selectAll.indeterminate = checked.length > 0 && !selectAll.checked;
  }

  function openModal(modal) {
    document.querySelectorAll(".modal-layer.is-open").forEach(closeModal);
    modal.classList.add("is-open");
    modal.setAttribute("aria-hidden", "false");
    const focusTarget = modal.querySelector("input, button");
    requestAnimationFrame(() => focusTarget?.focus());
  }

  function closeModal(modal) {
    modal.classList.remove("is-open");
    modal.setAttribute("aria-hidden", "true");
    if (modal.id === "settingsModal" && shortcutRecording) {
      setShortcutRecording(false);
    }
  }

  document
    .querySelectorAll("[data-view]")
    .forEach((button) =>
      button.addEventListener("click", () => setView(button.dataset.view)),
    );
  spaceSwitcher.addEventListener("click", () => {
    const open = spaceSwitcher.getAttribute("aria-expanded") !== "true";
    setSpaceMenu(open);
    if (open) {
      requestAnimationFrame(() =>
        spaceMenu.querySelector('[aria-selected="true"]')?.focus(),
      );
    }
  });
  spaceSwitcher.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowDown") return;
    event.preventDefault();
    setSpaceMenu(true);
    requestAnimationFrame(() =>
      spaceMenu.querySelector('[aria-selected="true"]')?.focus(),
    );
  });
  spaceMenu.querySelectorAll("[data-space-value]").forEach((option) => {
    option.addEventListener("click", () => selectSpace(option.dataset.spaceValue));
    option.addEventListener("keydown", (event) => {
      const options = [...spaceMenu.querySelectorAll("[data-space-value]")];
      const index = options.indexOf(option);
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const delta = event.key === "ArrowDown" ? 1 : -1;
        options[(index + delta + options.length) % options.length].focus();
      }
      if (event.key === "Escape") {
        event.preventDefault();
        setSpaceMenu(false);
        spaceSwitcher.focus();
      }
    });
  });
  document.addEventListener("click", (event) => {
    if (!event.target.closest(".space-switcher-wrap")) setSpaceMenu(false);
  });

  document.querySelector("#applyHierarchy").addEventListener("click", () => {
    const selected = tagById(selectedTagId);
    const nextParentId = parentTagSelect.value || null;
    if (selected.parentId === nextParentId) {
      hierarchyFeedback.classList.remove("is-success");
      hierarchyFeedback.textContent = "层级未发生变化";
      return;
    }
    selected.parentId = nextParentId;
    selectTag(selectedTagId);
    hierarchyFeedback.classList.add("is-success");
    hierarchyFeedback.textContent = `已更新：${tagPath(selectedTagId)}`;
    showToast(`“${selected.name}”的层级已更新`);
  });
  parentTagSelect.addEventListener("change", () => {
    hierarchyFeedback.classList.remove("is-success");
    hierarchyFeedback.textContent = "点击“应用层级”确认修改";
  });
  document.querySelector("#focusHierarchyEditor").addEventListener("click", () => {
    document
      .querySelector("#hierarchyEditor")
      .scrollIntoView({ block: "nearest", behavior: "smooth" });
    parentTagSelect.focus();
  });
  selectTag(selectedTagId);

  resourceSearch.addEventListener("input", applyFilters);
  document.querySelector("#clearSearch").addEventListener("click", () => {
    resourceSearch.value = "";
    applyFilters();
    resourceSearch.focus();
  });
  document.querySelector("#emptyClear").addEventListener("click", () => {
    resourceSearch.value = "";
    applyFilters();
    resourceSearch.focus();
  });
  document
    .querySelector("#clearFilters")
    .addEventListener("click", () =>
      document
        .querySelectorAll(".filter-chip")
        .forEach((chip) => chip.classList.remove("is-active")),
    );

  rows.forEach((row) => {
    row.addEventListener("click", (event) => {
      if (event.target.closest("button, input")) return;
      updateInspector(row);
    });
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter") updateInspector(row);
    });
    row
      .querySelector('input[type="checkbox"]')
      .addEventListener("change", updateSelection);
  });
  document
    .querySelectorAll(".row-action")
    .forEach((button) =>
      button.addEventListener("click", () =>
        showToast(
          button.title === "打开"
            ? "已交给 Windows 默认应用"
            : "资源操作菜单已打开",
        ),
      ),
    );
  selectAll.addEventListener("change", () => {
    visibleRows().forEach((row) => {
      row.querySelector('input[type="checkbox"]').checked = selectAll.checked;
    });
    updateSelection();
  });

  const quickTagModal = document.querySelector("#quickTagModal");
  const importModal = document.querySelector("#importModal");
  const settingsModal = document.querySelector("#settingsModal");
  document
    .querySelectorAll("[data-open-quick]")
    .forEach((button) =>
      button.addEventListener("click", () => openModal(quickTagModal)),
    );
  tagSelection.addEventListener("click", () => openModal(quickTagModal));
  document
    .querySelectorAll("[data-open-import]")
    .forEach((button) =>
      button.addEventListener("click", () => openModal(importModal)),
    );
  document
    .querySelectorAll("[data-open-settings]")
    .forEach((button) =>
      button.addEventListener("click", () => {
        body.classList.remove("nav-open");
        openModal(settingsModal);
      }),
    );
  document
    .querySelectorAll("[data-close-modal]")
    .forEach((button) =>
      button.addEventListener("click", () =>
        closeModal(button.closest(".modal-layer")),
      ),
    );
  document.querySelectorAll(".modal-layer").forEach((layer) =>
    layer.addEventListener("mousedown", (event) => {
      if (event.target === layer) closeModal(layer);
    }),
  );

  document.querySelectorAll("[data-tag-option]").forEach((button) =>
    button.addEventListener("click", () => {
      button.classList.toggle("is-selected");
      const dialog = button.closest(".dialog");
      if (dialog?.classList.contains("quick-dialog")) {
        const count = dialog.querySelectorAll(
          "[data-tag-option].is-selected",
        ).length;
        document.querySelector("#applyTags span").textContent =
          `添加 ${count} 个标签`;
      }
    }),
  );
  document.querySelector("#tagSearch").addEventListener("input", (event) => {
    const query = event.target.value.trim().toLocaleLowerCase("zh-CN");
    quickTagModal.querySelectorAll("[data-tag-option]").forEach((button) => {
      button.hidden = !button.textContent
        .toLocaleLowerCase("zh-CN")
        .includes(query);
    });
  });
  document.querySelector("#applyTags").addEventListener("click", () => {
    closeModal(quickTagModal);
    showToast("标签已添加到所选资源");
  });

  document.querySelectorAll("[data-import-mode]").forEach((button) =>
    button.addEventListener("click", () => {
      document
        .querySelectorAll("[data-import-mode]")
        .forEach((item) =>
          item.classList.toggle("is-selected", item === button),
        );
      const moving = button.dataset.importMode === "move";
      document.querySelector("#importNotice").textContent = moving
        ? "源资源会移动到存储根目录"
        : "源文件会保留在原位置";
      document.querySelector("#confirmImport span").textContent = moving
        ? "移动并导入"
        : "复制并导入";
      document
        .querySelector("#confirmImport use")
        .setAttribute("href", moving ? "#i-move" : "#i-copy");
    }),
  );
  document.querySelector("#confirmImport").addEventListener("click", () => {
    closeModal(importModal);
    showToast("2 个资源已加入导入队列");
  });

  document.querySelectorAll("[data-settings-tab]").forEach((button) =>
    button.addEventListener("click", () => {
      const tab = button.dataset.settingsTab;
      document
        .querySelectorAll("[data-settings-tab]")
        .forEach((item) => item.classList.toggle("is-active", item === button));
      document.querySelectorAll("[data-settings-panel]").forEach((panel) => {
        panel.hidden = panel.dataset.settingsPanel !== tab;
      });
    }),
  );
  document.querySelectorAll("#themeControl button").forEach((button) =>
    button.addEventListener("click", () => {
      document
        .querySelectorAll("#themeControl button")
        .forEach((item) =>
          item.classList.toggle("is-selected", item === button),
        );
      body.dataset.theme = button.dataset.themeValue;
    }),
  );
  document.querySelectorAll("#densityControl button").forEach((button) =>
    button.addEventListener("click", () => {
      document
        .querySelectorAll("#densityControl button")
        .forEach((item) =>
          item.classList.toggle("is-selected", item === button),
        );
      body.dataset.density = button.dataset.densityValue;
    }),
  );
  document
    .querySelectorAll(
      ".segmented:not(#themeControl):not(#densityControl) button",
    )
    .forEach((button) =>
      button.addEventListener("click", () => {
        const group = button.closest(".segmented");
        group
          .querySelectorAll("button")
          .forEach((item) =>
            item.classList.toggle("is-selected", item === button),
          );
      }),
    );
  document.querySelector("#saveSettings").addEventListener("click", () => {
    setShortcutRecording(false);
    closeModal(settingsModal);
    showToast("设置已保存");
  });

  shortcutRecorder.addEventListener("click", () => {
    setShortcutRecording(!shortcutRecording);
  });
  document.querySelector("#resetHotkey").addEventListener("click", () => {
    activeShortcut = {
      ctrlKey: true,
      altKey: false,
      shiftKey: true,
      metaKey: false,
      key: "t",
    };
    hotkeyValue.textContent = shortcutLabel(activeShortcut);
    setShortcutRecording(false);
    showToast("全局快捷键已恢复默认");
  });
  window.addEventListener(
    "keydown",
    (event) => {
      if (!shortcutRecording) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.key === "Escape") {
        setShortcutRecording(false);
        shortcutRecorder.focus();
        return;
      }
      if (["Control", "Alt", "Shift", "Meta"].includes(event.key)) return;
      if (!event.ctrlKey && !event.altKey && !event.metaKey) {
        shortcutError.textContent = "请至少包含 Ctrl、Alt 或 Win 修饰键";
        return;
      }
      if (
        event.ctrlKey &&
        !event.altKey &&
        !event.shiftKey &&
        !event.metaKey &&
        event.key.toLowerCase() === "k"
      ) {
        shortcutError.textContent = "Ctrl + K 已用于资源搜索，请使用其他组合键";
        return;
      }
      activeShortcut = {
        ctrlKey: event.ctrlKey,
        altKey: event.altKey,
        shiftKey: event.shiftKey,
        metaKey: event.metaKey,
        key: event.key.toLowerCase(),
      };
      hotkeyValue.textContent = shortcutLabel(activeShortcut);
      setShortcutRecording(false);
      showToast(`全局快捷键已改为 ${shortcutLabel(activeShortcut)}`);
      shortcutRecorder.focus();
    },
    true,
  );

  document.querySelectorAll("[data-toggle-drawer]").forEach((button) =>
    button.addEventListener("click", () => {
      const open = !statusDrawer.classList.contains("is-open");
      if (open) body.classList.remove("nav-open");
      setStatusDrawer(open);
    }),
  );
  document.querySelectorAll("[data-close-drawer]").forEach((button) =>
    button.addEventListener("click", () => {
      setStatusDrawer(false);
    }),
  );
  document.querySelectorAll("[data-drawer-tab]").forEach((button) =>
    button.addEventListener("click", () => {
      const tab = button.dataset.drawerTab;
      document
        .querySelectorAll("[data-drawer-tab]")
        .forEach((item) => item.classList.toggle("is-active", item === button));
      document.querySelectorAll("[data-drawer-panel]").forEach((panel) => {
        panel.hidden = panel.dataset.drawerPanel !== tab;
      });
    }),
  );

  document
    .querySelector("#toggleInspector")
    .addEventListener("click", () => inspector.classList.toggle("is-open"));
  document
    .querySelector(".inspector-close")
    .addEventListener("click", () => inspector.classList.remove("is-open"));
  document
    .querySelector("#mobileMenu")
    .addEventListener("click", () => body.classList.toggle("nav-open"));
  document
    .querySelector("#mobileBackdrop")
    .addEventListener("click", () => body.classList.remove("nav-open"));

  let dragDepth = 0;
  window.addEventListener("dragenter", (event) => {
    event.preventDefault();
    dragDepth += 1;
    document.querySelector("#dropOverlay").classList.add("is-open");
  });
  window.addEventListener("dragover", (event) => event.preventDefault());
  window.addEventListener("dragleave", () => {
    dragDepth -= 1;
    if (dragDepth <= 0) {
      dragDepth = 0;
      document.querySelector("#dropOverlay").classList.remove("is-open");
    }
  });
  window.addEventListener("drop", (event) => {
    event.preventDefault();
    dragDepth = 0;
    document.querySelector("#dropOverlay").classList.remove("is-open");
    openModal(importModal);
  });

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      const modal = document.querySelector(".modal-layer.is-open");
      if (modal) closeModal(modal);
      else if (statusDrawer.classList.contains("is-open"))
        setStatusDrawer(false);
      else if (body.classList.contains("nav-open"))
        body.classList.remove("nav-open");
      return;
    }
    if (matchesShortcut(event, activeShortcut)) {
      event.preventDefault();
      openModal(quickTagModal);
    }
    if (event.ctrlKey && event.key.toLowerCase() === "k") {
      event.preventDefault();
      setView("search");
    }
  });

  const inspectorBreakpoint = window.matchMedia("(min-width: 1280px)");
  const syncInspectorLayout = (event) =>
    inspector.classList.toggle("is-open", event.matches);
  syncInspectorLayout(inspectorBreakpoint);
  inspectorBreakpoint.addEventListener("change", syncInspectorLayout);
  updateSelection();
})();
