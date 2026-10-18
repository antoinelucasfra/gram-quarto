// snippet.mjs — gram recipe → table-style quick-overview snippet
// (ingredient rows grouped under action columns, prep notes as full-width
//  rows, cook temp/time as a right-hand cell)
import { escapeHtml as esc } from "@gram-lang/renderer";

function textOf(content, names) {
  return content
    .map((t) => {
      if (typeof t === "string") return t;
      if (t.quantity)
        return (
          `${t.quantity.text ?? t.quantity.value ?? ""} ${t.unit}`.trim() + " "
        );
      if (t.name || names.has(t.id)) return (t.name ?? names.get(t.id)) + " ";
      return "";
    })
    .join("")
    .replace(/\s+([,.;:!?])/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function tokensOf(step) {
  return step.content.filter((t) => typeof t !== "string");
}

const qtyText = (q, unit) =>
  q == null ? "" : `${q.text ?? q.value ?? q} ${unit ?? ""}`.trim();

// One section → { notes: [string], groups: [{action, lines[]}], cooks: [string] }
function sectionSnippet(section, names) {
  const notes = [];
  const groups = [];
  const cooks = [];
  for (const step of section.steps ?? []) {
    const toks = tokensOf(step);
    const used = toks.filter((t) => names.has(t.id));
    const tokQty = (t) => qtyText(t.quantity, t.unit);
    const temps = toks.filter((t) => t.type === "temperature").map(tokQty);
    const timers = toks.filter((t) => t.type === "timer").map(tokQty);

    const lines = used.map((t) => {
      const meta = section.ingredients?.find((i) => i._usageId === t._usageId);
      return `${qtyText(meta?.qty, meta?.unit)} ${names.get(t.id)}`.trim();
    });

    const isCook = temps.length > 0 || timers.length > 0;
    const txt = textOf(step.content, names);
    // action fallback = first word (or post-comma verb for "In a bowl, whisk"
    // style); recipes control the label with [Action] tags
    const action =
      step.action ||
      (/^(In|To|On|For)\b/.test(txt) && txt.includes(",")
        ? txt.split(",")[1].trim().split(/\s+/)[0]
        : txt.split(/\s+/)[0]);
    const actionCap = action
      ? action[0].toUpperCase() + action.slice(1)
      : "Step";

    if (isCook) {
      cooks.push([actionCap, ...temps, ...timers].filter(Boolean).join(" · "));
    }
    if (lines.length > 0) {
      groups.push({ action: actionCap, lines });
    } else if (txt) notes.push(txt);
  }
  return { notes, groups, cooks };
}

export function toSnippetHTML(result) {
  const names = new Map();
  for (const [id, i] of Object.entries(result.registry?.ingredients ?? {})) {
    // base-module intermediates get "pate$crumbs" ids — show last segment only
    names.set(id, i.name?.includes("$") ? i.name.split("$").pop() : i.name);
  }
  for (const i of result.shopping_list ?? [])
    if (i.name) names.set(i.id, i.name);
  for (const [id, c] of Object.entries(result.registry?.cookware ?? {}))
    if (!names.has(id)) names.set(id, c.name);

  const parts = [];
  for (const section of result.sections ?? []) {
    const { notes, groups, cooks } = sectionSnippet(section, names);
    const cols = groups.length + (cooks.length ? 1 : 0);
    if (cols === 0) {
      if (notes.length)
        parts.push(`<tr><td class="sn-note">${esc(notes.join(" "))}</td></tr>`);
      continue;
    }
    for (const n of notes)
      parts.push(
        `<tr><td class="sn-note" colspan="${cols}">${esc(n)}</td></tr>`,
      );
    parts.push("<tr>");
    for (const g of groups) {
      parts.push(
        `<td class="sn-group"><div class="sn-action">${esc(g.action)}</div><ul class="sn-ings">` +
          g.lines.map((l) => `<li>${esc(l)}</li>`).join("") +
          "</ul></td>",
      );
    }
    if (cooks.length) {
      parts.push(`<td class="sn-cook">${cooks.map(esc).join("<br>")}</td>`);
    }
    parts.push("</tr>");
  }
  if (!parts.length) return "";
  return `<table class="recipe-snippet">${parts.join("\n")}</table>`;
}
