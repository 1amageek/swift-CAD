import { WASI } from 'node:wasi';
import { readFile } from 'node:fs/promises';
const path = process.argv[2];
const wasi = new WASI({ version: 'preview1', args: [path], env: {}, preopens: {} });
const module = await WebAssembly.compile(await readFile(path));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
wasi.start(instance);
