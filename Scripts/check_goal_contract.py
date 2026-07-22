#!/usr/bin/env python3

from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys


EXPECTED_GATES = tuple(f"G{index}" for index in range(8))
REMOVED_DOCUMENTS = (
    "CAD_KERNEL_REQUIREMENTS.md",
    "DEVELOPMENT_ROADMAP.md",
    "PHILOSOPHY.md",
)
EVIDENCE_LINK_PATTERN = re.compile(
    r"^\[gate evidence\]\((?P<path>Evidence/(?P<gate>G[0-7])\.json)\)$"
)
REVISION_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
REQUIRED_EVIDENCE_KINDS = {
    "G0": {
        "isolated-macos-build",
        "isolated-ios-build",
        "isolated-visionos-build",
        "isolated-wasm-build",
        "wasm-runtime-smoke",
        "schema-contract",
        "policy-contract",
        "capability-contract",
    },
    "G1": {
        "geometry-property-suite",
        "geometry-oracle-comparison",
        "intersection-matrix",
        "implicit-intersection-representation-suite",
        "predicate-adversarial-suite",
    },
    "G2": {
        "topology-invariant-suite",
        "topology-oracle-comparison",
        "lineage-edit-suite",
        "repair-suite",
    },
    "G3": {
        "modeling-capability-suite",
        "general-boolean-suite",
        "modeling-command-parity",
        "no-mesh-fallback-audit",
    },
    "G4": {
        "public-api-inventory",
        "command-parity-suite",
        "query-parity-suite",
        "stable-selection-edit-suite",
        "cache-determinism-suite",
    },
    "G5": {
        "constraint-relation-suite",
        "jacobian-oracle-comparison",
        "constraint-diagnostic-suite",
        "constraint-document-integration",
    },
    "G6": {
        "step-external-corpus",
        "iges-external-corpus",
        "exchange-round-trip-suite",
        "implicit-curve-exchange-certification",
        "exchange-resource-fuzz",
        "third-party-cad-oracle",
    },
    "G7": {
        "public-contract-inventory",
        "catalog-completion",
        "full-integration-suite",
        "property-suite",
        "parser-fuzz",
        "large-model-benchmark",
        "allocation-benchmark",
        "incremental-evaluation-benchmark",
        "all-platform-build-runtime",
    },
}


def fail(message: str) -> None:
    print(f"Goal contract check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_gate_rows(roadmap: str) -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    header = (
        "| Gate | Completion requirement | Status | Current blocking condition | "
        "Required final evidence | Recorded evidence |"
    )
    reading_gate_table = False
    for line in roadmap.splitlines():
        if line == header:
            reading_gate_table = True
            continue
        if not reading_gate_table:
            continue
        if not line.startswith("|"):
            break
        if not line.startswith("| `G"):
            continue
        fields = [field.strip() for field in line.strip().strip("|").split("|")]
        if len(fields) != 6:
            fail(f"gate row must have six fields: {line}")
        gate_id = fields[0].strip("`")
        status = fields[2]
        recorded_evidence = fields[5]
        if status not in {"OPEN", "PASS"}:
            fail(f"{gate_id} has invalid status {status}")
        rows.append((gate_id, status, recorded_evidence))
    return rows


