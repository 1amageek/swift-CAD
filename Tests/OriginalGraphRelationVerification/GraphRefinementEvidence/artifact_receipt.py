"""Admit cached artifacts only from a successful, source-bound generation receipt."""
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_generation(receipt_path, cache_root, required_inputs, required_artifacts):
    receipt_path = Path(receipt_path).resolve()
    receipt_bytes = receipt_path.read_bytes()
    receipt = json.loads(receipt_bytes)
    runs = receipt.get("runs", [])
    if receipt.get("success") is not True or not runs or any(r.get("exitCode") != 0 for r in runs):
        raise RuntimeError("Lower generation did not complete successfully")
    if not receipt.get("logs"):
        raise RuntimeError("Lower generation logs are not bound")

    def resolve(name):
        return (cache_root / name).resolve()

    checked = {str(receipt_path): hashlib.sha256(receipt_bytes).hexdigest()}
    for section, required in [("inputs", required_inputs), ("artifacts", required_artifacts)]:
        recorded = {str(resolve(p)): h for p, h in receipt.get(section, {}).items()}
        for name, expected in required.items():
            path = str(resolve(name))
            if path not in recorded:
                raise RuntimeError("Missing generation " + section + ": " + path)
            if expected is not None and recorded[path] != expected:
                raise RuntimeError("Changed generation premise: " + path)
            if digest(path) != recorded[path]:
                raise RuntimeError("Overwritten generation " + section + ": " + path)
            checked[path] = recorded[path]
    for name, expected in receipt["logs"].items():
        path = str(resolve(name))
        if digest(path) != expected:
            raise RuntimeError("Changed generation log: " + path)
        checked[path] = expected
    return checked
