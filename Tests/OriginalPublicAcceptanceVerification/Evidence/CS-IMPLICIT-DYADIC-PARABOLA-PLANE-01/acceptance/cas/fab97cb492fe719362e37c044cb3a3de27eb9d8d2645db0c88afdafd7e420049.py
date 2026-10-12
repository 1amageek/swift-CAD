#!/usr/bin/env python3
"""Compile the unchanged current producer closure with finite acceptance controls."""
import importlib.util
import sys
from pathlib import Path
ROOT=Path('/private/tmp/cad-m4-m8-completion-20261010')
OUT=Path(__file__).resolve().parent
BASE=ROOT/'.build/cs-implicit-dyadic-parabola-acceptance-native-20261013-v9'
spec=importlib.util.spec_from_file_location('driver',ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.py')
driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver);driver.OUT=OUT
mode=sys.argv[1]
if mode=='compile':
 meta=driver.read(BASE/'upper-premises.json');checks=dict(meta['checks'])
 fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.swift'
 checks.pop(str(fixture),None)
 command=driver.read(BASE/'upper-command.json')
 prior=(BASE/'Proof.swift').read_bytes(); priorfixture=(BASE/'fixture-at-runtime.swift').read_bytes()
 assert prior.endswith(priorfixture)
 proof=OUT/'Proof.swift';proof.write_bytes(prior[:-len(priorfixture)]+fixture.read_bytes())
 checks[str(fixture)]=driver.sha(fixture);checks[str(proof)]=driver.sha(proof)
 command=[str(proof) if p==str(BASE/'Proof.swift') else p for p in command]
 command[command.index('-module-cache-path')+1]=str(OUT/'module-cache')
 command[command.index('-o')+1]=str(OUT/'Acceptance')
 driver.save(OUT/'upper-command.json',command)
 checks[str(OUT/'upper-command.json')]=driver.sha(OUT/'upper-command.json')
 checks[str(Path(__file__).resolve())]=driver.sha(__file__)
 meta['checks']=checks;meta['groups']=['ordinary','source','selections','continuous','limits','budgets','cancel-entry','cancel-mid','cancel-final','cancel-empty','lifetime']
 meta['sourceReusedFrom']=str(BASE/'source-compile-receipt.json')
 driver.save(OUT/'upper-premises.json',meta)
 checks[str(OUT/'upper-premises.json')]=driver.sha(OUT/'upper-premises.json')
 result=driver.bounded('upper-compile',command,checks)
 if result['exitCode']==0:
  result['products']={str(OUT/'Acceptance'):driver.sha(OUT/'Acceptance')};driver.save(OUT/'upper-compile-receipt.json',result)
else:
 meta=driver.read(OUT/'upper-premises.json');checks=meta['checks']
 checks[str(OUT/'upper-premises.json')]=driver.sha(OUT/'upper-premises.json')
 checks[str(Path(__file__).resolve())]=driver.sha(__file__)
 result=driver.read(OUT/'upper-compile-receipt.json');assert result['exitCode']==0
 driver.bounded('runtime-'+mode,[str(OUT/'Acceptance'),mode],checks,result['products'])
