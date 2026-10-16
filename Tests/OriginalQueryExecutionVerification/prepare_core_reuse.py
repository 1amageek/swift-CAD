#!/usr/bin/env python3
"""Project a verified successful Core build without accepting stale Geometry inputs."""
import argparse
import json
from pathlib import Path
import shutil

from typecheck import ROOT, SDK, SWIFT_BIN, digest


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def prepare(source, output):
    source = source.resolve()
    receipt = json.loads(source.read_text())
    module = "CADCore"
    step = receipt.get("steps", {}).get(module)
    require(step and step["exitCode"] == 0 and step.get("stopReason") is None,
            "Core is not an accepted successful compiler step.")
    origin = Path(step.get("reusedFrom", source)).resolve()
    original = json.loads(origin.read_text())
    original_step = original.get("steps", {}).get(module)
    require(original_step and original_step["exitCode"] == 0
            and original_step.get("stopReason") is None and not original_step.get("reusedFrom"),
            "Core origin must identify the actual successful compiler invocation.")
    require(original_step["command"] == step["command"], "Core origin command changed.")
    for key in ["toolchain", "compilerSHA256", "compilerVersion", "sdk",
                "sdkSettingsSHA256", "reusedProducts"]:
        require(receipt.get(key) == original.get(key), "Core origin premise changed: " + key)
    require(receipt["toolchain"] == str(SWIFT_BIN)
            and receipt["compilerSHA256"] == digest(SWIFT_BIN / "swiftc"),
            "Core compiler differs from the fixed toolchain.")
    require(receipt["sdk"] == str(SDK)
            and receipt["sdkSettingsSHA256"] == digest(SDK / "SDKSettings.json"),
            "Core SDK differs from the fixed SDK.")
    command = step["command"]
    require(command[0] == str(SWIFT_BIN / "swiftc")
            and command[command.index("-module-name") + 1] == module
            and command[command.index("-target") + 1] == "arm64-apple-macosx27.0"
            and command[command.index("-sdk") + 1] == str(SDK)
            and all(flag in command for flag in ["-O", "-whole-module-optimization",
                                                "-enable-testing", "-emit-module", "-emit-object"]),
            "Core command does not have the accepted Native WMO object contract.")
    inputs = {path: value for path, value in receipt["sourceSHA256"].items()
              if path.startswith("Sources/CADCore/")}
    original_inputs = {path: value for path, value in original["sourceSHA256"].items()
                       if path.startswith("Sources/CADCore/")}
    current = {str(path.relative_to(ROOT)) for path in (ROOT / "Sources/CADCore").rglob("*.swift")}
    require(inputs == original_inputs and current == set(inputs) and len(inputs) == 65,
            "Core source inventory differs from the accepted 65 inputs.")
    require({str(Path(value).resolve()) for value in command if value.endswith(".swift")}
            == {str((origin.parent / "snapshot" / path).resolve()) for path in inputs},
            "Core compiler command differs from its complete source inventory.")
    for relative, expected in inputs.items():
        for path in [ROOT / relative, source.parent / "snapshot" / relative,
                     origin.parent / "snapshot" / relative]:
            require(digest(path) == expected, "Core source changed: " + str(path))
    require(digest(origin.parent / "CADCore.log") == step["logSHA256"],
            "Core original compiler log changed.")
    for key, extension, flag in [("products", ".swiftmodule", "-emit-module-path"),
                                 ("objects", ".o", "-o")]:
        expected = receipt[key][module]
        require(expected == original[key][module], "Core accepted product differs from origin.")
        for path in [Path(command[command.index(flag) + 1]),
                     source.parent / "modules" / (module + extension)]:
            require(digest(path) == expected, "Core product changed: " + str(path))
    for path, expected in receipt["reusedProducts"].items():
        require(digest(Path(path)) == expected, "Core dependency product changed: " + path)
        require(digest(source.parent / "modules" / Path(path).name) == expected,
                "Core retained dependency product changed: " + path)

    output.mkdir(parents=True, exist_ok=False)
    (output / "modules").mkdir()
    for relative in inputs:
        destination = output / "snapshot" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source.parent / "snapshot" / relative, destination)
    for name in ["CADCore.swiftmodule", "CADCore.o"] + [Path(path).name for path in receipt["reusedProducts"]]:
        shutil.copyfile(source.parent / "modules" / name, output / "modules" / name)
    shutil.copyfile(origin.parent / "CADCore.log", output / "CADCore.log")
    projected = {key: receipt[key] for key in ["reusedProducts", "toolchain", "compilerSHA256",
                 "compilerVersion", "sdk", "sdkSettingsSHA256"]}
    projected.update(sourceSHA256=inputs,
                     steps={module: dict(original_step, reusedFrom=str(origin))},
                     products={module: receipt["products"][module]},
                     objects={module: receipt["objects"][module]},
                     reuseProjection={"sourceReceipt": str(source), "sourceReceiptSHA256": digest(source),
                                      "originalCompilerReceipt": str(origin),
                                      "originalCompilerReceiptSHA256": digest(origin),
                                      "scope": "Core only; no Geometry acceptance", "sourceCount": len(inputs)})
    for relative, expected in inputs.items():
        require(digest(output / "snapshot" / relative) == expected, "Copied Core input changed.")
    for name, expected in [("CADCore.swiftmodule", projected["products"][module]),
                           ("CADCore.o", projected["objects"][module])]:
        require(digest(output / "modules" / name) == expected, "Copied Core product changed.")
    (output / "receipt.json").write_text(json.dumps(projected, indent=2) + "\n")
    print(json.dumps({"receipt": str(output / "receipt.json"),
                      "sha256": digest(output / "receipt.json"), "sourceCount": len(inputs),
                      "compilerStarted": False}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.receipt, args.output.resolve())