def validate_evidence(
    root: Path,
    gate_id: str,
    recorded_evidence: str,
) -> str:
    link_match = EVIDENCE_LINK_PATTERN.fullmatch(recorded_evidence)
    if link_match is None or link_match.group("gate") != gate_id:
        fail(
            f"{gate_id} PASS must link exactly to "
            f"[gate evidence](Evidence/{gate_id}.json)"
        )

    evidence_path = root / link_match.group("path")
    if not evidence_path.is_file():
        fail(f"{gate_id} evidence manifest does not exist: {evidence_path}")
    try:
        payload = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{gate_id} evidence manifest is invalid: {error}")

    if payload.get("gate") != gate_id:
        fail(f"{gate_id} evidence manifest has a mismatched gate")
    revision = payload.get("revision")
    if not isinstance(revision, str) or REVISION_PATTERN.fullmatch(revision) is None:
        fail(f"{gate_id} evidence manifest requires a 40-character Git revision")

    commands = payload.get("commands")
    if not isinstance(commands, list) or not commands:
        fail(f"{gate_id} evidence manifest requires at least one command result")
    kinds: set[str] = set()
    for index, command in enumerate(commands):
        if not isinstance(command, dict):
            fail(f"{gate_id} command result {index} must be an object")
        kind = command.get("kind")
        if not isinstance(kind, str) or not kind.strip():
            fail(f"{gate_id} command result {index} requires an evidence kind")
        if kind in kinds:
            fail(f"{gate_id} contains duplicate evidence kind {kind}")
        kinds.add(kind)
        if not isinstance(command.get("command"), str) or not command["command"].strip():
            fail(f"{gate_id} command result {index} requires the exact command")
        if command.get("outcome") != "passed":
            fail(f"{gate_id} command result {index} is not passed")
        artifact = command.get("artifact")
        if not isinstance(artifact, str) or not artifact.strip():
            fail(f"{gate_id} command result {index} requires an artifact")
        artifact_path = Path(artifact)
        if artifact_path.is_absolute() or ".." in artifact_path.parts:
            fail(f"{gate_id} command result {index} has an unsafe artifact path")
        required_parent = Path("Evidence") / "artifacts" / gate_id
        if not artifact_path.is_relative_to(required_parent):
            fail(
                f"{gate_id} command result {index} artifact must be under "
                f"{required_parent}"
            )
        resolved_artifact = root / artifact_path
        if not resolved_artifact.is_file():
            fail(
                f"{gate_id} command result {index} artifact does not exist: "
                f"{artifact}"
            )
        expected_digest = command.get("sha256")
        if (
            not isinstance(expected_digest, str)
            or SHA256_PATTERN.fullmatch(expected_digest) is None
        ):
            fail(f"{gate_id} command result {index} requires a SHA-256 digest")
        actual_digest = hashlib.sha256(resolved_artifact.read_bytes()).hexdigest()
        if actual_digest != expected_digest:
            fail(f"{gate_id} command result {index} artifact digest does not match")

    missing_kinds = sorted(REQUIRED_EVIDENCE_KINDS[gate_id] - kinds)
    if missing_kinds:
        fail(f"{gate_id} is missing evidence kinds: {', '.join(missing_kinds)}")
    return revision


def git_output(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"git {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def validate_final_attestation(root: Path, revision: str) -> None:
    git_output(root, "cat-file", "-e", f"{revision}^{{commit}}")
    changed_paths = set(
        filter(None, git_output(root, "diff", "--name-only", revision, "HEAD").splitlines())
    )
    forbidden_changes = sorted(
        path
        for path in changed_paths
        if path != "ROADMAP.md" and not path.startswith("Evidence/")
    )
    if forbidden_changes:
        fail(
            "final attestation changed tested implementation paths: "
            + ", ".join(forbidden_changes)
        )
    if git_output(root, "status", "--porcelain"):
        fail("final completion requires a clean worktree")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    roadmap = (root / "ROADMAP.md").read_text(encoding="utf-8")
    readme = (root / "README.md").read_text(encoding="utf-8")
    spec = (root / "SPEC.md").read_text(encoding="utf-8")

    gate_rows = read_gate_rows(roadmap)
    gate_ids = tuple(gate_id for gate_id, _, _ in gate_rows)
    if gate_ids != EXPECTED_GATES:
        fail(f"expected gate rows {EXPECTED_GATES}, found {gate_ids}")

    passed = sum(status == "PASS" for _, status, _ in gate_rows)
    achieved = passed == len(EXPECTED_GATES)
    expected_status = (
        f"**Overall status: {'ACHIEVED' if achieved else 'NOT ACHIEVED'} — "
        f"{passed}/8 gates passed.**"
    )
    if expected_status not in roadmap:
        fail(f"overall status must be exactly: {expected_status}")

    revisions: set[str] = set()
    for gate_id, status, recorded_evidence in gate_rows:
        if status == "OPEN":
            if recorded_evidence != "—":
                fail(f"{gate_id} OPEN must not record final evidence")
            continue
        revisions.add(validate_evidence(root, gate_id, recorded_evidence))
    if len(revisions) > 1:
        fail("all passed gates must use evidence from the same Git revision")
    if achieved:
        if len(revisions) != 1:
            fail("completed goal requires exactly one tested source revision")
        validate_final_attestation(root, next(iter(revisions)))

    for document in REMOVED_DOCUMENTS:
        if (root / document).exists():
            fail(f"removed duplicate document still exists: {document}")
        for source_name, source in (("README.md", readme), ("SPEC.md", spec)):
            if document in source:
                fail(f"{source_name} still links to removed document {document}")

    required_documents = ("SPEC.md", "CAPABILITY_LEDGER.md", "ROADMAP.md")
    for document in required_documents:
        if document not in readme:
            fail(f"README.md does not link to {document}")

    if achieved:
        print("Goal completion contract achieved (8/8 gates passed).")
    else:
        print(
            "Goal contract consistency check passed; "
            f"completion is NOT ACHIEVED ({passed}/8 gates passed)."
        )


if __name__ == "__main__":
    main()
