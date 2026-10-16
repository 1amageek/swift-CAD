"""Load an immutable accepted Core/Geometry lane. This module never launches a process."""
import hashlib
import json
from pathlib import Path

BIN = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin')


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_files(files):
    for path, expected in files.items():
        require(digest(path) == expected, 'Pinned input or product changed: ' + str(path))


def load_core_geometry_prefix(receipt_path, native_receipt_path, lane, source_root):
    """Return checked source/product pins and exact accepted lane compiler/link settings."""
    receipt_path = Path(receipt_path).resolve()
    native_receipt_path = Path(native_receipt_path).resolve()
    source_root = Path(source_root).resolve()
    require(lane in ['asan', 'wasm', 'embedded'], 'Unsupported selected lane.')
    prefix = json.loads(receipt_path.read_text())
    native = json.loads(native_receipt_path.read_text())
    require(prefix['status'] == 'passed', 'The immutable portable prefix was not accepted.')
    require(prefix['sourceRoot'] == str(source_root) and native['sourceRoot'] == str(source_root), 'Source owner differs.')
    require(not prefix['currentDrift'] and not prefix['snapshotDrift'] and not prefix['productDrift'], 'Portable prefix had drift.')
    sources = {path: sha for path, sha in native['sourceSHA256'].items()
        if path.startswith('Sources/CADCore/') or path.startswith('Sources/CADGeometry/')}
    require(sources == prefix['sourceSHA256'], 'Portable Core/Geometry source authority differs.')
    require(prefix['sourceCount'] == {'CADCore': 67, 'CADGeometry': 2170}, 'Unexpected frozen Core/Geometry inventory.')
    files = {str(receipt_path): digest(receipt_path), str(native_receipt_path): digest(native_receipt_path),
        str(Path(__file__).resolve()): digest(Path(__file__))}
    for module in ['CADCore', 'CADGeometry']:
        step = native['steps'][module]
        require(step['exitCode'] == 0 and step.get('stopReason') is None, 'Native source authority was not accepted: ' + module)
        actual = {str(path.relative_to(source_root)) for path in (source_root / 'Sources' / module).rglob('*.swift')}
        require(actual == {path for path in sources if path.startswith('Sources/' + module + '/')}, 'Source inventory changed: ' + module)
    for path, sha in sources.items():
        files[str(source_root / path)] = sha
        files[str(receipt_path.parent / 'snapshot' / path)] = sha
    selected = prefix['lanes'][lane]
    phases = {}
    for name in ['core-compile', 'compile', 'link', 'runtime']:
        phase = next(item for item in prefix['phases'] if item['name'] == lane + '-' + name)
        require(phase['exitCode'] == 0 and phase.get('stopReason') is None, 'Unaccepted portable prefix phase: ' + name)
        require(phase['command'] == selected['commands'][name], 'Retained successful command differs: ' + name)
        files[phase['log']] = phase['logSHA256']
        phases[name] = phase
    require(len(selected['matchedOracleLines']) == 8, 'Selected prefix did not execute all eight oracles.')
    compile_command = selected['commands']['compile']
    require(compile_command[0] == str(BIN / 'swiftc') and compile_command[compile_command.index('-package-name') + 1] == 'swift_cad', 'Compiler or package owner differs.')
    require(compile_command[compile_command.index('-target') + 1] == ('arm64-apple-macos27.0' if lane == 'asan' else 'wasm32-unknown-wasip1'), 'Target differs.')
    require(('-enable-experimental-feature' in compile_command and 'Embedded' in compile_command) == (lane == 'embedded'), 'Embedded mode differs.')
    require('-Onone' in compile_command and '-whole-module-optimization' in compile_command, 'Required debug WMO configuration differs.')
    for name, response_sha, module in [('core-compile', selected['coreResponseSHA256'], 'CADCore'), ('compile', selected['responseSHA256'], 'CADGeometry')]:
        response = next(Path(value[1:]) for value in selected['commands'][name] if value.startswith('@'))
        files[str(response)] = response_sha
        require({value.strip().strip('"') for value in response.read_text().splitlines()} ==
            {str(receipt_path.parent / 'snapshot' / path) for path in sources if path.startswith('Sources/' + module + '/')}, 'Compiler source response differs: ' + module)
    products = {**selected['compiledCoreProductSHA256'], **selected['compiledProductSHA256']}
    files.update(products)
    for path, evidence in selected['dependencies'].items():
        files[path] = evidence['sha256']
        files[evidence['source']] = evidence['sha256']
        products[path] = evidence['sha256']
    require(any(Path(path).name == 'HashTreeCollections.swiftmodule' for path in products), 'Actual Collections module missing.')
    for name, sha in prefix['toolSHA256'].items():
        files[str(BIN / name)] = sha
    for name, sha in prefix['wasmSDK']['metadataSHA256'].items():
        files[str(Path(prefix['wasmSDK']['path']) / name)] = sha
    files[str(Path(prefix['nativeSDK']['path']) / 'SDKSettings.json')] = prefix['nativeSDK']['SDKSettings.json']
    files[prefix['nativeLinker']['path']] = prefix['nativeLinker']['sha256']
    files.update(selected['platformArchiveSHA256'])
    old_link = selected['commands']['link']
    objects = [value for value in old_link if value.endswith('.o')]
    require(not objects if lane == 'embedded' else len(objects) == 4, 'Unexpected library emission model.')
    for path in objects:
        require(path in products, 'Unreceipted lower link object: ' + path)
    old_runtime = selected['commands']['runtime']
    if lane != 'asan':
        for path in old_runtime[:2]:
            files[path] = digest(path)
    verify_files(files)
    return {'files': files, 'native': native, 'selected': selected,
        'sources': sources, 'products': products, 'objects': objects,
        'flags': compile_command[1:compile_command.index('-module-name')],
        'linkTail': old_link[old_link.index('-o') + 2:],
        'runtimePrefix': [] if lane == 'asan' else old_runtime[:2],
        'receipt': {'path': str(receipt_path), 'sha256': digest(receipt_path)},
        'nativeReceipt': {'path': str(native_receipt_path), 'sha256': digest(native_receipt_path)}}
