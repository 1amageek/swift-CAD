import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";

const argumentsAfterExecutable = process.argv.slice(2);

if (argumentsAfterExecutable.length !== 1) {
    throw new Error("Usage: node run_wasi_smoke.mjs <executable.wasm>");
}

const executablePath = argumentsAfterExecutable[0];
const wasi = new WASI({
    version: "preview1",
    args: [executablePath],
    env: {},
    preopens: {},
    returnOnExit: true,
});

const module = await WebAssembly.compile(await readFile(executablePath));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());

if (!(instance.exports.memory instanceof WebAssembly.Memory)) {
    throw new Error("The WebAssembly executable does not export linear memory");
}

console.log(`WASI linear memory: ${instance.exports.memory.buffer.byteLength} bytes`);

const exitCode = wasi.start(instance);

if (exitCode !== 0) {
    throw new Error(`The WebAssembly executable exited with code ${exitCode}`);
}
