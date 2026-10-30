// gntrees-launcher frontend: filter the application list and run the picked one.
const { invoke } = window.__TAURI__.core;

const input = document.getElementById("q");
const list = document.getElementById("list");
const count = document.getElementById("count");
const clock = document.getElementById("time");
const date = document.getElementById("date");
const network = document.getElementById("network");
const memory = document.getElementById("memory");
const battery = document.getElementById("battery");

let apps = [];
let shown = [];
let selected = 0;

/// Subsequence score: consecutive and early matches rank higher. -1 means no match.
function score(query, text) {
  let at = 0;
  let total = 0;
  let streak = 0;

  for (const ch of query) {
    const idx = text.indexOf(ch, at);
    if (idx < 0) return -1;
    total += idx === at ? 3 : 1;
    total += streak;
    streak = idx === at ? streak + 1 : 0;
    at = idx + 1;
  }

  return total;
}

function render() {
  list.replaceChildren();

  if (shown.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = "tidak ada aplikasi yang cocok";
    list.append(empty);
    count.textContent = "";
    return;
  }

  if (selected >= shown.length) selected = 0;

  shown.forEach((app, i) => {
    const row = document.createElement("li");
    row.className = "row" + (i === selected ? " active" : "");
    row.dataset.index = String(i);

    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = app.name.slice(0, 1).toUpperCase();

    const texts = document.createElement("div");
    texts.className = "texts";

    const name = document.createElement("div");
    name.className = "name";
    name.textContent = app.name;

    const comment = document.createElement("div");
    comment.className = "comment";
    comment.textContent = app.comment || app.id;

    texts.append(name, comment);
    row.append(badge, texts);

    row.addEventListener("click", () => open(i));
    row.addEventListener("mouseenter", () => {
      selected = i;
      highlight();
    });

    list.append(row);
  });

  count.textContent = shown.length === apps.length ? `${apps.length} aplikasi` : `${shown.length} dari ${apps.length}`;
  highlight();
}

function highlight() {
  for (const row of list.children) {
    const i = Number(row.dataset.index);
    row.classList.toggle("active", i === selected);
  }
  const active = list.querySelector(".row.active");
  if (active) active.scrollIntoView({ block: "nearest" });
}

function filter() {
  const query = input.value.trim().toLowerCase();

  if (!query) {
    shown = apps.slice();
  } else {
    shown = apps
      .map((app) => ({ app, s: Math.max(score(query, app.name.toLowerCase()), score(query, app.id.toLowerCase()) - 2) }))
      .filter((item) => item.s >= 0)
      .sort((a, b) => b.s - a.s)
      .map((item) => item.app);
  }

  selected = 0;
  render();
}

async function open(index) {
  const app = shown[index];
  if (!app) return;

  try {
    await invoke("launch_app", { id: app.id });
  } catch (err) {
    console.error(err);
  }

  invoke("hide");
}

async function refreshStatus() {
  try {
    const s = await invoke("status");
    clock.textContent = s.time;
    date.textContent = s.date;
    network.textContent = s.network === "offline" ? "net offline" : `net ${s.network}`;
    memory.textContent = `mem ${s.memory}%`;

    if (s.battery === null || s.battery === undefined) {
      battery.hidden = true;
    } else {
      battery.hidden = false;
      battery.textContent = `bat ${s.battery}%${s.charging ? " +" : ""}`;
    }
  } catch (err) {
    console.error(err);
  }
}

input.addEventListener("input", filter);

// The resident instance is re-shown from the socket, so start each visit clean.
window.addEventListener("focus", () => {
  input.value = "";
  filter();
  input.focus();
});

document.addEventListener("keydown", (event) => {
  switch (event.key) {
    case "Escape":
      event.preventDefault();
      invoke("hide");
      break;
    case "ArrowDown":
      event.preventDefault();
      if (shown.length) {
        selected = (selected + 1) % shown.length;
        highlight();
      }
      break;
    case "ArrowUp":
      event.preventDefault();
      if (shown.length) {
        selected = (selected - 1 + shown.length) % shown.length;
        highlight();
      }
      break;
    case "Enter":
      event.preventDefault();
      open(selected);
      break;
  }
});

(async function start() {
  try {
    apps = await invoke("list_apps");
  } catch (err) {
    console.error(err);
    apps = [];
  }
  filter();
  input.focus();
  refreshStatus();
  setInterval(refreshStatus, 1000);
})();
