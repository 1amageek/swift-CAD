"""Behavioral refusal checks; synthetic receipts do not certify Swift artifacts."""
import json
from pathlib import Path
import tempfile
import unittest

from artifact_receipt import digest, verify_generation


class GenerationReceiptTests(unittest.TestCase):
    def test_generation_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            contents = {"source.swift": "source", "swiftc": "compiler", "module.swiftmodule": "module",
                        "lower.o": "object", "debug.yaml": "plan", "build.log": "completed",
                        "GraphProof": "accepted executable"}
            for name, data in contents.items():
                (root / name).write_text(data)
            inputs = {name: digest(root / name) for name in ["source.swift", "swiftc"]}
            artifacts = {name: digest(root / name) for name in ["module.swiftmodule", "lower.o", "debug.yaml"]}
            manifest = dict(success=True, inputs=inputs, artifacts=artifacts,
                            logs={"build.log": digest(root / "build.log")}, runs=[dict(exitCode=0)])
            path = root / "generation.json"
            required = {name: None for name in artifacts}

            def verify(value):
                path.write_text(json.dumps(value))
                return verify_generation(path, root, inputs, required)

            self.assertIn(str(root / "lower.o"), verify(manifest))
            for name in artifacts:
                with self.subTest(overwritten=name):
                    executable = digest(root / "GraphProof")
                    (root / name).write_text("later build")
                    with self.assertRaisesRegex(RuntimeError, "Overwritten generation"):
                        verify(manifest)
                    self.assertEqual(executable, digest(root / "GraphProof"))
                    (root / name).write_text(contents[name])
            for name in artifacts:
                with self.subTest(missing=name):
                    broken = {**manifest, "artifacts": {p: h for p, h in artifacts.items() if p != name}}
                    with self.assertRaisesRegex(RuntimeError, "Missing generation"):
                        verify(broken)
            for broken in [{**manifest, "success": False}, {**manifest, "runs": []},
                           {**manifest, "runs": [dict(exitCode=1)]}, {**manifest, "logs": {}}]:
                with self.assertRaises(RuntimeError):
                    verify(broken)
            with self.assertRaisesRegex(RuntimeError, "Missing generation inputs"):
                verify({**manifest, "inputs": {}})
            for name in inputs:
                with self.subTest(changed_input=name):
                    (root / name).write_text("other generation")
                    with self.assertRaisesRegex(RuntimeError, "Overwritten generation"):
                        verify(manifest)
                    (root / name).write_text(contents[name])
            with self.assertRaisesRegex(RuntimeError, "Changed generation premise"):
                verify({**manifest, "inputs": {**inputs, "source.swift": "0" * 64}})
            (root / "build.log").write_text("other log")
            with self.assertRaisesRegex(RuntimeError, "Changed generation log"):
                verify(manifest)
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                verify_generation(path, root, inputs, required)


if __name__ == "__main__":
    unittest.main()
