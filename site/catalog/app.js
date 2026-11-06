"use strict";
const BUILTINS_URL=new URL("../metadata/builtins.json",location.href).href;
const state={builtins:[],repository:[],filtered:[],page:1,pageSize:12,view:"tiles"};
const $=id=>document.getElementById(id);
const TYPES=["App","Script","Font","Certificate","Driver"];
const DOC_ROOT="https://github.com/roryvossepoel/OSDStage/blob/main/docs/";
const DOC_URLS={
  Microsoft365Apps:"microsoft-365-apps.md",
  MicrosoftTeams:"microsoft-teams.md",
  AdobeAcrobatUnified:"adobe-acrobat.md",
  GoogleChromeEnterprise:"google-chrome.md",
  MozillaFirefoxEnterprise:"mozilla-firefox.md",
  CiscoWebex:"cisco-webex.md",
  ZoomWorkplace:"zoom-workplace.md",
  "7Zip":"7zip.md",
  VisualStudioCode:"visual-studio-code.md",
  VisualCRedist:"runtime-prerequisites.md",
  DotNetRuntime:"runtime-prerequisites.md",
  WindowsInboxCleanup:"windows-inbox-cleanup.md",
  WindowsFeatures:"windows-features.md",
  WindowsCapabilities:"windows-capabilities.md",
  MicrosoftCompanyPortal:"microsoft-company-portal.md",
  CMTraceOpen:"cmtrace-open.md",
  WiFiProfiles:"wifi-staging.md",
  Certificates:"certificate-staging.md",
  EnvironmentVariables:"environment-variables.md",
  FileSystem:"file-system.md",
  Services:"services.md",
  DesktopSettings:"desktop-settings.md",
  DefaultAssociations:"default-associations.md",
  RegistrySettings:"registry-staging.md",
  WindowsUpdate:"windows-update.md"
};
let repositoryRequest=0,repositoryController;

const ICONS={
  grid:`<svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>`,
  cube:`<svg viewBox="0 0 24 24"><path d="m12 2 8 4.5v9L12 20l-8-4.5v-9Z"/><path d="m4 6.5 8 4.5 8-4.5M12 11v9"/></svg>`,
  database:`<svg viewBox="0 0 24 24"><ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v6c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 11v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/></svg>`,
  monitor:`<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>`,
  search:`<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg>`,
  github:`<svg viewBox="0 0 24 24"><path d="M9 19c-4.5 1.4-4.5-2.2-6-2.7m12 5v-3.6c0-1 .1-1.4-.5-2 2.8-.3 5.8-1.4 5.8-6.3A5 5 0 0 0 19 6c.1-.3.6-1.7-.1-3.4 0 0-1.1-.3-3.6 1.3a12.6 12.6 0 0 0-6.6 0C6.2 2.3 5.1 2.6 5.1 2.6 4.4 4.3 4.9 5.7 5 6a5 5 0 0 0-1.3 3.4c0 4.9 3 6 5.8 6.3-.4.4-.7 1-.7 2V21"/></svg>`
};

document.querySelectorAll("[data-icon]").forEach(el=>{el.innerHTML=ICONS[el.dataset.icon]||""});

