const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');
const root=path.join(__dirname,'..');
const builtin=JSON.parse(fs.readFileSync(path.join(root,'dist/site/metadata/builtins.json'),'utf8'));
const builtinUrl='https://example.test/OSDStage/metadata/builtins.json',catalog='https://repo.example.test/catalog.json';
const fixtures={[builtinUrl]:builtin,[catalog]:{SchemaVersion:2,Packages:[]}};
for(const type of ['App','Script','Font','Certificate','Driver']){
 const id='Example'+type,manifest=`${id}/manifest.json`,entry={SchemaVersion:2,Id:id,DisplayName:`Example ${type}`,Version:'1.0.0',Architecture:'any',PackageType:type,Payload:{FileName:'Package.zip',Sha256:'A'.repeat(64)}};
 if(type==='Certificate')entry.CertificateStore='Root';
 fixtures[catalog].Packages.push({Id:id,Architectures:[{Architecture:'any',Manifest:manifest}]});fixtures[new URL(manifest,catalog).href]=entry;
}
function setup(saved=null,search=''){
 const nodes=new Map(),requests=[],store=new Map(saved?[['osdstage.viewer.display',JSON.stringify(saved)]]:[]);
 const node=id=>{if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',innerHTML:'',hidden:false,dataset:{},listeners:{},attributes:{},setAttribute(k,v){this.attributes[k]=v},addEventListener(k,f){this.listeners[k]=f},replaceChildren(){},append(){},removeAttribute(k){delete this.attributes[k]},scrollIntoView(){}});return nodes.get(id)};
 const context=vm.createContext({URL,URLSearchParams,AbortController,setTimeout,clearTimeout,console,location:{search,href:'https://example.test/OSDStage/catalog/index.html'+search},localStorage:{getItem:k=>store.get(k)||null,setItem:(k,v)=>store.set(k,v)},document:{getElementById:node,querySelectorAll(){return []},querySelector:()=>node('toolbar'),createElement:()=>({textContent:''})},fetch:async(url,opts)=>{requests.push(url);assert.equal(opts.credentials,'omit');return {ok:!!fixtures[url],status:fixtures[url]?200:404,json:async()=>fixtures[url]}}});
 vm.runInContext(fs.readFileSync(path.join(root,'site/catalog/app.js'),'utf8'),context);
 return {node,requests,store,run:s=>vm.runInContext(s,context)};
}
const tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 const {node,requests,store,run}=setup();await tick();const count=builtin.Packages.length;
 assert.deepEqual(requests,[builtinUrl]);assert.equal(run('state.repository.length'),0);assert.equal(run('state.filtered.length'),count);
 assert.equal(node('resultSummary').textContent,`1–12 of ${count} entries`);
 run('changePage(1)');assert.equal(node('resultSummary').textContent,`13–${count} of ${count} entries`);assert.equal(node('nextPage').disabled,true);
 node('search').value='StartPins';run('filter()');assert.equal(run('state.page'),1);assert.match(node('cards').innerHTML,/Add-OSDStageStartPins/);
 node('search').value='no-such-item';run('filter()');assert.equal(node('pageSummary').textContent,'No results');assert.equal(node('nextPage').disabled,true);
 node('search').value='';run('filter()');run('setView("list")');assert.equal(node('cards').className,'package-list');assert.equal(node('listView').attributes['aria-pressed'],'true');
 node('pageSize').value='24';node('pageSize').listeners.change();assert.equal((node('cards').innerHTML.match(/<details /g)||[]).length,count);
 await run(`loadRepository(${JSON.stringify(catalog)})`);assert.equal(run('state.repository.length'),5);
 node('pageSize').value='all';node('pageSize').listeners.change();assert.equal(node('resultSummary').textContent,`1–${count+5} of ${count+5} entries`);
 for(const type of ['App','Script','Font','Certificate','Driver']){node('sourceFilter').value='Repository';node('typeFilter').value=type;run('filter()');assert.equal(run('state.filtered.length'),1)}
 await run('loadRepository("https://bad.example/catalog.json")');assert.equal(run('state.repository.length'),5);assert.match(node('repoStatus').textContent,/Previous results retained/);
 run('clearRepository()');assert.equal(run('state.repository.length'),0);assert.equal(node('repoLink').hidden,true);
 const restored=setup(JSON.parse(store.get('osdstage.viewer.display')));assert.equal(restored.run('state.view'),'list');assert.equal(restored.run('state.pageSize'),'all');
 const invalid=setup({view:'bad',pageSize:0});assert.equal(invalid.run('state.pageSize'),12);
 assert.throws(()=>run('catalogReferences({SchemaVersion:1,Apps:[]})'),/schema/);
 assert.throws(()=>run('httpUrl("javascript:alert(1)")'),/HTTP/);
 assert.throws(()=>run('httpUrl("https://user:password@example.test")'),/credentials/);
 assert.equal(run('esc("<img src=x onerror=alert(1)>")'),'&lt;img src=x onerror=alert(1)&gt;');
 const explicit=setup(null,'?catalog='+encodeURIComponent(catalog));await tick();assert.equal(explicit.run('state.repository.length'),5);
 console.log('PASS: project path, no default repo, all package types, pagination, filters, view settings, explicit catalog URL, failure retention and escaped content.');
})().catch(e=>{console.error(e);process.exitCode=1});
