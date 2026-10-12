#!/usr/bin/env python3
"""Prepare the current retained-guard source phase and unchanged upper closure."""
import hashlib
import importlib.util
import sys
from pathlib import Path
ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
OUT = Path(__file__).resolve().parent
BASE = ROOT / '.build/cs-implicit-dyadic-parabola-acceptance-native-20261013-v7'
spec = importlib.util.spec_from_file_location('driver', ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)
driver.OUT = OUT
mode = sys.argv[1]
if mode == 'source':
    expected = driver.read(OUT/'frozen-source-hashes.json')
    assert len(expected) == 5
    driver.NAMES = expected
    driver.prepare_source()
    metadata = driver.read(OUT/'source-premises.json')
    metadata['newBodies'] = metadata['actualSourceBodyCount'] = 5
    metadata['guardReduction'] = 'All 27 original/substituted conditions retained; only source-proved whole-domain tautologies omitted from solver graph.'
    driver.save(OUT/'source-premises.json', metadata)
    checks = metadata['checks']
    for file in ['source-premises.json','frozen-source-hashes.json','Prepare.py']:
        checks[str(OUT/file)] = driver.sha(OUT/file)
    driver.bounded('source-compile', driver.read(OUT/'source-command.json'), checks)
elif mode == 'upper':
    source = driver.read(OUT/'source-compile-receipt.json')
    assert source['exitCode'] == 0 and source['postHashesMatch']
    old = driver.read(BASE/'upper-premises.json')
    checks = dict(old['checks'])
    # The previous fixture is immutable in BASE/Proof.swift; bind the new selected fixture separately.
    fixture = ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.swift'
    checks.pop(str(fixture), None)
    for binding in source['checks']:
        checks[binding] = source['checks'][binding]
    checks.update(source['products'])
    checks[str(OUT/'source-compile-receipt.json')] = driver.sha(OUT/'source-compile-receipt.json')
    bindings = []
    remap = {}
    generated = []
    for binding in old['bindings']:
        original = Path(binding['original'])
        assert driver.sha(original) == binding['originalSHA256'], 'Upper production changed: '+str(original)
        prior = Path(binding['generated'])
        data = prior.read_bytes()
        assert driver.sha(prior) == binding['generatedSHA256'] and data.endswith(original.read_bytes())
        prefix = data[:-len(original.read_bytes())]
        target = OUT/original.name
        target.write_bytes(prefix+original.read_bytes())
        checks[str(target)] = driver.sha(target)
        remap[str(prior)] = str(target)
        generated.append(target)
        bindings.append(dict(original=str(original),originalSHA256=driver.sha(original),generated=str(target),generatedSHA256=driver.sha(target),prefixSHA256=hashlib.sha256(prefix).hexdigest()))
    assert len(generated) == 56
    oldproof = (BASE/'Proof.swift').read_bytes()
    oldfixture = (BASE/'fixture-at-reduced-runtime.swift').read_bytes()
    assert oldproof.endswith(oldfixture)
    prefix = oldproof[:-len(oldfixture)]
    assert b'import struct DraftZeroRuledPort.NativeExactPublicAdmission' in prefix
    assert b'NativeDepthTracingAdmission' not in fixture.read_bytes()
    proof = OUT/'Proof.swift'
    proof.write_bytes(prefix+fixture.read_bytes())
    adapter = OUT/'ActualSelectorDeclineAdapters.swift'
    adapter_source = Path(next(v for v in driver.read(BASE/'upper-command.json') if v.endswith('/ActualSelectorDeclineAdapters.swift')))
    adapter.write_bytes(adapter_source.read_bytes())
    checks[str(proof)] = driver.sha(proof)
    checks[str(fixture)] = driver.sha(fixture)
    checks[str(adapter)] = driver.sha(adapter)
    command = driver.read(BASE/'upper-command.json')
    command = [remap.get(v,v.replace(str(BASE/'source'),str(OUT/'source'))) for v in command]
    command[command.index('-module-cache-path')+1] = str(OUT/'module-cache')
    for name in ['Proof.swift','ActualSelectorDeclineAdapters.swift','Acceptance']:
        command = [str(OUT/name) if v.endswith('/'+name) else v for v in command]
    assert len([v for v in command if v.endswith('.swift')]) == 58
    assert len([v for v in command if v.endswith('.a')]) == 14
    driver.save(OUT/'upper-command.json',command)
    checks[str(OUT/'upper-command.json')] = driver.sha(OUT/'upper-command.json')
    checks[str(Path(__file__).resolve())] = driver.sha(__file__)
    metadata = dict(checks=checks,bindings=bindings,upperBodies=56,swiftInputs=58,archives=14,currentSourceBodyCount=5,lowerBodies=0,groups=['complete','empty'],admission='Unmodified admitted DraftZeroRuledPort.NativeExactPublicAdmission; no diagnostic shadow',sourceModuleReceipt=str(OUT/'source-compile-receipt.json'),historicalChecks='Prior immutable support snapshots/products remain bound; only bindings and current source phase identify selected compiler bodies.')
    driver.save(OUT/'upper-premises.json',metadata)
    checks[str(OUT/'upper-premises.json')] = driver.sha(OUT/'upper-premises.json')
    driver.check(checks)
    print({'upperBodies':56,'swiftInputs':58,'archives':14,'checks':len(checks)})
    result = driver.bounded('upper-compile',command,checks)
    if result['exitCode'] == 0:
        result['products'] = {str(OUT/'Acceptance'):driver.sha(OUT/'Acceptance')}
        driver.save(OUT/'upper-compile-receipt.json',result)
else:
    assert mode in ['complete','empty']
    metadata = driver.read(OUT/'upper-premises.json')
    checks = metadata['checks']
    checks[str(OUT/'upper-premises.json')] = driver.sha(OUT/'upper-premises.json')
    checks[str(Path(__file__).resolve())] = driver.sha(__file__)
    result = driver.read(OUT/'upper-compile-receipt.json')
    assert result['exitCode'] == 0
    driver.bounded('runtime-'+mode,[str(OUT/'Acceptance'),mode],checks,result['products'])
