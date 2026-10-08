import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
LANE = sys.argv[1]
CONFIGURATION = "Debug-webassembly-wasm32" if LANE in ("wasm", "embedded") else "Debug"
PRODUCTS = ROOT / ".build" / ("public-" + LANE) / "out/Products" / CONFIGURATION
GROUPS = ["public-cs-limit-early", "public-cs-candidate-ordinary", "public-cs-candidate-admitted", "public-cs", "public-cs-weighted", "ssi-images", "ssi-failures", "public-ssi-cover-ordinary", "smoke"]
runtime_path = EVIDENCE / (LANE + "-runtime.json")
RESULTS = [item for item in json.loads(runtime_path.read_text()) if item["exit"] == 0] if runtime_path.exists() else []
for group in GROUPS:
    if any(item["group"] == group for item in RESULTS):
        continue
    smoke = group == "smoke"
    name = "CADIntersectionPortabilitySmoke" if smoke else "NativeExactGeometricProof"
    if LANE in ("wasm", "embedded"):
        script = "run_wasi_smoke.mjs" if smoke else "run_wasi_group.mjs"
        script_path = ROOT / "Scripts" / script if smoke else ROOT / "Tests/NativeExactRelationVerification/Scripts" / script
        command = ["/usr/local/bin/node", str(script_path), str(PRODUCTS / (name + ".wasm"))]
    else:
        command = [str(PRODUCTS / name)]
    if not smoke:
        command.append(group)
    log = EVIDENCE / (LANE + "-" + group + ".log")
    start = time.monotonic()
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, cwd=ROOT, start_new_session=True)
        try:
            code = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            code = 124
    result = {"group": group, "exit": code, "seconds": time.monotonic() - start, "command": command, "timeout_seconds": 120}
    RESULTS.append(result)
    print(LANE, group, code, round(result["seconds"], 3), flush=True)
    (EVIDENCE / (LANE + "-runtime.json")).write_text(json.dumps(RESULTS, indent=2) + "\n")
    if code:
        sys.exit(code)
