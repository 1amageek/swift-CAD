import hashlib, json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
evidence = root / "Tests/OriginalDomainIdentityVerification/Evidence"
inputs = json.loads((evidence / "source-hashes.json").read_text())
for relative, expected in inputs.items():
    actual = hashlib.sha256((root / relative).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit("Changed verification input: " + relative)
receipt = json.loads((evidence / "receipt.json").read_text())
for relative, expected in receipt["evidence_hashes"].items():
    if hashlib.sha256((evidence / relative).read_bytes()).hexdigest() != expected:
        raise SystemExit("Changed evidence: " + relative)
print("PASS retained isolated inputs:", len(inputs), "and all bound evidence")
