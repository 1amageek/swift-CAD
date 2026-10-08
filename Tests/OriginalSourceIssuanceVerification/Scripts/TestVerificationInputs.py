"""Exercise source edits deterministically at the compiler snapshot boundary."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from VerificationInputs import copy_input, require_unchanged_inputs


class VerificationInputTests(unittest.TestCase):
    def check_copy(self, prefix, edit_during_copy):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Original.swift'
            target = root / 'Compiled.swift'
            original = b'// Original bytes\r\nlet value = 1\n'
            changed = b'// Changed bytes\nlet value = 2\n'
            source.write_bytes(original)
            hashes = {}
            write_bytes = Path.write_bytes
            read_bytes = Path.read_bytes
            source_reads = []

            def read(path):
                if path == source:
                    source_reads.append(path)
                return read_bytes(path)

            def write(path, data):
                count = write_bytes(path, data)
                if path == target and edit_during_copy:
                    write_bytes(source, changed)
                return count

            with patch.object(Path, 'read_bytes', read), patch.object(Path, 'write_bytes', write):
                self.assertEqual(copy_input(source, target, root, hashes, prefix), target)
            self.assertEqual(len(source_reads), 1)
            self.assertEqual(target.read_bytes(), prefix + original)
            self.assertEqual(hashes, {'Original.swift': hashlib.sha256(original).hexdigest()})
            if edit_during_copy:
                self.assertEqual(source.read_bytes(), changed)
                with self.assertRaisesRegex(RuntimeError, 'Source changed during verification: Original.swift'):
                    require_unchanged_inputs(root, hashes)
            else:
                require_unchanged_inputs(root, hashes)
                source.write_bytes(changed)
                with self.assertRaises(RuntimeError):
                    require_unchanged_inputs(root, hashes)

    def test_overlay_edit_during_copy_is_rejected(self):
        self.check_copy(b'@testable import CADGeometry\n', True)

    def test_proof_edit_during_copy_is_rejected(self):
        self.check_copy(b'', True)

    def test_unchanged_overlay_and_later_edit(self):
        self.check_copy(b'import CADGeometry\nimport SourceIssuerCached\n', False)

    def test_unchanged_proof_and_later_edit(self):
        self.check_copy(b'', False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
