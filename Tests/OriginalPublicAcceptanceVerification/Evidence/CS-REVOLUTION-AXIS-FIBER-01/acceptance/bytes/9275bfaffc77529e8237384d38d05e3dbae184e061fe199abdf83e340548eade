import {readFile} from "node:fs/promises";
import {WASI} from "node:wasi";
const [path,group]=process.argv.slice(2);
const wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group},preopens:{},returnOnExit:true});
const module=await WebAssembly.compile(await readFile(path));
const instance=await WebAssembly.instantiate(module,wasi.getImportObject());
const code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);
