"""Bind compiler snapshots and receipt hashes to the same captured bytes."""
import hashlib


def copy_input(source, target, root, hashes, prefix=b''):
    content = source.read_bytes()
    name = str(source.relative_to(root))
    captured_hash = hashlib.sha256(content).hexdigest()
    target.write_bytes(prefix + content)
    hashes[name] = captured_hash
    return target


def require_unchanged_inputs(root, hashes):
    for name, expected_hash in hashes.items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected_hash:
            raise RuntimeError('Source changed during verification: ' + name)
