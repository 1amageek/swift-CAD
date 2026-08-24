#!/usr/bin/env python3
"""Keep the capability ledger and the compiled kernel catalog in lockstep."""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
import re
import sys


CAPABILITY_ID_PATTERN = (
    r"(?:GEO|TOPO|MODEL|API|EXCHANGE)-[A-Z0-9]+(?:-[A-Z0-9]+)*-\d{3}"
)
CAPABILITY_ID = re.compile(rf"\b{CAPABILITY_ID_PATTERN}\b")
CATALOG_ID = re.compile(rf'id:\s*"(?P<id>{CAPABILITY_ID_PATTERN})"')
CATALOG_OPERATION = re.compile(r'operation:\s*"(?P<operation>[^"]+)"')
CATALOG_STATUS = re.compile(r"status:\s*\.(?P<status>supported|partial|planned)")
CATALOG_TOPOLOGY = re.compile(r"topology:\s*\.(?P<topology>[A-Za-z0-9_]+)")
FEATURE_DEFAULT_STATUS = re.compile(
    r"status:\s*KernelCapabilityStatus\s*=\s*\.(?P<status>supported|partial|planned)"
)
CATALOG_FIXTURE_ARRAY = re.compile(
    r"(?:fixtures|testFixtures):\s*\[(.*?)\]",
    re.DOTALL,
)
CATALOG_FAILURE_ARRAY = re.compile(r"failureCodes:\s*\[(.*?)\]", re.DOTALL)
FEATURE_DEFAULT_FAILURE_ARRAY = re.compile(
    r"failureCodes:\s*\[KernelErrorCode\]\s*=\s*\[(.*?)\]",
    re.DOTALL,
)
KERNEL_ERROR_CASE = re.compile(r"\.([A-Za-z][A-Za-z0-9_]*)")
SWIFT_STRING_LITERAL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')
LEDGER_FIXTURE = re.compile(r"`([^`]*Tests(?:\.[^`]*)?)`")
ENVELOPE_ID = re.compile(r"ENV-(?P<number>\d{3})")
TEST_CONTAINER = re.compile(
    r"\b(?:actor|class|enum|struct)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*Tests)\b"
)
TEST_FUNCTION = re.compile(r"\bfunc\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(")


@dataclass(frozen=True)
class CatalogEntry:
    identifier: str
    operation: str
    status: str
    topology: str
    fixtures: frozenset[str]
    failure_codes: frozenset[str]


@dataclass(frozen=True)
class LedgerContract:
    capability_ids: tuple[str, ...]
    envelope_ids: tuple[str, ...]
    fixtures_by_capability: dict[str, frozenset[str]]


@dataclass(frozen=True)
class TestEvidence:
    containers: frozenset[str]
    functions: frozenset[str]