function esc(v){return String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#039;")}
function text(v,fallback=""){return typeof v==="string"?v:fallback}
function strings(v){return Array.isArray(v)?v.filter(x=>typeof x==="string"&&x.trim()).map(x=>x.trim()):[]}
function status(id,msg,level="info"){const el=$(id);el.textContent=msg;el.dataset.level=level;el.hidden=!msg}
function httpUrl(value,base){
  if(typeof value!=="string"||!value.trim())throw new Error("A valid HTTP(S) URL is required.");
  const u=new URL(value.replaceAll("\\","/"),base);
  if(!["http:","https:"].includes(u.protocol)||u.username||u.password)throw new Error("Only HTTP(S) URLs without embedded credentials are supported.");
  return u.href;
}
function safeUrl(value,base){try{return httpUrl(value,base)}catch{return ""}}
function displayUrl(value){const u=new URL(value);return u.origin+u.pathname+(u.search?"?…":"")}
function saveView(){try{localStorage.setItem("osdstage.viewer.display",JSON.stringify({view:state.view,pageSize:state.pageSize}))}catch{}}
function restoreView(){
  try{const saved=JSON.parse(localStorage.getItem("osdstage.viewer.display")||"null");
    if(saved&&["tiles","list"].includes(saved.view))state.view=saved.view;
    if(saved&&[12,24,48,96,"all"].includes(saved.pageSize))state.pageSize=saved.pageSize;
  }catch{}
  $("pageSize").value=String(state.pageSize);
}
function initials(name){return (name||"?").split(/\s+/).slice(0,2).map(x=>x[0]||"").join("").toUpperCase()}
function packageType(value){const normalized=text(value,"App").toLowerCase();const result=normalized==="application"?"App":TYPES.find(x=>x.toLowerCase()===normalized);if(!result)throw new Error("Unsupported package type.");return result}
function packagesFrom(data){
  if(!data||typeof data!=="object"||Array.isArray(data))throw new Error("Expected a JSON object.");
  if(data.SchemaVersion!==2)throw new Error("Unsupported schema version.");
  const packages=data.Packages;
  if(!Array.isArray(packages))throw new Error("Expected a Packages array in the schema 2 JSON document.");
  return packages;
}
async function getJson(value,signal){
  const url=httpUrl(value),controller=new AbortController();
  const abort=()=>controller.abort();
  signal?.addEventListener("abort",abort,{once:true});
  if(signal?.aborted)controller.abort();
  const timer=setTimeout(abort,15000);
  try{
    const r=await fetch(url,{cache:"no-store",credentials:"omit",referrerPolicy:"no-referrer",signal:controller.signal});
    if(!r.ok)throw new Error(`HTTP ${r.status}`);
    try{return await r.json()}catch{throw new Error("Response is not valid JSON.")}
  }catch(e){
    if(signal?.aborted)throw e;
    if(controller.signal.aborted)throw new Error("Request timed out after 15 seconds.");
    if(e instanceof TypeError)throw new Error("Browser request failed. Check the URL, network, HTTPS and server CORS settings.");
    throw e;
  }finally{clearTimeout(timer);signal?.removeEventListener("abort",abort)}
}
function normalizeBuiltIn(x){
  if(!x||!text(x.Id))throw new Error("Built-in component is missing Id.");
  const bundled=x.Acquisition==="BundledScript",phase=text(x.SyncPhase,"Unknown");
  const phaseLabel={None:"No download / cache",FullWindowsPreparation:"Full Windows preparation",FullWindowsPreInstall:"Full Windows PreInstall"}[phase]||phase;
  const description=bundled
    ?"Included with OSDStage. Configuration is staged in WinPE and applied once during SetupComplete."
    :phase==="FullWindowsPreparation"
      ?"Evergreen built-in integration. Prepare supported vendor content in full Windows, then reuse the verified cache during staging."
      :"Evergreen built-in integration. During an online deployment, OSDStage resolves supported vendor content when acquisition runs; valid cached content can be reused.";
  return {
    id:x.Id,displayName:text(x.DisplayName,x.Id),source:"BuiltIn",vendor:text(x.Vendor),
    version:bundled?"Included with module":x.DefaultChannel?`Evergreen · ${x.DefaultChannel}`:"Evergreen",
    architectures:strings(x.Architectures).map(a=>a.toLowerCase()),packageType:packageType(x.PackageType),
    commands:[text(x.AddCommand),...strings(x.AdditionalAddCommands)],
    syncPhase:phaseLabel,acquisition:text(x.Acquisition,"Unknown"),command:text(x.AddCommand),
    metadataUrl:BUILTINS_URL,documentationUrl:DOC_ROOT+(DOC_URLS[x.Id]||"built-in-apps.md"),packageUrl:"",iconUrl:safeUrl(x.IconUrl,BUILTINS_URL),description,aliases:[],certificateStore:""
  };
}
function normalizeRepository(app,pkg,m,url){
  if(!m||m.SchemaVersion!==2)throw new Error("Manifest requires SchemaVersion 2.");
  if(!text(m.Id).trim())throw new Error("Manifest is missing Id.");
  const warnings=[];
  if(m.Id.toLowerCase()!==app.Id.toLowerCase())warnings.push(`Catalog Id '${app.Id}' differs from manifest Id '${m.Id}'. Make these IDs identical before deploying this package.`);
  if(!text(m.Architecture)||m.Architecture.toLowerCase()!==pkg.Architecture.toLowerCase())throw new Error("Manifest architecture does not match the catalog.");
  if(!text(m.Version).trim())throw new Error("Manifest is missing Version.");
  const type=packageType(m.PackageType);
  if(!m.Payload||!/^[a-f\d]{64}$/i.test(text(m.Payload.Sha256)))throw new Error("Manifest requires a payload SHA-256.");
  if(m.Payload.FileName!=="Package.zip")throw new Error("Payload filename must be Package.zip.");
  const store=type==="Certificate"?text(m.CertificateStore):"";
  if(type==="Certificate"&&!/^(Root|CA)$/i.test(store))throw new Error("CertificateStore must be Root or CA.");
  const command={Font:"Add-OSDStageFont",Certificate:"Add-OSDStageCertificate",Driver:"Add-OSDStageDriver"}[type]||"Add-OSDStage";
  return {
    id:app.Id,manifestId:m.Id,warnings,displayName:text(m.DisplayName,app.Id),source:"Repository",vendor:text(m.Vendor,"Organization"),
    version:m.Version,architectures:[m.Architecture.toLowerCase()],packageType:type,
    syncPhase:"WinPE sync / cache",acquisition:"Repository Package.zip",command:`${command} ${type==="App"||type==="Script"?"-Name":"-Id"} '${app.Id}'`,
    metadataUrl:url,packageUrl:httpUrl("Package.zip",url),iconUrl:safeUrl(m.IconUrl,url),
    aliases:strings(app.Aliases),certificateStore:store,
    description:type==="Certificate"?`Public certificates for the computer certificate store (LocalMachine\\${store}).`:type==="Driver"?"Repository driver package. Drivers are added to the Windows Driver Store during SetupComplete.":type==="Font"?"Repository font package. Fonts are installed for the computer during SetupComplete.":"Organization-managed package. Content is synchronized/cached and staged in WinPE."
  };
}
async function loadBuiltIns(){
  status("builtinStatus","Loading built-in metadata…");
  try{
    const rows=packagesFrom(await getJson(BUILTINS_URL));
    state.builtins=rows.map(normalizeBuiltIn);
    status("builtinStatus","");
  }catch(e){status("builtinStatus",`Built-in metadata could not be loaded: ${e.message}`,"error")}
  render();
}
function catalogReferences(c){
  const seen=new Set();
  return packagesFrom(c).flatMap(app=>{
    if(!app||!text(app.Id)||! /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(app.Id)||app.Id.includes(".."))throw new Error("Catalog contains an invalid package Id.");
    if(seen.has(app.Id.toLowerCase()))throw new Error("Catalog contains duplicate package Ids.");
    seen.add(app.Id.toLowerCase());
    if(!Array.isArray(app.Architectures))throw new Error(`Architectures array missing for ${app.Id}.`);
    const architectures=new Set();
    return app.Architectures.map(pkg=>{
      const arch=text(pkg?.Architecture).toLowerCase();
      if(!["x86","x64","arm64","any"].includes(arch))throw new Error(`Invalid architecture for ${app.Id}.`);
      if(architectures.has(arch))throw new Error(`Duplicate architecture for ${app.Id}: ${arch}.`);
      architectures.add(arch);return {app,pkg};
    });
  });
}
async function loadRepository(value){
  const request=++repositoryRequest;
  repositoryController?.abort();repositoryController=new AbortController();
  const signal=repositoryController.signal;
  $("loadErrors").hidden=true;$("errorList").replaceChildren();
  status("repoStatus","Loading repository…");
  try{
    const base=httpUrl(value),refs=catalogReferences(await getJson(base,signal));
    const results=new Array(refs.length);let next=0;
    await Promise.all(Array.from({length:Math.min(6,refs.length)},async()=>{
      while(next<refs.length&&!signal.aborted){
        const i=next++,{app,pkg}=refs[i];
        try{
          if(!pkg||!text(pkg.Architecture)||!text(pkg.Manifest))throw new Error("Package reference needs Architecture and Manifest.");
          const url=httpUrl(pkg.Manifest,base);
          results[i]={value:normalizeRepository(app,pkg,await getJson(url,signal),url)};
        }catch(e){results[i]={error:`${app.Id} (${text(pkg?.Architecture,"unknown")}): ${e.message}`}}
      }
    }));
    if(request!==repositoryRequest)return;
    const successful=results.filter(r=>r?.value).map(r=>r.value),failures=results.filter(r=>r?.error).map(r=>r.error);
    const warnings=successful.flatMap(row=>row.warnings||[]);
    for(const error of [...failures,...warnings]){const li=document.createElement("li");li.textContent=error;$("errorList").append(li)}
    $("loadErrors").hidden=!(failures.length||warnings.length);
    if(refs.length&&successful.length===0){status("repoStatus",`Repository not loaded: all ${failures.length} package manifests failed. Previous results retained.`,"error");return}
    state.repository=successful;
    $("repoLink").textContent=displayUrl(base);$("repoLink").href=base;$("repoLink").rel="noreferrer";$("repoLink").target="_blank";
    $("repoLink").hidden=false;$("clearRepository").hidden=false;render();
    status("repoStatus",`Repository: ${successful.length}/${refs.length} loaded.${failures.length?` ${failures.length} failed; see details below.`:""}${warnings.length?` ${warnings.length} warning(s); see details below.`:""}`,failures.length||warnings.length?"warning":"info");
  }catch(e){if(request===repositoryRequest)status("repoStatus",`Unable to load repository: ${e.message} Previous results retained.`,"error")}
}
function clearRepository(){
  ++repositoryRequest;repositoryController?.abort();state.repository=[];
  $("catalogUrl").value="";$("repoLink").hidden=true;$("repoLink").removeAttribute("href");
  $("clearRepository").hidden=true;$("loadErrors").hidden=true;$("errorList").replaceChildren();
  status("repoStatus","");render();
}
function render(){
  const all=[...state.builtins,...state.repository];
  $("allCount").textContent=all.length;$("builtinCount").textContent=state.builtins.length;$("repoCount").textContent=state.repository.length;
  $("repositoryToggle").textContent=state.repository.length?"Repository settings":"+ Add repository";
  const arches=[...new Set(all.flatMap(x=>x.architectures))].sort();
  const select=$("archFilter"),cur=select.value;
  select.innerHTML='<option value="">All architectures</option>'+arches.map(x=>`<option value="${esc(x)}">${x==="any"?"Architecture-independent":esc(x)}</option>`).join("");
  if(arches.includes(cur))select.value=cur;
  filter();
}
function filter(){
  state.page=1;
  const q=$("search").value.trim().toLowerCase(),src=$("sourceFilter").value,arch=$("archFilter").value,type=$("typeFilter").value;
  state.filtered=[...state.builtins,...state.repository]
    .filter(x=>!src||x.source===src).filter(x=>!type||componentType(x)===type)
    .filter(x=>!arch||x.architectures.includes(arch)||x.architectures.includes("any"))
    .filter(x=>!q||[x.id,x.displayName,x.vendor,x.version,x.syncPhase,x.acquisition,x.packageType,x.certificateStore,componentType(x),x.command,...(x.commands||[]),...x.aliases,...x.architectures].some(v=>String(v).toLowerCase().includes(q)))
    .sort((a,b)=>a.displayName.localeCompare(b.displayName)||a.source.localeCompare(b.source));
  renderPage();
}
function renderPage(){
  const total=state.filtered.length,size=state.pageSize==="all"?Math.max(total,1):state.pageSize;
  const pages=Math.max(1,Math.ceil(total/size));state.page=Math.min(Math.max(state.page,1),pages);
  const start=(state.page-1)*size,items=state.filtered.slice(start,start+size);
  $("resultSummary").textContent=total?`${start+1}–${start+items.length} of ${total} components`:"0 components";
  $("pageSummary").textContent=total?`Page ${state.page} of ${pages}`:"No results";
  $("previousPage").disabled=state.page===1;$("nextPage").disabled=state.page===pages;
  $("tileView").setAttribute("aria-pressed",String(state.view==="tiles"));
  $("listView").setAttribute("aria-pressed",String(state.view==="list"));
  $("cards").className=state.view==="list"?"package-list":"cards";
  $("cards").innerHTML=items.length?items.map(state.view==="list"?listRow:card).join(""):'<div class="panel empty-state">No components match the current filters.</div>';
}
function changePage(delta){state.page+=delta;renderPage();document.querySelector(".results-toolbar").scrollIntoView({block:"start"})}
function setView(view){state.view=view;saveView();renderPage()}
function componentType(x){return x.source==="BuiltIn"&&x.acquisition==="BundledScript"?"Configuration":x.packageType}
function commandMarkup(x){return (x.commands||[x.command]).map(c=>`<span class="command" title="Starting point; additional parameters may be required.">${esc(c)}</span>`).join("")}
function badges(x){return `<span class="badge ${x.source==="BuiltIn"?"builtin":"repository"}">${x.source==="BuiltIn"?"BUILT-IN":"YOUR REPOSITORY"}</span><span class="badge type">${esc(componentType(x))}</span>${x.architectures.map(a=>`<span class="badge arch">${esc(a)}</span>`).join("")}`}
function listRow(x){
  return `<details class="package-row panel">
    <summary><div class="row-name"><div class="app-icon">${appIcon(x)}</div><div><span class="row-title">${esc(x.displayName)}</span><span class="app-subtitle">${esc(x.id)} · ${esc(x.vendor)}</span></div></div>
      <span class="row-version">${esc(x.version)}</span><span class="badges">${badges(x)}</span><span class="row-chevron" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="m7 9 5 5 5-5"/></svg></span>
    </summary>
    <div class="row-details"><p class="description">${esc(x.description)}</p><p class="row-preparation">${esc(x.syncPhase)} · ${esc(x.acquisition)}</p>
      ${(x.warnings||[]).map(w=>`<p class="package-warning">${esc(w)}</p>`).join("")}
      <div class="card-footer">${commandMarkup(x)}${x.source==="BuiltIn"?link(x.documentationUrl,"View command documentation"):link(x.metadataUrl,"Manifest JSON")}${link(x.packageUrl,"Package.zip")}</div>
    </div></details>`;
}

function link(url,label){const href=safeUrl(url);return href?`<a href="${esc(href)}" target="_blank" rel="noreferrer">${esc(label)} ↗</a>`:""}
function appIcon(x){
  const icon={Font:"fonts",Certificate:"certificates",Driver:"drivers",Script:"script"}[x.packageType];
  const fallback=icon?`<img class="type-icon" src="../metadata/icons/${icon}.svg" alt="">`:`<span class="fallback-icon">${esc(initials(x.displayName))}</span>`;
  const url=safeUrl(x.iconUrl);
  return url?`<img src="${esc(url)}" alt="" loading="lazy" referrerpolicy="no-referrer"><span hidden>${fallback}</span>`:fallback;
}
function card(x){
  return `<article class="card panel">
    <div class="card-head"><div class="title-wrap"><div class="app-icon">${appIcon(x)}</div><div>
      <h2>${esc(x.displayName)}</h2><div class="app-subtitle">${esc(x.id)} · ${esc(x.vendor)}</div>
    </div></div><div class="badges">
      <span class="badge ${x.source==="BuiltIn"?"builtin":"repository"}">${x.source==="BuiltIn"?"BUILT-IN":"YOUR REPOSITORY"}</span>
      <span class="badge type">${esc(componentType(x))}</span>
      ${x.architectures.map(a=>`<span class="badge arch">${esc(a)}</span>`).join("")}
    </div></div>
    <div class="meta-grid">
      <div class="meta-item"><span class="meta-label">Version / channel</span><div class="meta-value">${esc(x.version)}</div></div>
      <div class="meta-item"><span class="meta-label">Content preparation</span><div class="meta-value">${esc(x.syncPhase)}</div></div>
      <div class="meta-item"><span class="meta-label">Acquisition</span><div class="meta-value">${esc(x.acquisition)}</div></div>
    </div>
    <p class="description">${esc(x.description)}</p>
    ${(x.warnings||[]).map(w=>`<p class="package-warning">${esc(w)}</p>`).join("")}
    <div class="card-footer">${commandMarkup(x)}
      ${x.source==="BuiltIn"?link(x.documentationUrl,"View command documentation"):link(x.metadataUrl,"Manifest JSON")}${link(x.packageUrl,"Package.zip")}
    </div>
  </article>`;
}
const repositoryToggle=$("repositoryToggle"),repositoryPanel=$("repositoryPanel");
function setRepositoryPanel(open){
  repositoryPanel.hidden=!open;
  repositoryToggle.setAttribute("aria-expanded",String(open));
}
repositoryToggle.addEventListener("click",()=>setRepositoryPanel(repositoryPanel.hidden));

$("cards").addEventListener("error",e=>{if(e.target.tagName==="IMG"){const fallback=e.target.nextElementSibling;if(fallback)fallback.hidden=false;e.target.remove()}},true);
$("catalogForm").addEventListener("submit",e=>{e.preventDefault();const u=$("catalogUrl").value.trim();if(u)loadRepository(u)});
$("clearRepository").addEventListener("click",clearRepository);
$("tileView").addEventListener("click",()=>setView("tiles"));
$("listView").addEventListener("click",()=>setView("list"));
$("previousPage").addEventListener("click",()=>changePage(-1));
$("nextPage").addEventListener("click",()=>changePage(1));
$("pageSize").addEventListener("change",()=>{const value=$("pageSize").value;state.pageSize=value==="all"?"all":Number(value);state.page=1;saveView();renderPage()});
$("search").addEventListener("input",filter);
for(const id of ["sourceFilter","archFilter","typeFilter"])$(id).addEventListener("change",filter);
restoreView();
render();
loadBuiltIns();
const requestedCatalog=new URLSearchParams(location.search).get("catalog");
if(requestedCatalog){$("catalogUrl").value=requestedCatalog;setRepositoryPanel(true);loadRepository(requestedCatalog)}
