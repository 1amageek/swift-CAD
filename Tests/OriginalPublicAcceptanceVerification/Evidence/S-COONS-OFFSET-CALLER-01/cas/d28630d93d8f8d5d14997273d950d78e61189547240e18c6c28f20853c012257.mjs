import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";
const argumentsAfterExecutable = process.argv.slice(2);
if (argumentsAfterExecutable.length !== 2) {
    throw new Error("Usage: node run_wasi_group.mjs <artifact.wasm> <proof-group>");
}
const [path, group] = argumentsAfterExecutable;
const wasi = new WASI({version:"preview1", args:[path, group], env:{CAD_PROOF_GROUP:group}, preopens:{}, returnOnExit:true});
const module = await WebAssembly.compile(await readFile(path));
const instance = await WebAssembly.instantiate(module,wasi.getImportObject());
const code=wasi.start(instance); if(code!==0) throw new Error(`WASI exit ${code}`);
