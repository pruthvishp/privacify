const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawnSync, spawn } = require("child_process");

const appDir = process.env.PRIVACIFY_APP_DIR || __dirname;
const port = Number(process.env.PRIVACIFY_PORT || process.argv[2] || 8787);
const configPath = path.join(appDir, "config.json");
const workerPath = path.join(appDir, "llm_clipboard_worker.ps1");
const ahkPath = path.join(appDir, "llm_clipboard.ahk");
const logPath = path.join(appDir, "llm_clipboard_debug.log");
const defaultExamplesPath = path.join(appDir, "privacify_examples.json");
const recommendedModels = ["phi3", "llama3.2:3b", "qwen2.5:3b", "gemma2:2b"];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
}

function writeJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2), "utf8");
}

function examplesPath(config) {
  return config.privacify_examples_file || defaultExamplesPath;
}

function readExamples(config) {
  const file = examplesPath(config);
  if (!fs.existsSync(file)) return [];
  const parsed = readJson(file);
  return Array.isArray(parsed) ? parsed : [];
}

function normalizeExamples(examples) {
  return examples
    .filter((example) => example && String(example.input || "").trim() && String(example.output || "").trim())
    .map((example, index) => ({
      id: String(example.id || `user-${Date.now()}-${index}`),
      enabled: example.enabled !== false,
      category: String(example.category || "user"),
      input: String(example.input),
      output: String(example.output)
    }));
}

function getOllamaExe() {
  const candidates = [
    path.join(process.env.LOCALAPPDATA || "", "Programs", "Ollama", "ollama.exe"),
    path.join(process.env.LOCALAPPDATA || "", "Ollama", "ollama.exe"),
    path.join(process.env.ProgramFiles || "C:\\Program Files", "Ollama", "ollama.exe"),
    "ollama"
  ];
  return candidates.find((candidate) => candidate === "ollama" || fs.existsSync(candidate)) || "ollama";
}

function listModels() {
  const result = spawnSync(getOllamaExe(), ["list"], { encoding: "utf8", timeout: 10000 });
  if (result.status !== 0) return [];
  return result.stdout
    .split(/\r?\n/)
    .slice(1)
    .map((line) => line.trim().split(/\s+/)[0])
    .filter(Boolean);
}

function pullModel(model) {
  if (!recommendedModels.includes(model) && !/^[A-Za-z0-9._:-]+$/.test(model)) {
    throw new Error("Model name contains unsupported characters.");
  }
  const result = spawnSync(getOllamaExe(), ["pull", model], { encoding: "utf8", timeout: 900000 });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || `Failed to pull ${model}.`);
  }
  return { ok: true, model, installed_models: listModels() };
}

function state() {
  const config = readJson(configPath);
  if (config.privacify_examples_enabled === undefined) config.privacify_examples_enabled = true;
  if (config.privacify_examples_limit === undefined) config.privacify_examples_limit = 60;
  if (config.privacify_examples_file === undefined) config.privacify_examples_file = defaultExamplesPath;
  const examples = readExamples(config);
  const prompts = {};
  for (const profile of config.profiles || []) {
    prompts[profile.name] = fs.existsSync(profile.prompt_file)
      ? fs.readFileSync(profile.prompt_file, "utf8")
      : "";
  }
  const logTail = fs.existsSync(logPath)
    ? fs.readFileSync(logPath, "utf8").split(/\r?\n/).filter(Boolean).slice(-80)
    : [];
  return {
    app_dir: appDir,
    config,
    prompts,
    examples,
    example_count: examples.length,
    enabled_example_count: examples.filter((example) => example.enabled !== false).length,
    log_tail: logTail,
    installed_models: listModels(),
    recommended_models: recommendedModels,
    autohotkey_running: spawnSync("powershell", [
      "-NoProfile",
      "-Command",
      "Get-Process -Name AutoHotkey64 -ErrorAction SilentlyContinue | Select-Object -First 1"
    ], { encoding: "utf8" }).stdout.trim().length > 0
  };
}

