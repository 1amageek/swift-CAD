import argparse, hashlib, json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--evidence", default="Tests/OriginalDomainIdentityVerification/Evidence")
args = parser.parse_args()
evidence = root / args.evidence
inputs = json.loads((evidence / "source-hashes.json").read_text())
for relative, expected in inputs.items():
    actual = hashlib.sha256((root / relative).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit("Changed verification input: " + relative)
receipt = json.loads((evidence / "receipt.json").read_text())
for generated, expected in receipt.get("generated_inputs", {}).items():
    if hashlib.sha256(Path(generated).read_bytes()).hexdigest() != expected:
        raise SystemExit("Changed retained generated input: " + generated)
for relative, expected in receipt["evidence_hashes"].items():
    if hashlib.sha256((evidence / relative).read_bytes()).hexdigest() != expected:
        raise SystemExit("Changed evidence: " + relative)
print("PASS retained isolated inputs:", len(inputs), "generated:", len(receipt.get("generated_inputs", {})), "and all bound evidence")
