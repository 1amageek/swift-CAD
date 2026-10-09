"""Validate newly rebuilt lower products without presenting compile evidence as runtime proof."""
from pathlib import Path
import hashlib
import json


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(root, products):
    build = products.parents[2]
    inputs = {}
    for listing in (build / 'out/Intermediates.noindex').rglob('*.SwiftFileList'):
        for line in listing.read_text().splitlines():
            source = Path(line.strip().strip('"')).resolve()
            if source.is_file():
                inputs[str(source.relative_to(root))] = digest(source)
    if not inputs:
        raise RuntimeError('Missing compiled lower source inventory')
    files = {}
    for module in ['L0', 'L1', 'DI0', 'L2', 'L3', 'L4', 'L5']:
        obj = products / (module + '.o')
        objects = [obj] if obj.is_file() else sorted((products / (module + '.objlib')).glob('*.o'))
        if not objects:
            raise RuntimeError('Missing rebuilt lower object: ' + module)
        for obj in objects:
            files[str(obj.relative_to(products))] = digest(obj)
        interface = products / (module + '.swiftmodule')
        if interface.is_dir():
            for path in interface.rglob('*'):
                if path.is_file(): files[str(path.relative_to(products))] = digest(path)
        elif interface.is_file(): files[str(interface.relative_to(products))] = digest(interface)
        else: raise RuntimeError('Missing rebuilt module interface: ' + module)
    manifest = {'inputs': inputs, 'products': files,
        'scope': 'Compiled independent L0-L5 and exact domains. Runtime behavior is verified by the consuming proof separately.'}
    (build / 'rebuild-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def checked(root, products):
    manifest = json.loads((products.parents[2] / 'rebuild-manifest.json').read_text())
    for name, expected in manifest['inputs'].items():
        if digest(root / name) != expected: raise RuntimeError('Changed rebuilt lower source: ' + name)
    for name, expected in manifest['products'].items():
        if digest(products / name) != expected: raise RuntimeError('Changed rebuilt lower product: ' + name)
    return manifest


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('products', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    capture(root, args.products.resolve())
