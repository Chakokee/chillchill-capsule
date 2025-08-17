import fs from "fs";
import path from "path";

const projectRoot = process.cwd();
const targets = ["components", "src"];
let errors = 0;

function walk(dir){
  let out=[];
  if(!fs.existsSync(dir)) return out;
  for(const d of fs.readdirSync(dir,{withFileTypes:true})){
    const p = path.join(dir,d.name);
    if(d.isDirectory()) out=out.concat(walk(p));
    else if(/\.(tsx|jsx)$/.test(d.name)) out.push(p);
  }
  return out;
}

function checkFile(file){
  const text = fs.readFileSync(file,"utf8").replace(/\r\n/g,"\n");
  const hasClient = /^(?:\uFEFF)?\s*['"]use client['"]\s*;/.test(text) || /(^|\n)\s*['"]use client['"]\s*;/.test(text);
  if(!hasClient) return; // only guard client files

  // 1) Must be first statement
  if(!/^(?:\uFEFF)?\s*['"]use client['"]\s*;/.test(text)){
    console.error(`✖ "${file}": "use client" must be the very first statement.`);
    errors++;
  }

  // 2) All imports must be before any other code
  // Strip top directive
  let rest = text.replace(/^(?:\uFEFF)?\s*['"]use client['"]\s*;\s*/, "");
  // Consume initial import block (including side-effect and type imports)
  const importLine = /^\s*import(?:\s+type)?\s+.*?from\s+["'].*?["']\s*;|^\s*import\s+["'].*?["']\s*;/m;
  while(importLine.test(rest)){
    rest = rest.replace(importLine, "");
  }
  // If any further import appears, it's an error
  if(/^\s*import\s/m.test(rest)){
    console.error(`✖ "${file}": found an import after non-import code.`);
    errors++;
  }
}

for(const dir of targets){
  for(const f of walk(path.join(projectRoot,dir))) checkFile(f);
}

if(errors>0){
  console.error(`\nBuild guard failed: ${errors} issue(s) found.`);
  process.exit(1);
}else{
  console.log("Client/import ordering looks good ✅");
}