function updateConfig(body) {
  const config = readJson(configPath);
  for (const key of ["model", "ollama_url", "app_name", "accent_color", "image_path", "privacify_examples_file"]) {
    if (body[key] !== undefined) config[key] = String(body[key]);
  }
  for (const key of ["trim_output", "privacify_use_model", "privacify_examples_enabled"]) {
    if (body[key] !== undefined) config[key] = Boolean(body[key]);
  }
  if (body.privacify_examples_limit !== undefined) {
    config.privacify_examples_limit = Math.max(0, Number(body.privacify_examples_limit) || 0);
  }
  if (Array.isArray(body.profiles)) {
    for (const incoming of body.profiles) {
      const profile = (config.profiles || []).find((p) => p.name === incoming.name);
      if (profile && incoming.hotkey !== undefined) profile.hotkey = String(incoming.hotkey);
    }
  }
  if (body.prompts) {
    for (const profile of config.profiles || []) {
      if (body.prompts[profile.name] !== undefined) {
        fs.writeFileSync(profile.prompt_file, String(body.prompts[profile.name]), "utf8");
      }
    }
  }
  if (Array.isArray(body.examples)) {
    config.privacify_examples_file = config.privacify_examples_file || defaultExamplesPath;
    writeJson(config.privacify_examples_file, normalizeExamples(body.examples));
  }
  writeJson(configPath, config);
  return state();
}

function runPrivacify(input) {
  const dir = fs.mkdtempSync(path.join(require("os").tmpdir(), "privacify-ui-"));
  const inputFile = path.join(dir, "input.txt");
  const outputFile = path.join(dir, "output.txt");
  fs.writeFileSync(inputFile, input, "utf8");
  const result = spawnSync("powershell", [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    workerPath,
    "-ProfileName",
    "privacify",
    "-ConfigPath",
    configPath,
    "-InputFile",
    inputFile,
    "-OutputFile",
    outputFile
  ], { encoding: "utf8", timeout: 180000 });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || "Privacify test failed.");
  }
  const output = fs.readFileSync(outputFile, "utf8").replace(/^\uFEFF/, "");
  fs.rmSync(dir, { recursive: true, force: true });
  return output;
}

function restartHotkeys() {
  spawnSync("powershell", [
    "-NoProfile",
    "-Command",
    "Get-Process -Name AutoHotkey64 -ErrorAction SilentlyContinue | Stop-Process -Force"
  ]);
  const ahk = [
    path.join(process.env.LOCALAPPDATA || "", "Programs", "AutoHotkey", "v2", "AutoHotkey64.exe"),
    path.join(process.env.ProgramFiles || "C:\\Program Files", "AutoHotkey", "v2", "AutoHotkey64.exe")
  ].find((candidate) => fs.existsSync(candidate));
  if (!ahk) throw new Error("AutoHotkey v2 was not found.");
  spawn(ahk, [ahkPath], { detached: true, stdio: "ignore", cwd: appDir }).unref();
}

