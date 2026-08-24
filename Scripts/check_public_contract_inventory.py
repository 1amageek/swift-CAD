#!/usr/bin/env python3
"""Verify that every public mutation, query, persistence, and exchange route has one primary capability."""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

from check_capability_ledger import parse_catalog


EXPECTED_SECTIONS = {
    "schemaVersion",
    "featureOperations",
    "commands",
    "queries",
    "nativePersistence",
    "exchangeFormats",
}
PUBLIC_FUNCTION = re.compile(r"^\s*public\s+func\s+`?(?P<name>[A-Za-z_][A-Za-z0-9_]*)`?\s*\(")


def fail(message: str) -> None:
    print(f"Public contract inventory check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def public_enum_cases(path: Path, enum_name: str) -> tuple[str, ...]:
    lines = path.read_text(encoding="utf-8").splitlines()
    declaration = re.compile(rf"^public\s+enum\s+{re.escape(enum_name)}\b")
    depth = 0
    inside = False
    cases: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not inside:
            if declaration.match(stripped) is None:
                continue
            inside = True
            depth = line.count("{") - line.count("}")
            continue
        if depth == 1 and stripped.startswith("case "):
            payload = stripped.removeprefix("case ")
            name = re.split(r"[\s(,]", payload, maxsplit=1)[0]
            if not name:
                fail(f"could not parse {enum_name} case in {path}: {line}")
            cases.append(name)
        depth += line.count("{") - line.count("}")
        if depth == 0:
            break
    if not inside or not cases:
        fail(f"could not find public enum {enum_name} cases in {path}")
    if len(cases) != len(set(cases)):
        fail(f"public enum {enum_name} contains duplicate cases")
    return tuple(cases)


def public_functions(path: Path) -> tuple[str, ...]:
    functions = tuple(
        match.group("name")
        for line in path.read_text(encoding="utf-8").splitlines()
        if (match := PUBLIC_FUNCTION.match(line)) is not None
    )
    if len(functions) != len(set(functions)):
        fail(f"{path} contains overloaded public functions that require signature-level inventory keys")
    return functions


def require_mapping(
    section_name: str,
    mapping: object,
    source_entries: tuple[str, ...],
    catalog_ids: set[str],
) -> dict[str, str]:
    if not isinstance(mapping, dict):
        fail(f"{section_name} must be an object")
    if not all(isinstance(key, str) and isinstance(value, str) for key, value in mapping.items()):
        fail(f"{section_name} keys and capability IDs must be strings")
    source_set = set(source_entries)
    inventory_set = set(mapping)
    missing = sorted(source_set - inventory_set)
    extra = sorted(inventory_set - source_set)
    if missing or extra:
        details: list[str] = []
        if missing:
            details.append(f"missing {missing}")
        if extra:
            details.append(f"unknown {extra}")
        fail(f"{section_name} does not match its public source enum: {', '.join(details)}")
    unknown_ids = sorted(set(mapping.values()) - catalog_ids)
    if unknown_ids:
        fail(f"{section_name} references unknown capability IDs: {', '.join(unknown_ids)}")
    return mapping


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    inventory_path = root / "PUBLIC_CONTRACT_INVENTORY.json"
    try:
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"inventory is unreadable: {error}")
    if not isinstance(inventory, dict):
        fail("inventory root must be an object")
    if set(inventory) != EXPECTED_SECTIONS:
        fail(
            "inventory sections must be exactly "
            f"{sorted(EXPECTED_SECTIONS)}, found {sorted(inventory)}"
        )
    if inventory["schemaVersion"] != 1:
        fail("inventory schemaVersion must be 1")

    catalog = parse_catalog(sorted((root / "Sources" / "CADKernel").glob("KernelCapabilities*.swift")))
    catalog_ids = set(catalog)
    features = require_mapping(
        "featureOperations",
        inventory["featureOperations"],
        public_enum_cases(
            root / "Sources" / "CADIR" / "FeatureOperationKind.swift",
            "FeatureOperationKind",
        ),
        catalog_ids,
    )
    commands = require_mapping(
        "commands",
        inventory["commands"],
        public_enum_cases(root / "Sources" / "CADIR" / "CADCommand.swift", "CADCommand"),
        catalog_ids,
    )
    queries = require_mapping(
        "queries",
        inventory["queries"],
        public_enum_cases(root / "Sources" / "CADKernel" / "KernelQuery.swift", "KernelQuery"),
        catalog_ids,
    )
    persistence = require_mapping(
        "nativePersistence",
        inventory["nativePersistence"],
        public_functions(root / "Sources" / "CADExchange" / "NativePackageStore.swift"),
        catalog_ids,
    )
    formats = require_mapping(
        "exchangeFormats",
        inventory["exchangeFormats"],
        public_enum_cases(
            root / "Sources" / "CADExchange" / "ExchangeFileFormat.swift",
            "ExchangeFileFormat",
        ),
        catalog_ids,
    )

    operation_to_ids: dict[str, list[str]] = {}
    for entry in catalog.values():
        operation_to_ids.setdefault(entry.operation, []).append(entry.identifier)
    for operation, capability_id in features.items():
        matching_ids = operation_to_ids.get(operation, [])
        if matching_ids != [capability_id]:
            fail(
                f"feature operation {operation} must map to exactly {capability_id}; "
                f"catalog has {matching_ids}"
            )

    parity_id = "API-PARITY-001"
    for section_name, mapping in (("commands", commands), ("queries", queries)):
        mismatches = sorted(key for key, value in mapping.items() if value != parity_id)
        if mismatches:
            fail(f"{section_name} must use the shared {parity_id} path: {mismatches}")
    native_id = "API-NATIVEPERSISTENCE-001"
    native_mismatches = sorted(key for key, value in persistence.items() if value != native_id)
    if native_mismatches or formats.get("swiftCAD") != native_id:
        fail("all native persistence routes must use API-NATIVEPERSISTENCE-001")

    entry_count = sum(
        len(mapping)
        for mapping in (features, commands, queries, persistence, formats)
    )
    print(
        "Public contract inventory check passed "
        f"({entry_count} routes: {len(features)} feature operations, "
        f"{len(commands)} commands, {len(queries)} queries, "
        f"{len(persistence)} native persistence methods, "
        f"{len(formats)} exchange formats)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