def fail(message: str) -> None:
    print(f"Capability ledger check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_catalog(paths: list[Path]) -> dict[str, CatalogEntry]:
    source = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    default_status_match = FEATURE_DEFAULT_STATUS.search(source)
    if default_status_match is None:
        fail("compiled catalog is missing the feature helper's default status")
    default_status = default_status_match.group("status")
    default_failure_match = FEATURE_DEFAULT_FAILURE_ARRAY.search(source)
    if default_failure_match is None:
        fail("compiled catalog is missing the feature helper's default failure codes")
    default_failure_codes = frozenset(
        KERNEL_ERROR_CASE.findall(default_failure_match.group(1))
    )
    matches = list(CATALOG_ID.finditer(source))
    counts = Counter(match.group("id") for match in matches)
    duplicates = sorted(identifier for identifier, count in counts.items() if count != 1)
    if duplicates:
        fail(f"compiled catalog has duplicate IDs: {', '.join(duplicates)}")

    entries: dict[str, CatalogEntry] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        block = source[match.start():end]
        operation_match = CATALOG_OPERATION.search(block)
        status_match = CATALOG_STATUS.search(block)
        topology_match = CATALOG_TOPOLOGY.search(block)
        fixture_match = CATALOG_FIXTURE_ARRAY.search(block)
        if operation_match is None or topology_match is None or fixture_match is None:
            fail(f"compiled capability {match.group('id')} is structurally incomplete")
        fixtures = frozenset(SWIFT_STRING_LITERAL.findall(fixture_match.group(1)))
        if not fixtures:
            fail(f"compiled capability {match.group('id')} has no fixtures")
        identifier = match.group("id")
        failure_match = CATALOG_FAILURE_ARRAY.search(block)
        failure_codes = (
            frozenset(KERNEL_ERROR_CASE.findall(failure_match.group(1)))
            if failure_match is not None
            else default_failure_codes
        )
        if not failure_codes:
            fail(f"compiled capability {identifier} has no typed failure codes")
        entries[identifier] = CatalogEntry(
            identifier=identifier,
            operation=operation_match.group("operation"),
            status=status_match.group("status") if status_match is not None else default_status,
            topology=topology_match.group("topology"),
            fixtures=fixtures,
            failure_codes=failure_codes,
        )
    return entries


def table_fields(line: str) -> list[str]:
    return [field.strip() for field in line.strip().strip("|").split("|")]


def fixtures_from_field(field: str) -> frozenset[str]:
    fixtures = frozenset(LEDGER_FIXTURE.findall(field))
    if not fixtures:
        fail(f"ledger evidence field has no fixture binding: {field}")
    return fixtures


def parse_ledger(path: Path) -> LedgerContract:
    source = path.read_text(encoding="utf-8")
    primary_source, separator, envelope_source = source.partition(
        "## Current envelope additions"
    )
    if not separator:
        fail("ledger is missing the current envelope additions section")

    primary_ids: list[str] = []
    fixtures: defaultdict[str, set[str]] = defaultdict(set)
    for line in primary_source.splitlines():
        if not re.match(rf"^\| `{CAPABILITY_ID_PATTERN}` \|", line):
            continue
        fields = table_fields(line)
        if len(fields) != 6:
            fail(f"primary capability row must have six fields: {line}")
        identifier = fields[0].strip("`")
        primary_ids.append(identifier)
        fixtures[identifier].update(fixtures_from_field(fields[5]))

    primary_counts = Counter(primary_ids)
    duplicates = sorted(identifier for identifier, count in primary_counts.items() if count != 1)
    if duplicates:
        fail(f"primary ledger has duplicate capability IDs: {', '.join(duplicates)}")

    envelope_ids: list[str] = []
    for line in envelope_source.splitlines():
        if not line.startswith("| `ENV-"):
            continue
        fields = table_fields(line)
        if len(fields) != 5:
            fail(f"capability envelope row must have five fields: {line}")
        envelope_id = fields[0].strip("`")
        capability_id = fields[1].strip("`")
        if ENVELOPE_ID.fullmatch(envelope_id) is None:
            fail(f"invalid envelope ID: {envelope_id}")
        if capability_id not in primary_counts:
            fail(f"{envelope_id} references unknown capability {capability_id}")
        envelope_ids.append(envelope_id)
        fixtures[capability_id].update(fixtures_from_field(fields[4]))

    envelope_counts = Counter(envelope_ids)
    duplicate_envelopes = sorted(
        identifier for identifier, count in envelope_counts.items() if count != 1
    )
    if duplicate_envelopes:
        fail(f"duplicate envelope IDs: {', '.join(duplicate_envelopes)}")
    expected_envelopes = tuple(
        f"ENV-{number:03d}" for number in range(1, len(envelope_ids) + 1)
    )
    if tuple(envelope_ids) != expected_envelopes:
        fail(
            "envelope IDs must be contiguous and ordered: "
            f"expected {expected_envelopes}, found {tuple(envelope_ids)}"
        )

    return LedgerContract(
        capability_ids=tuple(primary_ids),
        envelope_ids=tuple(envelope_ids),
        fixtures_by_capability={
            identifier: frozenset(values) for identifier, values in fixtures.items()
        },
    )


def ids_from_contract_test(path: Path) -> set[str]:
    return set(CAPABILITY_ID.findall(path.read_text(encoding="utf-8")))


def test_evidence(root: Path) -> TestEvidence:
    containers: set[str] = set()
    functions: set[str] = set()
    for path in sorted((root / "Tests").rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        containers.add(path.stem)
        containers.update(match.group("name") for match in TEST_CONTAINER.finditer(source))
        functions.update(match.group("name") for match in TEST_FUNCTION.finditer(source))
    return TestEvidence(
        containers=frozenset(containers),
        functions=frozenset(functions),
    )


def fixture_has_source_evidence(fixture: str, evidence: TestEvidence) -> bool:
    components = fixture.split(".")
    if len(components) == 1:
        return components[0] in evidence.containers
    if len(components) == 2:
        return (
            components[0] in evidence.containers
            and components[1] in evidence.functions
        )
    return False


def roadmap_row_numbers(source: str, label: str) -> list[int]:
    for line in source.splitlines():
        if not line.startswith("|"):
            continue
        fields = table_fields(line)
        if fields and fields[0] == label:
            return [int(value) for value in re.findall(r"\d+", fields[1])]
    fail(f"ROADMAP is missing the '{label}' row")


def roadmap_domain_numbers(source: str, label: str) -> list[int]:
    for line in source.splitlines():
        if not line.startswith("|"):
            continue
        fields = table_fields(line)
        if fields and fields[0] == label and len(fields) >= 4:
            return [int(field) for field in fields[1:4]]
    fail(f"ROADMAP is missing the '{label}' domain row")


def validate_roadmap_metrics(
    source: str,
    catalog: dict[str, CatalogEntry],
    envelope_count: int,
) -> None:
    statuses = Counter(entry.status for entry in catalog.values())
    fixture_count = sum(len(entry.fixtures) for entry in catalog.values())
    expected_metrics = {
        "Catalog capabilities": [len(catalog)],
        "General `supported` capabilities": [statuses["supported"], len(catalog)],
        "`partial` capabilities": [statuses["partial"]],
        "Development-only input envelopes": [envelope_count],
        "Capability-to-fixture bindings": [fixture_count],
    }
    for label, expected in expected_metrics.items():
        actual = roadmap_row_numbers(source, label)
        if actual != expected:
            fail(f"ROADMAP '{label}' reports {actual}, expected {expected}")

    domains = {
        "Geometry": "GEO-",
        "Topology": "TOPO-",
        "Modeling and constraints": "MODEL-",
        "Shared command/query and native API": "API-",
        "Exact and USD exchange": "EXCHANGE-",
    }
    for label, prefix in domains.items():
        entries = [
            entry for entry in catalog.values() if entry.identifier.startswith(prefix)
        ]
        expected = [
            len(entries),
            sum(entry.status == "supported" for entry in entries),
            sum(entry.status == "partial" for entry in entries),
        ]
        actual = roadmap_domain_numbers(source, label)
        if actual != expected:
            fail(f"ROADMAP '{label}' reports {actual}, expected {expected}")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    ledger = parse_ledger(root / "CAPABILITY_LEDGER.md")
    catalog = parse_catalog(sorted(
        (root / "Sources/CADKernel").glob("KernelCapabilities*.swift")
    ))
    contract_test_ids = ids_from_contract_test(
        root / "Tests/CADKernelTests/KernelCapabilityContractTests.swift"
    )

    ledger_ids = set(ledger.capability_ids)
    catalog_ids = set(catalog)
    if ledger_ids != catalog_ids or catalog_ids != contract_test_ids:
        missing_catalog = sorted(ledger_ids - catalog_ids)
        undocumented_catalog = sorted(catalog_ids - ledger_ids)
        missing_tests = sorted(catalog_ids - contract_test_ids)
        unknown_tests = sorted(contract_test_ids - catalog_ids)
        if missing_catalog:
            print("Missing compiled capability IDs:", ", ".join(missing_catalog))
        if undocumented_catalog:
            print("Undocumented compiled capability IDs:", ", ".join(undocumented_catalog))
        if missing_tests:
            print("Capability IDs missing from contract tests:", ", ".join(missing_tests))
        if unknown_tests:
            print("Contract tests reference unknown capability IDs:", ", ".join(unknown_tests))
        return 1

    inconsistent_supported = sorted(
        entry.identifier
        for entry in catalog.values()
        if entry.status == "supported"
        and "unsupportedCapability" in entry.failure_codes
    )
    if inconsistent_supported:
        print(
            "Supported capabilities declaring unsupported public inputs:",
            ", ".join(inconsistent_supported),
            file=sys.stderr,
        )
        return 1

    fixture_mismatches: list[str] = []
    for identifier in ledger.capability_ids:
        ledger_fixtures = ledger.fixtures_by_capability[identifier]
        catalog_fixtures = catalog[identifier].fixtures
        if ledger_fixtures != catalog_fixtures:
            missing = sorted(catalog_fixtures - ledger_fixtures)
            extra = sorted(ledger_fixtures - catalog_fixtures)
            details: list[str] = []
            if missing:
                details.append(f"missing ledger fixtures {missing}")
            if extra:
                details.append(f"uncompiled ledger fixtures {extra}")
            fixture_mismatches.append(f"{identifier}: {', '.join(details)}")
    if fixture_mismatches:
        print("Capability fixture mismatches:", file=sys.stderr)
        for mismatch in fixture_mismatches:
            print(f"- {mismatch}", file=sys.stderr)
        return 1

    evidence = test_evidence(root)
    missing_test_fixtures = sorted(
        fixture
        for entry in catalog.values()
        for fixture in entry.fixtures
        if not fixture_has_source_evidence(fixture, evidence)
    )
    if missing_test_fixtures:
        print(
            "Catalog fixtures missing from test sources:",
            ", ".join(missing_test_fixtures),
        )
        return 1

    validate_roadmap_metrics(
        (root / "ROADMAP.md").read_text(encoding="utf-8"),
        catalog,
        len(ledger.envelope_ids),
    )

    status_counts = Counter(entry.status for entry in catalog.values())
    fixture_count = sum(len(entry.fixtures) for entry in catalog.values())
    print(
        "Capability ledger check passed "
        f"({len(catalog)} unique capabilities, "
        f"{status_counts['supported']} supported, "
        f"{status_counts['partial']} partial, "
        f"{status_counts['planned']} planned, "
        f"{len(ledger.envelope_ids)} unique envelopes, "
        f"{fixture_count} capability-fixture bindings)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
