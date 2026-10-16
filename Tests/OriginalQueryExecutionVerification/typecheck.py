#!/usr/bin/env python3
"""Pin actual production inputs and diagnose the direct Core/Geometry contracts."""
import hashlib
import argparse
import json
import os
import re
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SWIFT_BIN = Path("/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin")
SDK = Path("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
DEPENDENCIES = ROOT / ".build/g01-finite-bounded-20261014/accepted/native"
MODULE_ORDER = ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADModeling", "CADKernel",
                "CADCapabilities", "CADUSD", "CADExchange", "SwiftCAD"]
OPENUSD_MODULES = ["OpenUSD", "OpenUSDC", "OpenUSDZ"]
OPENUSD_REVISION = "2c943c75ef9c0c32974663b13441a0972bec7d3e"

PRODUCT_RECEIPT = ROOT / "Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-FINITE-UV/native/products.json"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_collections_products(path):
    """Verify a fresh pinned SwiftPM build and its exact module/object origins."""
    path = path.resolve()
    products = json.loads(path.read_bytes())
    origin_path = path.parent / "receipt.json"
    origin = json.loads(origin_path.read_bytes())
    def check(condition, message):
        if not condition:
            raise RuntimeError("Collections dependency: " + message)
    check(origin.get("status") == "passed" and origin.get("sourceUnchanged")
          and origin.get("productsUnchanged"), "not a successful frozen build")
    check(origin.get("revision") == "fea17c02d767f46b23070fdfdacc28a03a39232a", "different pinned revision")
    check(origin.get("productsReceipt") == {"path": str(path), "sha256": digest(path)}, "product map differs")
    for key, expected in {"toolchain": str(SWIFT_BIN), "sdk": str(SDK),
                          "target": "arm64-apple-macosx27.0",
                          "compilerSHA256": digest(SWIFT_BIN / "swiftc"),
                          "sdkSettingsSHA256": digest(SDK / "SDKSettings.json")}.items():
        check(origin.get(key) == expected, "compiler/SDK/target differs: " + key)
    for name, expected in origin["toolSHA256"].items():
        check(digest(SWIFT_BIN / name) == expected, "tool changed: " + name)
    check(digest(path.parent / "run.py") == origin["runnerSHA256"], "generation runner changed")
    check(digest(Path(origin["monitor"]["path"])) == origin["monitor"]["sha256"], "monitor snapshot changed")
    for name in ["compiler-version", "swiftpm-build"]:
        step = origin["steps"][name]
        check(step["exitCode"] == 0 and step.get("stopReason") is None, "unsuccessful step: " + name)
        check(digest(path.parent / (name + ".log")) == step["logSHA256"], "compiler log changed: " + name)
    check((path.parent / "compiler-version.log").read_text() == origin["compilerVersion"], "compiler banner differs")
    source = Path(origin["sourceRoot"])
    check(subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
          == origin["revision"], "source revision changed")
    names = subprocess.check_output(["git", "-C", str(source), "ls-files", "-z"]).decode().split("\0")
    actual = {name: digest(source / name) for name in names if name and (source / name).is_file()}
    check(actual == origin["sourceSHA256"], "pinned source inventory changed")
    command = origin["steps"]["swiftpm-build"]["command"]
    check(command[:2] == [str(SWIFT_BIN / "swift"), "build"] and "--verbose" in command,
          "not the actual verbose SwiftPM build")
    for flag, expected in {"--package-path": str(source), "--scratch-path": origin["scratchPath"],
                           "--target": "HashTreeCollections", "--build-system": "native",
                           "--triple": "arm64-apple-macosx27.0", "--sdk": str(SDK), "--jobs": "1"}.items():
        check(flag in command and command[command.index(flag) + 1] == expected, "build flag differs: " + flag)
    log = (path.parent / "swiftpm-build.log").read_text()
    check(str(SWIFT_BIN / "swift-frontend") in log and str(SDK) in log, "actual compiler/SDK commands absent")
    expected_products = {}
    check(set(origin["products"]) == {"InternalCollectionsUtilities", "HashTreeCollections"}, "unexpected modules")
    for name, product in origin["products"].items():
        sources = sorted((source / "Sources" / name).rglob("*.swift"))
        check(len(sources) == product["sourceCount"] and all(str(item) in log for item in sources),
              "compiler source inventory differs: " + name)
        for key in ["module", "object"]:
            item = product[key]
            check(digest(Path(item["origin"])) == item["sha256"] and item["origin"] in log,
                  "original compiled product changed: " + name + "/" + key)
            check(digest(Path(item["path"])) == item["sha256"], "retained product changed: " + name + "/" + key)
            expected_products[item["path"]] = item["sha256"]
    check(products == expected_products, "module/object map differs from compiler origins")
    return products, {"path": str(path), "sha256": digest(path),
                      "originReceipt": str(origin_path), "originReceiptSHA256": digest(origin_path)}

