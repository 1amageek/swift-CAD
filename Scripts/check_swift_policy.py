#!/usr/bin/env python3
"""Check Swift source policy without matching comments or string literals."""

from __future__ import annotations

import argparse
import re
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

ZERO_COPY_PATTERNS = (
    ("Data(contentsOf:)", re.compile(r"\bData\s*\(\s*contentsOf\s*:")),
    ("String(contentsOf:)", re.compile(r"\bString\s*\(\s*contentsOf\s*:")),
    ("public Data return", re.compile(r"\bpublic\s+func[^\n{;]*->\s*Data\b")),
    ("public export Data return", re.compile(r"\bpublic\s+func[^\n{;]*export[^\n{;]*->\s*Data\b")),
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--zero-copy", action="store_true")
    arguments = parser.parse_args()
    patterns = ZERO_COPY_PATTERNS if arguments.zero_copy else FORBIDDEN_PATTERNS
    return 1 if scan(arguments.paths, patterns) else 0


if __name__ == "__main__":
    sys.exit(main())
