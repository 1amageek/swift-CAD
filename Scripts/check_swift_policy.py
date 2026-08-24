#!/usr/bin/env python3
"""Check Swift source policy without matching comments or string literals."""

from __future__ import annotations

import argparse
from functools import lru_cache
import re
import subprocess
import sys
from pathlib import Path


FORBIDDEN_PATTERNS = (
    ("optional try", re.compile(r"(?<![A-Za-z0-9_])try\s*\?")),
    ("unchecked Sendable", re.compile(r"@unchecked\s+Sendable")),
    ("EventLoopFuture", re.compile(r"\bEventLoopFuture\b")),
    ("DispatchQueue", re.compile(r"\bDispatchQueue\b")),
    ("fatalError", re.compile(r"\bfatalError\s*\(")),
    ("precondition", re.compile(r"\bprecondition\s*\(")),
    ("assert", re.compile(r"\bassert\s*\(")),
    ("forced try", re.compile(r"(?<![A-Za-z0-9_])try\s*!")),
    ("forced cast", re.compile(r"\bas\s*!")),
)

AST_FORBIDDEN_PATTERNS = (
    ("optional try", re.compile(r"\(optional_try_expr\b")),
    ("unchecked Sendable", re.compile(r'inherits="@unchecked')),
    ("EventLoopFuture", re.compile(r'(?:name|id)="EventLoopFuture"')),
    ("DispatchQueue", re.compile(r'(?:name|id)="DispatchQueue"')),
    ("fatalError", re.compile(r'name="fatalError"')),
    ("precondition", re.compile(r'name="precondition"')),
    ("assert", re.compile(r'name="assert"')),
    ("forced try", re.compile(r"\(force_try_expr\b")),
    ("forced cast", re.compile(r"\(forced_checked_cast_expr\b")),
)

ZERO_COPY_PATTERNS = (
    ("Data(contentsOf:)", re.compile(r"\bData\s*\(\s*contentsOf\s*:")),
    ("String(contentsOf:)", re.compile(r"\bString\s*\(\s*contentsOf\s*:")),
    ("public Data return", re.compile(r"\bpublic\s+func[^\n{;]*->\s*Data\b")),
    ("public export Data return", re.compile(r"\bpublic\s+func[^\n{;]*export[^\n{;]*->\s*Data\b")),
)

AST_DEFAULT_TOLERANCE_PATTERN = re.compile(
    r'\(parameter "tolerance"[^\n]*\bdefault_arg=normal\b'
)
SOURCE_DEFAULT_TOLERANCE_PATTERN = re.compile(
    r"\btolerance\s*:\s*[^,)=\n]+?\s*="
)
AST_STANDARD_TOLERANCE_PATTERNS = (
    re.compile(
        r'\(argument label="tolerance"\s+'
        r'\(unresolved_member_expr[^\n]*name="standard"'
    ),
    re.compile(
        r'unresolved_dot_expr[^\n]*field="standard"[^\n]*\n\s*'
        r'\(unresolved_decl_ref_expr[^\n]*name="ModelingTolerance"'
    ),
)
SOURCE_STANDARD_TOLERANCE_PATTERN = re.compile(
    r"\bModelingTolerance\s*\.\s*standard\b|\btolerance\s*:\s*\.standard\b"
)
STANDARD_TOLERANCE_BOUNDARIES = (
    Path("Sources/CADIR/CADIRPersistenceValidation.swift"),
    Path("Sources/CADKernel/KernelCapabilities.swift"),
)
STANDARD_TOLERANCE_BOUNDARY_PREFIXES = (
    "Sources/CADKernel/KernelCapabilities+",
)


def _blank_range(text: str, start: int, end: int) -> str:
    value = text[start:end]
    return "".join("\n" if character == "\n" else " " for character in value)


def mask_non_code(text: str) -> str:
    """Keep code and line breaks while masking comments and string literals."""
    output: list[str] = []
    index = 0
    length = len(text)
    block_depth = 0

    while index < length:
        if block_depth:
            if text.startswith("/*", index):
                block_depth += 1
                output.extend((" ", " "))
                index += 2
            elif text.startswith("*/", index):
                block_depth -= 1
                output.extend((" ", " "))
                index += 2
            else:
                output.append("\n" if text[index] == "\n" else " ")
                index += 1
            continue

        if text.startswith("//", index):
            while index < length and text[index] != "\n":
                output.append(" ")
                index += 1
            continue

        if text.startswith("/*", index):
            block_depth = 1
            output.extend((" ", " "))
            index += 2
            continue

        raw_hashes = 0
        while index + raw_hashes < length and text[index + raw_hashes] == "#":
            raw_hashes += 1
        if index + raw_hashes < length and text[index + raw_hashes] == '"':
            quote_start = index + raw_hashes
            delimiter = '"' * (3 if text.startswith('"""', quote_start) else 1)
            closing = delimiter + ("#" * raw_hashes)
            close_index = text.find(closing, quote_start + len(delimiter))
            if close_index < 0:
                close_index = length
            else:
                close_index += len(closing)
            output.append(_blank_range(text, index, close_index))
            index = close_index
            continue

        if text[index] == '"':
            delimiter = '"""' if text.startswith('"""', index) else '"'
            close_index = index + len(delimiter)
            escaped = False
            while close_index < length:
                if delimiter == '"' and text[close_index] == "\\" and not escaped:
                    escaped = True
                    close_index += 1
                    continue
                if text.startswith(delimiter, close_index) and not escaped:
                    close_index += len(delimiter)
                    break
                escaped = False
                close_index += 1
            output.append(_blank_range(text, index, close_index))
            index = close_index
            continue

        output.append(text[index])
        index += 1

    return "".join(output)