def tree_hashes(root):
    return {str(path.relative_to(root)): digest(path)
            for path in sorted(root.rglob("*")) if path.is_file()}


def needs_openusd(module):
    return module in {"CADUSD", "CADExchange", "SwiftCAD"}


def verify_openusd_receipt(path, source_root):
    """Validate real pinned SwiftPM products and their original resource lookup."""
    path = path.resolve()
    data = json.loads(path.read_bytes())
    def check(condition, message):
        if not condition:
            raise RuntimeError("OpenUSD dependency: " + message)
    check(data.get("status") == "passed" and data.get("sourceUnchanged")
          and data.get("productsAndResourcesUnchanged"), "not a successful frozen build")
    check(data.get("revision") == OPENUSD_REVISION, "different pinned revision")
    manifest = (source_root / "Package.swift").read_text()
    check('revision: "' + OPENUSD_REVISION + '"' in manifest,
          "production manifest does not select this revision")
    for key, expected in {"toolchain": str(SWIFT_BIN), "sdk": str(SDK),
                          "target": "arm64-apple-macosx27.0",
                          "compilerSHA256": digest(SWIFT_BIN / "swiftc"),
                          "sdkSettingsSHA256": digest(SDK / "SDKSettings.json")}.items():
        check(data.get(key) == expected, "different compiler/SDK/target: " + key)
    for name, expected in data["toolSHA256"].items():
        check(digest(SWIFT_BIN / name) == expected, "tool changed: " + name)
    source = Path(data["sourceRoot"])
    check(tree_hashes(source) == data["sourceSHA256"], "pinned source inventory/hash changed")
    check(digest(path.parent / "source.tar") == data["archiveSHA256"], "revision archive changed")
    check(digest(path.parent / "run.py") == data["runnerSHA256"], "generation runner changed")
    monitor = data["monitor"]
    check(monitor.get("unchangedSinceBeforeExecution")
          and digest(Path(monitor["snapshot"])) == monitor["sha256"], "executed monitor snapshot changed")
    for name in ["compiler-version", "swiftpm-build"]:
        step = data["steps"][name]
        check(step["exitCode"] == 0 and step.get("stopReason") is None, "unsuccessful step: " + name)
        check(digest(path.parent / (name + ".log")) == step["logSHA256"], "compiler log changed: " + name)
    check((path.parent / "compiler-version.log").read_text() == data["compilerVersion"],
          "compiler version evidence differs")
    command = data["steps"]["swiftpm-build"]["command"]
    check(command[:2] == [str(SWIFT_BIN / "swift"), "build"], "not the actual SwiftPM build")
    for flag, expected in {"--package-path": str(source), "--scratch-path": data["scratchPath"],
                           "--target": "OpenUSDZ", "--triple": "arm64-apple-macosx27.0",
                           "--sdk": str(SDK), "--build-system": "native"}.items():
        check(flag in command and command[command.index(flag) + 1] == expected, "build flag differs: " + flag)
    check("--verbose" in command and int(command[command.index("--jobs") + 1]) <= 2,
          "missing actual compiler commands or excessive concurrency")
    log = (path.parent / "swiftpm-build.log").read_text()
    check(str(SWIFT_BIN / "swift-frontend") in log and str(SDK) in log,
          "actual fixed compiler/SDK commands are absent")
    check(set(data["products"]) == set(OPENUSD_MODULES), "unexpected dependency modules")
    for module in OPENUSD_MODULES:
        product = data["products"][module]
        actual_sources = sorted((source / "Sources" / module).rglob("*.swift"))
        check(len(actual_sources) == data["swiftSourceCounts"][module], "source count changed: " + module)
        check(all(str(item) in log for item in actual_sources),
              "actual compiler source inventory is incomplete: " + module)
        expected_count = data["swiftSourceCounts"][module] + (1 if module == "OpenUSD" else 0)
        check(len(product["objects"]) == expected_count, "object/source count differs: " + module)
        for item in [product["module"], *product["objects"]]:
            check(digest(Path(item["path"])) == item["sha256"], "product changed: " + item["path"])
            check(item["path"] in log, "product missing from actual compiler commands: " + item["path"])
    accessors = data["productionResourceAccessors"]
    bundles = data["productionResourceBundles"]
    check(len(accessors) == 1 and len(bundles) == 1, "unexpected production resource owners")
    for item in accessors:
        check(digest(Path(item["path"])) == item["sha256"] and item["path"] in log,
              "generated resource accessor was not compiled unchanged")
    for bundle in bundles:
        check(tree_hashes(Path(bundle["path"])) == bundle["files"], "original resource bundle changed")
        check(bundle["path"] in Path(accessors[0]["path"]).read_text(),
              "resource bundle is not the compiled original accessor fallback")
    return data