const html = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacify Manager</title>
<style>
:root{--accent:#2563eb;--bg:#f7f8fb;--ink:#172033;--muted:#667085;--line:#d8dee9;--panel:#fff}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 "Segoe UI",system-ui,sans-serif;background:var(--bg);color:var(--ink)}
header{height:72px;display:flex;align-items:center;gap:16px;padding:0 28px;border-bottom:1px solid var(--line);background:var(--panel)}
.mark{width:44px;height:44px;border-radius:8px;display:grid;place-items:center;background:var(--accent);color:white;font-weight:800;overflow:hidden}.mark img{width:100%;height:100%;object-fit:cover}
h1{margin:0;font-size:20px}.subtitle{color:var(--muted);font-size:13px}main{display:grid;grid-template-columns:250px 1fr;min-height:calc(100vh - 72px)}
nav{border-right:1px solid var(--line);padding:18px 14px;background:#fbfcfe}nav button{width:100%;text-align:left;border:0;background:transparent;padding:11px 12px;border-radius:7px;color:#344054;cursor:pointer;font:inherit}nav button.active{background:#eaf1ff;color:#123c8c}
section{display:none;padding:24px 28px 40px;max-width:1120px}section.active{display:block}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:18px}.full{grid-column:1/-1}
label{display:block;font-weight:650;margin:0 0 8px}input,textarea{width:100%;border:1px solid #cbd5e1;border-radius:7px;padding:10px 11px;font:inherit;background:white;color:var(--ink)}textarea{min-height:150px;resize:vertical;font-family:Consolas,"Courier New",monospace}
.row{display:grid;grid-template-columns:1fr 130px;gap:12px;align-items:end;margin-bottom:12px}.actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}.btn{border:1px solid var(--accent);background:var(--accent);color:white;border-radius:7px;padding:10px 14px;cursor:pointer;font-weight:650}.btn.secondary{background:white;color:var(--accent)}.btn.ghost{border-color:#cbd5e1;background:white;color:#344054}
.status{color:var(--muted);margin-top:10px;min-height:20px}.switch{display:flex;align-items:center;gap:10px;margin-top:12px}.switch input{width:18px;height:18px}pre{background:#101828;color:#e5eefc;border-radius:8px;padding:14px;overflow:auto;min-height:180px;white-space:pre-wrap}.metric{display:flex;justify-content:space-between;border-top:1px solid var(--line);padding:10px 0}.metric:first-child{border-top:0}
@media(max-width:820px){main{grid-template-columns:1fr}nav{display:flex;overflow:auto;border-right:0;border-bottom:1px solid var(--line)}nav button{white-space:nowrap}.grid{grid-template-columns:1fr}.row{grid-template-columns:1fr}}
</style>
</head>
<body>
<header><div class="mark" id="brandMark">P</div><div><h1 id="title">Privacify Manager</h1><div class="subtitle" id="subtitle">Local settings, hotkeys, prompts, and testing</div></div></header>
<main>
<nav><button class="active" data-tab="overview">Overview</button><button data-tab="brand">Image & Brand</button><button data-tab="hotkeys">Hotkeys</button><button data-tab="prompts">Prompts</button><button data-tab="examples">Examples</button><button data-tab="test">Test</button><button data-tab="logs">Logs</button></nav>
<section class="active" id="overview"><div class="grid"><div class="panel"><div class="metric"><span>Install folder</span><strong id="appDir"></strong></div><div class="metric"><span>Hotkey app</span><strong id="ahkStatus"></strong></div><div class="metric"><span>Model</span><strong id="modelValue"></strong></div><div class="metric"><span>Installed models</span><strong id="modelsValue"></strong></div><div class="metric"><span>Privacify uses model</span><strong id="modelToggleValue"></strong></div></div><div class="panel"><label>Model<input id="model" list="modelOptions"></label><datalist id="modelOptions"></datalist><div class="actions"><button class="btn secondary" id="pullModel">Pull selected model</button></div><label>Ollama URL<input id="ollamaUrl"></label><label class="switch"><input type="checkbox" id="trimOutput"> Trim output</label><label class="switch"><input type="checkbox" id="privacifyUseModel"> Use local model after redaction</label></div></div><div class="actions"><button class="btn" id="saveOverview">Save settings</button><button class="btn secondary" id="restartHotkeys">Restart hotkeys</button></div><div class="status" id="overviewStatus"></div></section>
<section id="brand"><div class="grid"><div class="panel"><label>App name<input id="appName"></label><label>Accent color<input id="accentColor" type="color"></label><label>Tray/brand image path<input id="imagePath" placeholder="C:\path\to\icon.ico or image"></label></div><div class="panel"><div class="mark" id="brandPreview" style="width:96px;height:96px;font-size:36px;margin-bottom:14px">P</div><div class="subtitle">Changing the tray image takes effect after restarting hotkeys.</div></div></div><div class="actions"><button class="btn" id="saveBrand">Save brand</button></div><div class="status" id="brandStatus"></div></section>
<section id="hotkeys"><div class="panel" id="hotkeyPanel"></div><div class="actions"><button class="btn" id="saveHotkeys">Save hotkeys</button><button class="btn secondary" id="restartHotkeys2">Restart hotkeys</button></div><div class="status" id="hotkeyStatus"></div></section>
<section id="prompts"><div class="grid" id="promptGrid"></div><div class="actions"><button class="btn" id="savePrompts">Save prompts</button></div><div class="status" id="promptStatus"></div></section>
<section id="examples"><div class="grid"><div class="panel"><div class="metric"><span>Total examples</span><strong id="exampleCount"></strong></div><div class="metric"><span>Enabled examples</span><strong id="enabledExampleCount"></strong></div><label class="switch"><input type="checkbox" id="privacifyExamplesEnabled"> Use examples with local model</label><label>Examples used per run<input id="privacifyExamplesLimit" type="number" min="0" max="200"></label><label>Examples file<input id="privacifyExamplesFile"></label></div><div class="panel"><label>Category<input id="newExampleCategory" value="user"></label><label>Input<textarea id="newExampleInput"></textarea></label><label>Output<textarea id="newExampleOutput"></textarea></label><div class="actions"><button class="btn secondary" id="addExample">Add example</button></div></div><div class="panel full"><label>Examples JSON</label><textarea id="examplesJson" style="min-height:420px"></textarea></div></div><div class="actions"><button class="btn" id="saveExamples">Save examples</button></div><div class="status" id="exampleStatus"></div></section>
<section id="test"><div class="grid"><div class="panel"><label>Input text<textarea id="testInput">Name: Jane Smith
Email jane.smith@example.com or call (415) 555-2671.
SSN 123-45-6789, card 4111 1111 1111 1111.
Ship to 123 Market Street Apt 4, San Francisco.</textarea></label><div class="actions"><button class="btn" id="runTest">Run Privacify test</button></div></div><div class="panel"><label>Output</label><pre id="testOutput"></pre></div></div><div class="status" id="testStatus"></div></section>
<section id="logs"><div class="panel full"><label>Recent debug log</label><pre id="logOutput"></pre></div><div class="actions"><button class="btn ghost" id="refreshLogs">Refresh</button></div></section>
</main>
<script>
let state=null;const $=id=>document.getElementById(id);document.querySelectorAll('nav button').forEach(btn=>btn.onclick=()=>{document.querySelectorAll('nav button').forEach(b=>b.classList.remove('active'));document.querySelectorAll('section').forEach(s=>s.classList.remove('active'));btn.classList.add('active');$(btn.dataset.tab).classList.add('active')});
async function api(path,options){const res=await fetch(path,options);const data=await res.json();if(!res.ok)throw new Error(data.error||'Request failed');return data}
function collectExamples(){try{return JSON.parse($('examplesJson').value||'[]')}catch(e){throw new Error('Examples JSON is invalid: '+e.message)}}
function collect(){return{model:$('model').value,ollama_url:$('ollamaUrl').value,trim_output:$('trimOutput').checked,privacify_use_model:$('privacifyUseModel').checked,privacify_examples_enabled:$('privacifyExamplesEnabled').checked,privacify_examples_limit:Number($('privacifyExamplesLimit').value||0),privacify_examples_file:$('privacifyExamplesFile').value,app_name:$('appName').value,accent_color:$('accentColor').value,image_path:$('imagePath').value,profiles:state.config.profiles.map(p=>({name:p.name,hotkey:document.querySelector('[data-hotkey="'+p.name+'"]').value})),prompts:Object.fromEntries(state.config.profiles.map(p=>[p.name,document.querySelector('[data-prompt="'+p.name+'"]').value])),examples:collectExamples()}}
function render(){const c=state.config;document.documentElement.style.setProperty('--accent',c.accent_color||'#2563eb');$('title').textContent=(c.app_name||'Privacify')+' Manager';$('subtitle').textContent=state.app_dir;$('appDir').textContent=state.app_dir;$('ahkStatus').textContent=state.autohotkey_running?'Running':'Stopped';$('modelValue').textContent=c.model||'';$('modelsValue').textContent=(state.installed_models||[]).length?state.installed_models.join(', '):'None';$('modelToggleValue').textContent=c.privacify_use_model?'Yes':'No';$('model').value=c.model||'';$('modelOptions').innerHTML=[...(state.installed_models||[]),...(state.recommended_models||[])].filter((v,i,a)=>v&&a.indexOf(v)===i).map(m=>'<option value="'+m+'"></option>').join('');$('ollamaUrl').value=c.ollama_url||'';$('trimOutput').checked=!!c.trim_output;$('privacifyUseModel').checked=!!c.privacify_use_model;$('privacifyExamplesEnabled').checked=c.privacify_examples_enabled!==false;$('privacifyExamplesLimit').value=c.privacify_examples_limit||60;$('privacifyExamplesFile').value=c.privacify_examples_file||'';$('exampleCount').textContent=state.example_count||0;$('enabledExampleCount').textContent=state.enabled_example_count||0;$('examplesJson').value=JSON.stringify(state.examples||[],null,2);$('appName').value=c.app_name||'Privacify';$('accentColor').value=c.accent_color||'#2563eb';$('imagePath').value=c.image_path||'';const letter=(c.app_name||'P').trim().slice(0,1).toUpperCase()||'P';$('brandMark').textContent=letter;$('brandPreview').textContent=letter;$('hotkeyPanel').innerHTML=c.profiles.map(p=>'<div class="row"><label>'+p.name+'<input data-hotkey="'+p.name+'" value="'+(p.hotkey||'')+'"></label><button class="btn ghost" type="button">Profile</button></div>').join('');$('promptGrid').innerHTML=c.profiles.map(p=>'<div class="panel"><label>'+p.name+' prompt</label><textarea data-prompt="'+p.name+'">'+(state.prompts[p.name]||'')+'</textarea></div>').join('');$('logOutput').textContent=(state.log_tail||[]).join('\n')}
async function load(){state=await api('/api/state');render()}async function save(id){$(id).textContent='Saving...';state=await api('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(collect())});render();$(id).textContent='Saved.'}async function restart(id){$(id).textContent='Restarting hotkeys...';await api('/api/restart',{method:'POST'});await load();$(id).textContent='Hotkeys restarted.'}
$('saveOverview').onclick=()=>save('overviewStatus').catch(e=>$('overviewStatus').textContent=e.message);$('pullModel').onclick=async()=>{const model=$('model').value.trim();$('overviewStatus').textContent='Pulling '+model+'...';try{await api('/api/pull-model',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({model})});await save('overviewStatus');$('overviewStatus').textContent='Pulled and selected '+model+'.'}catch(e){$('overviewStatus').textContent=e.message}};$('saveBrand').onclick=()=>save('brandStatus').catch(e=>$('brandStatus').textContent=e.message);$('saveHotkeys').onclick=()=>save('hotkeyStatus').catch(e=>$('hotkeyStatus').textContent=e.message);$('savePrompts').onclick=()=>save('promptStatus').catch(e=>$('promptStatus').textContent=e.message);$('saveExamples').onclick=()=>save('exampleStatus').catch(e=>$('exampleStatus').textContent=e.message);$('addExample').onclick=()=>{try{const examples=collectExamples();examples.unshift({id:'user-'+Date.now(),enabled:true,category:$('newExampleCategory').value||'user',input:$('newExampleInput').value,output:$('newExampleOutput').value});$('examplesJson').value=JSON.stringify(examples,null,2);$('newExampleInput').value='';$('newExampleOutput').value='';$('exampleStatus').textContent='Example added. Save examples to keep it.'}catch(e){$('exampleStatus').textContent=e.message}};$('restartHotkeys').onclick=()=>restart('overviewStatus').catch(e=>$('overviewStatus').textContent=e.message);$('restartHotkeys2').onclick=()=>restart('hotkeyStatus').catch(e=>$('hotkeyStatus').textContent=e.message);$('refreshLogs').onclick=load;$('runTest').onclick=async()=>{$('testStatus').textContent='Running...';$('testOutput').textContent='';try{const data=await api('/api/test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({input:$('testInput').value})});$('testOutput').textContent=data.output;$('testStatus').textContent='Test passed.';await load()}catch(e){$('testStatus').textContent=e.message}};load().catch(e=>document.body.textContent=e.message)
</script></body></html>`;

function send(res, status, value) {
  const body = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  res.writeHead(status, {
    "Content-Type": typeof value === "string" ? "text/html; charset=utf-8" : "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/") return send(res, 200, html);
  if (req.method === "GET" && req.url === "/api/state") return send(res, 200, state());
  let body = "";
  req.on("data", (chunk) => { body += chunk; });
  req.on("end", () => {
    try {
      const data = body ? JSON.parse(body) : {};
      if (req.method === "POST" && req.url === "/api/config") return send(res, 200, updateConfig(data));
      if (req.method === "POST" && req.url === "/api/pull-model") return send(res, 200, pullModel(String(data.model || "")));
      if (req.method === "POST" && req.url === "/api/test") return send(res, 200, { output: runPrivacify(String(data.input || "")) });
      if (req.method === "POST" && req.url === "/api/restart") {
        restartHotkeys();
        return send(res, 200, { ok: true });
      }
      return send(res, 404, { error: "Not found" });
    } catch (error) {
      return send(res, 500, { error: error.message });
    }
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Privacify Manager running at http://127.0.0.1:${port}/`);
});