def scan(paths: list[Path], patterns: tuple[tuple[str, re.Pattern[str]], ...]) -> int:
    violations = 0
    for root in paths:
        files = [root] if root.is_file() else sorted(root.rglob("*.swift"))
        for path in files:
            source = path.read_text(encoding="utf-8")
            masked = mask_non_code(source)
            for label, pattern in patterns:
                for match in pattern.finditer(masked):
                    line = masked.count("\n", 0, match.start()) + 1
                    print(f"{path}:{line}: {label}")
                    violations += 1
    return violations


def swift_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for root in paths:
        files.extend([root] if root.is_file() else sorted(root.rglob("*.swift")))
    return sorted(set(files))


@lru_cache(maxsize=None)
def parse_ast(path: Path) -> str:
    result = subprocess.run(
        ["swiftc", "-frontend", "-dump-parse", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"Swift parser failed for {path}")
    return result.stdout


def scan_swift_ast(paths: list[Path]) -> int:
    violations = 0
    for path in swift_files(paths):
        source = path.read_text(encoding="utf-8")
        masked = mask_non_code(source)
        source_locations = {
            label: list(pattern.finditer(masked))
            for label, pattern in FORBIDDEN_PATTERNS
        }
        if not any(source_locations.values()):
            continue
        ast = parse_ast(path)
        for label, ast_pattern in AST_FORBIDDEN_PATTERNS:
            if ast_pattern.search(ast) is None:
                continue
            locations = source_locations[label]
            if not locations:
                print(f"{path}: {label}")
                violations += 1
                continue
            for match in locations:
                line = masked.count("\n", 0, match.start()) + 1
                print(f"{path}:{line}: {label}")
                violations += 1
    return violations


def scan_explicit_tolerance_ast(paths: list[Path]) -> int:
    violations = 0
    for path in swift_files(paths):
        source = path.read_text(encoding="utf-8")
        masked = mask_non_code(source)
        source_matches = list(SOURCE_DEFAULT_TOLERANCE_PATTERN.finditer(masked))
        if not source_matches:
            continue
        ast = parse_ast(path)
        ast_matches = list(AST_DEFAULT_TOLERANCE_PATTERN.finditer(ast))
        if not ast_matches:
            continue
        for index in range(len(ast_matches)):
            if index < len(source_matches):
                line = masked.count("\n", 0, source_matches[index].start()) + 1
                print(f"{path}:{line}: tolerance parameter must not have a default")
            else:
                print(f"{path}: tolerance parameter must not have a default")
            violations += 1
    return violations


def is_standard_tolerance_boundary(path: Path) -> bool:
    normalized = path.as_posix()
    if any(
        normalized.endswith(boundary.as_posix())
        for boundary in STANDARD_TOLERANCE_BOUNDARIES
    ):
        return True
    return any(
        prefix in normalized and normalized.endswith(".swift")
        for prefix in STANDARD_TOLERANCE_BOUNDARY_PREFIXES
    )


def scan_standard_tolerance_ast(paths: list[Path]) -> int:
    violations = 0
    for path in swift_files(paths):
        if is_standard_tolerance_boundary(path):
            continue
        source = path.read_text(encoding="utf-8")
        masked = mask_non_code(source)
        source_matches = list(SOURCE_STANDARD_TOLERANCE_PATTERN.finditer(masked))
        if not source_matches:
            continue
        ast = parse_ast(path)
        if not any(pattern.search(ast) for pattern in AST_STANDARD_TOLERANCE_PATTERNS):
            continue
        if not source_matches:
            print(f"{path}: standard tolerance is restricted to named boundaries")
            violations += 1
            continue
        for match in source_matches:
            line = masked.count("\n", 0, match.start()) + 1
            print(f"{path}:{line}: standard tolerance is restricted to named boundaries")
            violations += 1
    return violations


def scan_tolerance_contract_ast(paths: list[Path]) -> int:
    return scan_explicit_tolerance_ast(paths) + scan_standard_tolerance_ast(paths)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    policy = parser.add_mutually_exclusive_group()
    policy.add_argument("--zero-copy", action="store_true")
    policy.add_argument("--explicit-tolerance", action="store_true")
    policy.add_argument("--tolerance-contract", action="store_true")
    arguments = parser.parse_args()
    if arguments.zero_copy:
        return 1 if scan(arguments.paths, ZERO_COPY_PATTERNS) else 0
    if arguments.explicit_tolerance:
        return 1 if scan_explicit_tolerance_ast(arguments.paths) else 0
    if arguments.tolerance_contract:
        return 1 if scan_tolerance_contract_ast(arguments.paths) else 0
    return 1 if scan_swift_ast(arguments.paths) else 0


if __name__ == "__main__":
    sys.exit(main())