def run(command, output, wall_limit):
    started = time.monotonic()
    peak = 0
    reason = None
    tracked = set()
    maximum_processes = 0
    with output.open("wb") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=ENV, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        tracked.add(process.pid)
        while process.poll() is None:
            elapsed = time.monotonic() - started
            rows = subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid=,pgid=,rss="], text=True)
            entries = [tuple(map(int, row.split())) for row in rows.splitlines()
                       if len(row.split()) == 4]
            tracked.intersection_update(pid for pid, parent, group, size in entries)
            while True:
                expanded = tracked | {pid for pid, parent, group, size in entries if parent in tracked}
                if expanded == tracked:
                    break
                tracked = expanded
            live = [(pid, group, size) for pid, parent, group, size in entries if pid in tracked]
            rss = sum(size * 1024 for pid, group, size in live)
            maximum_processes = max(maximum_processes, len(live))
            peak = max(peak, rss)
            if elapsed > wall_limit or rss > 10 * 1024**3:
                reason = "wall" if elapsed > wall_limit else "rss"
                groups = {group for pid, group, size in live} | {process.pid}
                for group in groups:
                    if group != os.getpgrp():
                        try:
                            os.killpg(group, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                # A detached compiler child can ignore TERM after its driver exits.
                # Closing the bounded run must stop every observed owned group.
                for group in groups:
                    if group != os.getpgrp():
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                break
            time.sleep(0.5)
        code = process.wait()
    return {"command": command, "exitCode": code, "elapsedSeconds": time.monotonic() - started,
            "peakRSSBytes": peak, "rssAccounting": "tracked PPID descendants including separate process groups",
            "maximumObservedProcessCount": maximum_processes,
            "stopReason": reason, "logSHA256": digest(output)}

ENV = dict(os.environ)
ENV["PATH"] = str(SWIFT_BIN) + ":/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:" + ENV.get("PATH", "")
ENV.pop("TOOLCHAINS", None)
if __name__ == "__main__":
    module_order = MODULE_ORDER
    parser = argparse.ArgumentParser()
    parser.add_argument("name", nargs="?", default="u1-semantic-native-" + time.strftime("%Y%m%d-%H%M%S"))
    parser.add_argument("--through", choices=module_order, default="CADGeometry")
    parser.add_argument("--objects", action="store_true", help="Emit the actual WMO object together with its module.")
    parser.add_argument("--optimization", choices=["-Onone", "-O", "-Osize"], default="-Onone")
    parser.add_argument("--resume", type=Path, help="Reuse a receipt-verified unchanged successful module prefix.")
    parser.add_argument("--reuse-through", choices=module_order,
                        help="With --resume, verify and reuse only this successful prefix, then compile dependents freshly.")
    parser.add_argument("--source-root", type=Path, default=ROOT,
                        help="Read production sources from this checkout; retain the runner's artifact/dependency root.")
    parser.add_argument("--dependency-receipt", type=Path, help="Actual pinned OpenUSD SwiftPM module/object/resource receipt for upper targets.")
    parser.add_argument("--collections-products", type=Path,
                        help="Fresh pinned Collections product map with its adjacent actual-build receipt; defaults to historical products.")
    args = parser.parse_args()
    if args.reuse_through and not args.resume:
        parser.error("--reuse-through requires --resume.")
    if args.reuse_through and module_order.index(args.reuse_through) > module_order.index(args.through):
        parser.error("--reuse-through must be no later than --through.")
    source_root = args.source_root.resolve()
    if not source_root.is_dir():
        raise RuntimeError("Production source root does not exist: " + str(source_root))
    selected_modules = module_order[:module_order.index(args.through) + 1]
    output = ROOT / ".build" / args.name
    output.mkdir(parents=True, exist_ok=False)
    modules = output / "modules"
    modules.mkdir()
    collections_descriptor = None
    if args.collections_products:
        accepted, collections_descriptor = verify_collections_products(args.collections_products)
    else:
        accepted = json.loads(PRODUCT_RECEIPT.read_text())
    reused = {}
    for name in ["HashTreeCollections.swiftmodule", "InternalCollectionsUtilities.swiftmodule"]:
        if args.collections_products:
            matching = [Path(path) for path in accepted if Path(path).name == name]
            if len(matching) != 1:
                raise RuntimeError("The Collections receipt has no unique product: " + name)
            product = matching[0]
        else:
            product = DEPENDENCIES / name
        observed = digest(product)
        if accepted.get(str(product)) != observed:
            raise RuntimeError("Dependency product does not match its accepted receipt: " + str(product))
        shutil.copyfile(product, modules / name)
        reused[str(product)] = observed
    external = None
    if any(needs_openusd(module) for module in selected_modules):
        if not args.dependency_receipt:
            raise RuntimeError("Upper module generation requires --dependency-receipt.")
        external = verify_openusd_receipt(args.dependency_receipt, source_root)
        for module in OPENUSD_MODULES:
            product = external["products"][module]["module"]
            shutil.copyfile(product["path"], modules / (module + ".swiftmodule"))
        for bundle in external["productionResourceBundles"]:
            shutil.copytree(bundle["path"], output / "resources" / Path(bundle["path"]).name)
    sources = {}
    inputs = {}
    for module in selected_modules:
        sources[module] = []
        for path in sorted((source_root / "Sources" / module).rglob("*.swift")):
            relative = path.relative_to(source_root)
            data = path.read_bytes()
            pinned = output / "snapshot" / relative
            pinned.parent.mkdir(parents=True, exist_ok=True)
            pinned.write_bytes(data)
            sources[module].append(str(pinned))
            inputs[str(relative)] = hashlib.sha256(data).hexdigest()
    common = [str(SWIFT_BIN / "swiftc"), "-parse-as-library", "-swift-version", "6", args.optimization,
              "-whole-module-optimization", "-enable-testing", "-target", "arm64-apple-macosx27.0",
              "-sdk", str(SDK), "-package-name", "swift_cad", "-DSWIFT_PACKAGE", "-DDEBUG", "-DNativeExchange",
              "-I", str(modules)]
    receipt = {"sourceRoot": str(source_root), "packageManifestSHA256": digest(source_root / "Package.swift"), "sourceSHA256": inputs, "reusedProducts": reused, "toolchain": str(SWIFT_BIN),
               "compilerSHA256": digest(SWIFT_BIN / "swiftc"),
               "compilerVersion": subprocess.check_output([str(SWIFT_BIN / "swiftc"), "--version"], env=ENV, text=True),
               "sdk": str(SDK), "sdkSettingsSHA256": digest(SDK / "SDKSettings.json"), "steps": {}}
    if collections_descriptor:
        receipt["collectionsProductsReceipt"] = collections_descriptor
    if external:
        receipt["externalDependencyReceipt"] = {"path": str(args.dependency_receipt.resolve()),
            "sha256": digest(args.dependency_receipt),
            "products": external["products"], "resourceBundles": external["productionResourceBundles"],
            "resourceAccessors": external["productionResourceAccessors"]}
    def module_flags(module):
        return common[:-2] + (["-DCAD_EXCHANGE"] if module == "SwiftCAD" else []) + common[-2:]
    resumed = set()
    if args.resume:
        prior_bytes = args.resume.read_bytes()
        prior = json.loads(prior_bytes)
        receipt["resumeSelection"] = {"receipt": str(args.resume.resolve()),
            "sha256": hashlib.sha256(prior_bytes).hexdigest(),
            "reuseThrough": args.reuse_through, "explicitPrefix": args.reuse_through is not None}
        (output / "resume-source-receipt.json").write_bytes(prior_bytes)
        reuse_modules = (selected_modules[:selected_modules.index(args.reuse_through) + 1]
                         if args.reuse_through else selected_modules)
        if prior.get("reusedProducts") != reused:
            raise RuntimeError("Unchanged module reuse has different dependency products.")
        for key in ["compilerSHA256", "sdk", "sdkSettingsSHA256"]:
            if prior.get(key) != receipt[key]:
                raise RuntimeError("Unchanged module reuse has a different compiler/SDK: " + key)
        for module in reuse_modules:
            step = prior.get("steps", {}).get(module)
            expected = prior.get("products", {}).get(module)
            if not step or step["exitCode"] != 0 or step.get("stopReason") is not None or not expected:
                if args.reuse_through:
                    raise RuntimeError("Selected reuse prefix lacks a successful accepted module: " + module)
                break
            prefix = "Sources/" + module + "/"
            current_inputs = {key: value for key, value in inputs.items() if key.startswith(prefix)}
            previous_inputs = {key: value for key, value in prior["sourceSHA256"].items() if key.startswith(prefix)}
            if current_inputs != previous_inputs:
                raise RuntimeError("Unchanged module reuse has different source inputs: " + module)
            flags = module_flags(module)
            if step["command"][:len(flags) - 1] != flags[:-1]:
                raise RuntimeError("Unchanged module reuse has different compilation flags: " + module)
            if needs_openusd(module) and prior.get("externalDependencyReceipt") != receipt.get("externalDependencyReceipt"):
                raise RuntimeError("Unchanged upper module reuse has different OpenUSD products/resources: " + module)
            for relative, expected_input in previous_inputs.items():
                if digest(args.resume.parent / "snapshot" / relative) != expected_input:
                    raise RuntimeError("Retained compiler source differs from its receipt: " + relative)
            origin_path = Path(step.get("reusedFrom", args.resume)).resolve()
            origin = json.loads(origin_path.read_bytes())
            origin_step = origin.get("steps", {}).get(module)
            if (not origin_step or origin_step.get("exitCode") != 0
                    or origin_step.get("stopReason") is not None or origin_step.get("reusedFrom")
                    or origin_step.get("command") != step["command"]
                    or origin_step.get("logSHA256") != step["logSHA256"]
                    or origin.get("products", {}).get(module) != expected):
                raise RuntimeError("Selected reuse module lacks its original successful compiler origin: " + module)
            if digest(origin_path.parent / (module + ".log")) != step["logSHA256"]:
                raise RuntimeError("Original successful compiler log changed: " + module)
            for key in ["compilerSHA256", "compilerVersion", "sdk", "sdkSettingsSHA256", "reusedProducts"]:
                if origin.get(key) != prior.get(key):
                    raise RuntimeError("Original reuse compiler premise changed: " + module + "/" + key)
            for relative, expected_input in previous_inputs.items():
                if (origin.get("sourceSHA256", {}).get(relative) != expected_input
                        or digest(origin_path.parent / "snapshot" / relative) != expected_input):
                    raise RuntimeError("Original reuse compiler source changed: " + relative)
            origin_module = Path(origin_step["command"][origin_step["command"].index("-emit-module-path") + 1])
            if digest(origin_module) != expected:
                raise RuntimeError("Original reuse compiled module changed: " + module)
            if args.objects:
                origin_object = Path(origin_step["command"][origin_step["command"].index("-o") + 1])
                if digest(origin_object) != prior.get("objects", {}).get(module):
                    raise RuntimeError("Original reuse compiled object changed: " + module)
            if args.objects and origin.get("objects", {}).get(module) != prior.get("objects", {}).get(module):
                raise RuntimeError("Original reuse object premise changed: " + module)
            prior_product = args.resume.parent / "modules" / (module + ".swiftmodule")
            if digest(prior_product) != expected:
                raise RuntimeError("Retained module differs from its receipt: " + module)
            shutil.copyfile(prior_product, modules / prior_product.name)
            receipt.setdefault("products", {})[module] = expected
            if args.objects:
                expected_object = prior.get("objects", {}).get(module)
                prior_object = args.resume.parent / "modules" / (module + ".o")
                if not expected_object or digest(prior_object) != expected_object:
                    raise RuntimeError("Retained object differs from its receipt: " + module)
                shutil.copyfile(prior_object, modules / prior_object.name)
                receipt.setdefault("objects", {})[module] = expected_object
            receipt["steps"][module] = dict(step, reusedFrom=step.get("reusedFrom", str(args.resume.resolve())))
            resumed.add(module)
        receipt["resumeSelection"]["reusedModules"] = [module for module in selected_modules if module in resumed]
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2))
    print(str(output), flush=True)
    total_started = time.monotonic()
    for module in selected_modules:
        if module in resumed:
            print(module, "unchanged receipt-verified module reused", flush=True)
            continue
        command = module_flags(module) + ["-module-name", module, "-emit-module", "-emit-module-path", str(modules / (module + ".swiftmodule"))]
        if args.objects:
            command += ["-emit-object", "-o", str(modules / (module + ".o"))]
        command += sources[module]
        step = run(command, output / (module + ".log"), max(1, 1200 - (time.monotonic() - total_started)))
        receipt["steps"][module] = step
        if step["exitCode"] == 0:
            receipt.setdefault("products", {})[module] = digest(modules / (module + ".swiftmodule"))
            if args.objects:
                receipt.setdefault("objects", {})[module] = digest(modules / (module + ".o"))
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2))
        print(module, step["exitCode"], round(step["elapsedSeconds"], 2), "seconds", step["peakRSSBytes"], "peak bytes", flush=True)
        if step["exitCode"] != 0:
            errors = []
            for line in (output / (module + ".log")).read_text().splitlines():
                match = re.match(r".*snapshot/(Sources/[^:]+):(\d+):\d+: error: (.*)", line)
                if match:
                    errors.append({"file": match[1], "line": int(match[2]), "message": match[3]})
            (output / "errors.json").write_text(json.dumps(errors, indent=2))
            print(len(errors), "source diagnostics in", len({error["file"] for error in errors}), "files", flush=True)
            sys.exit(step["exitCode"] if step["exitCode"] > 0 else 1)

    if collections_descriptor:
        if verify_collections_products(args.collections_products)[1] != collections_descriptor:
            raise RuntimeError("Collections dependency receipt changed during generation.")
    if external:
        verify_openusd_receipt(args.dependency_receipt, source_root)
        for bundle in external["productionResourceBundles"]:
            if tree_hashes(output / "resources" / Path(bundle["path"]).name) != bundle["files"]:
                raise RuntimeError("Copied OpenUSD resource bundle changed.")
