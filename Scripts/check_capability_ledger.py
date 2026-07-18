#!/usr/bin/env python3
"""Keep the capability ledger and the compiled kernel catalog in lockstep."""

from pathlib import Path
import re
import sys


CAPABILITY_ID = re.compile(r"\b(?:GEO|TOPO|MODEL|API|EXCHANGE)-[A-Z0-9]+-\d{3}\b")


def ids_from(path: Path) -> set[str]:
    return set(CAPABILITY_ID.findall(path.read_text(encoding="utf-8")))


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    ledger = ids_from(root / "CAPABILITY_LEDGER.md")
    implementation = ids_from(root / "Sources/CADKernel/KernelCapabilities.swift")
    tests = ids_from(root / "Tests/CADKernelTests/KernelCapabilityContractTests.swift")
    if ledger != implementation or implementation != tests:
        missing = sorted(ledger - implementation)
        extra = sorted(implementation - ledger)
        if missing:
            print("Missing implementation capability IDs:", ", ".join(missing))
        if extra:
            print("Undocumented implementation capability IDs:", ", ".join(extra))
        missing_tests = sorted(implementation - tests)
        extra_tests = sorted(tests - implementation)
        if missing_tests:
            print("Capability IDs missing from contract tests:", ", ".join(missing_tests))
        if extra_tests:
            print("Contract tests reference unknown capability IDs:", ", ".join(extra_tests))
        return 1
    print(f"Capability ledger check passed ({len(ledger)} IDs).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
