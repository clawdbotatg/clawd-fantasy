#!/usr/bin/env node
/**
 * Post-build script to fix relative asset paths for IPFS static export.
 * 
 * Problem: Next.js assetPrefix "./" resolves differently at each directory depth:
 *   /index.html          → ./_next/... ✅ (resolves to /_next/...)
 *   /create/index.html   → ./_next/... ❌ (resolves to /create/_next/...)
 *   /league/1/index.html → ./_next/... ❌ (resolves to /league/1/_next/...)
 * 
 * Fix: Replace "./" with the correct relative prefix based on directory depth.
 */

const fs = require("fs");
const path = require("path");

const outDir = path.join(__dirname, "out");

function findHtmlFiles(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) findHtmlFiles(full, files);
    else if (entry.name === "index.html") files.push(full);
  }
  return files;
}

const htmlFiles = findHtmlFiles(outDir);

for (const file of htmlFiles) {
  const relPath = path.relative(outDir, path.dirname(file));
  const depth = relPath === "" ? 0 : relPath.split(path.sep).length;
  
  if (depth === 0) continue; // Root index.html is fine
  
  const prefix = "../".repeat(depth);
  let html = fs.readFileSync(file, "utf8");
  
  // Replace ./_next/ with correct relative path
  const before = html;
  html = html.replace(/"\.\/_next\//g, `"${prefix}_next/`);
  // Also fix "." prefix used in RSC data for chunk paths
  html = html.replace(/"p":"\."/g, `"p":"${prefix.slice(0, -1) || "."}"`);
  
  if (html !== before) {
    fs.writeFileSync(file, html);
    console.log(`Fixed: ${path.relative(outDir, file)} (depth=${depth}, prefix=${prefix})`);
  }
}

console.log(`\nProcessed ${htmlFiles.length} HTML files.`);
