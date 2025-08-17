import fs from "node:fs"; import path from "node:path";
const roots=["app","components"], exts=new Set([".tsx"]);
const walk=(d,o=[])=>fs.existsSync(d)?(fs.readdirSync(d).forEach(n=>{const p=path.join(d,n),s=fs.statSync(p);s.isDirectory()?walk(p,o):exts.has(path.extname(p))&&o.push(p)}),o):o;
const strip=t=>t.charCodeAt(0)===0xfeff?t.slice(1):t;
function ensureDirective(file, content){
  let s = strip(content).replace(/^\s*\r?\n+/g,"");
  const hasTop = /^["']use client["'];?/.test(s);
  if (!hasTop) {
    // If directive appears later, remove and hoist; else inject
    if (s.match(/^[\s\S]*?\b["']use client["'];?/m)) {
      s = s.replace(/^[\s\S]*?\b["']use client["'];?\s*/m,"");
    }
    s = `"use client";\n` + s.replace(/^\s*\r?\n+/,"");
  }
  return s;
}
const root = process.cwd();
for (const dir of roots) {
  const abs = path.resolve(root, dir);
  for (const f of walk(abs)) {
    let before = fs.readFileSync(f,"utf8");
    // Force for AppClient.tsx; for others, only if needed
    const must = path.basename(f)==="AppClient.tsx";
    const needs = must || !/^["']use client["'];?/.test(strip(before).replace(/^\s*\r?\n+/g,""));
    if (needs) {
      const after = ensureDirective(f, before);
      if (after !== before) fs.writeFileSync(f, after, "utf8");
    }
  }
}
console.log("fix-client-directives: enforced");
