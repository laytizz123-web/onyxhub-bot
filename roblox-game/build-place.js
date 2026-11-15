#!/usr/bin/env node
// Genere OnyxFarm.rbxlx a partir de src/ (aucune dependance).
// Usage : node build-place.js
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const SRC = path.join(ROOT, "src");
const OUT = path.join(ROOT, "OnyxFarm.rbxlx");

let referent = 0;
const nextRef = () => "RBX" + (referent++).toString(16).toUpperCase().padStart(8, "0");

const esc = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function scriptItem(className, name, source) {
  return (
    `<Item class="${className}" referent="${nextRef()}">` +
    `<Properties><string name="Name">${esc(name)}</string>` +
    `<bool name="Disabled">false</bool>` +
    `<ProtectedString name="Source">${esc(source)}</ProtectedString>` +
    `</Properties></Item>`
  );
}

function folderItem(className, name, childrenXml) {
  return (
    `<Item class="${className}" referent="${nextRef()}">` +
    `<Properties><string name="Name">${esc(name)}</string></Properties>` +
    childrenXml +
    `</Item>`
  );
}

const SERVICE_CLASSES = new Set([
  "ReplicatedStorage",
  "ServerScriptService",
  "StarterPlayer",
  "StarterPlayerScripts",
  "StarterGui",
  "Workspace",
  "Lighting",
]);

function buildDir(dir, name, isTop) {
  const entries = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  let xml = "";
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      xml += buildDir(full, entry.name, false);
    } else if (entry.name.endsWith(".lua") || entry.name.endsWith(".luau")) {
      const source = fs.readFileSync(full, "utf8");
      const base = entry.name.replace(/\.luau?$/, "");
      if (base.endsWith(".server")) xml += scriptItem("Script", base.replace(/\.server$/, ""), source);
      else if (base.endsWith(".client")) xml += scriptItem("LocalScript", base.replace(/\.client$/, ""), source);
      else xml += scriptItem("ModuleScript", base, source);
    }
  }
  const className = SERVICE_CLASSES.has(name) ? name : "Folder";
  return folderItem(className, name, xml);
}

let body = "";
for (const service of fs.readdirSync(SRC).sort()) {
  body += buildDir(path.join(SRC, service), service, true);
}

const xml =
  `<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ` +
  `xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n` +
  body +
  `\n</roblox>\n`;

fs.writeFileSync(OUT, xml);
console.log(`OK -> ${path.relative(ROOT, OUT)} (${(xml.length / 1024).toFixed(1)} Ko)`);
