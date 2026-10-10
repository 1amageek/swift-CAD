#!/usr/bin/env python3
"""Compare generation-bound baseline and improved refinement processes serially."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import statistics
import subprocess
import time
from artifact_receipt import digest

parser = argparse.ArgumentParser()
parser.add_argument("--baseline", type=Path, required=True)
parser.add_argument("--candidate", type=Path, required=True)
parser.add_argument("--baseline-commit", required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--repeats", type=int, default=3)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
if args.repeats < 1 or args.output.exists():
    raise RuntimeError("Positive repeats and a fresh output directory are required")
args.output.mkdir(parents=True)
records = []


def admit(path, baseline):
    path = path.resolve()
    generation = json.loads(path.read_text())
    if generation.get("success") is not True or not generation.get("runs") or not generation.get("logs"):
        raise RuntimeError("Missing successful generation")
    if any(run.get("exitCode") != 0 for run in generation["runs"]):
        raise RuntimeError("Failed generation")
    checked, snapshots = {str(path): digest(path)}, {}
    for section in ["inputs", "artifacts", "logs"]:
        if not generation.get(section):
            raise RuntimeError("Missing generation section: " + section)
        for name, expected in generation[section].items():
            item = Path(name).resolve()
            actual = digest(item)
            if actual != expected:
                # Baseline source bytes belong to the committed generation snapshot.
                # Executables, compiler, emitted objects/modules and logs must still match.
                if not baseline or section != "inputs" or not item.is_relative_to(root):
                    raise RuntimeError("Changed generation premise: " + name)
                relative = item.relative_to(root)
                if ".build" in relative.parts:
                    raise RuntimeError("Changed generated premise: " + name)
                original = subprocess.check_output(["git", "show", args.baseline_commit + ":" + str(relative)], cwd=root)
                if hashlib.sha256(original).hexdigest() != expected:
                    raise RuntimeError("Baseline snapshot mismatch: " + name)
                snapshots[str(relative)] = expected
            else:
                checked[str(item)] = expected
    products = [name for name in generation["artifacts"] if name.endswith("/GraphProof")]
    if len(products) != 1:
        raise RuntimeError("Expected one Native proof product")
    return products[0], checked, snapshots


premises = {}
for name, path in [("baseline", args.baseline), ("candidate", args.candidate)]:
    product, checked, snapshots = admit(path, name == "baseline")
    premises[name] = dict(product=product, generationSHA256=digest(path),
                          checked=checked, committedSourceOverrides=snapshots)
for repeat in range(args.repeats):
    order = ["baseline", "candidate"] if repeat % 2 == 0 else ["candidate", "baseline"]
    for name in order:
        product, checked, _ = admit(args.baseline if name == "baseline" else args.candidate, name == "baseline")
        log = args.output / (str(repeat) + "-" + name + ".log")
        cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
        start = time.monotonic()
        with log.open("w") as output:
            process = subprocess.Popen([product], cwd=root, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=120)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise
        elapsed = time.monotonic() - start
        end = resource.getrusage(resource.RUSAGE_CHILDREN)
        for path, expected in checked.items():
            if digest(path) != expected:
                raise RuntimeError("Premise changed during measurement: " + path)
        if code != 0 or "PASS graph refinement descendant-field membership and foreign-field refusal" not in log.read_text():
            raise RuntimeError("Refinement fixture failed: " + name)
        records.append(dict(repeat=repeat, lane=name, elapsedSeconds=elapsed,
            userSeconds=end.ru_utime-cpu.ru_utime, systemSeconds=end.ru_stime-cpu.ru_stime,
            exitCode=code, log=log.name, logSHA256=digest(log), productSHA256=digest(product)))
        print(name, repeat, round(elapsed,3), flush=True)
        (args.output / "runs.json").write_text(json.dumps(records, indent=2) + "\n")
medians = {name: statistics.median(r["elapsedSeconds"] for r in records if r["lane"] == name)
           for name in premises}
(args.output / "receipt.json").write_text(json.dumps(dict(premises=premises,
    benchmarkSHA256=digest(__file__), baselineCommit=args.baseline_commit, runs=records,
    mediansSeconds=medians, speedup=medians["baseline"]/medians["candidate"],
    scope="Identical fixed Swift6.4.0 debug Native fixture, separate serial processes, alternating order; hash admission outside timing."), indent=2) + "\n")
print(medians, flush=True)
