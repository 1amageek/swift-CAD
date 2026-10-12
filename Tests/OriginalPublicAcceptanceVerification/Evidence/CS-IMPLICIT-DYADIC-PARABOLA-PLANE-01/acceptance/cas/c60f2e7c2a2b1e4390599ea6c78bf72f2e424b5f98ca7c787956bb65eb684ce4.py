#!/usr/bin/env python3
"""Concrete nominal-owner repair, preserving the observed failed assembly."""
import importlib.util
import sys
from pathlib import Path
ROOT=Path('/private/tmp/cad-m4-m8-completion-20261010')
spec=importlib.util.spec_from_file_location('driver', ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.py')
driver=importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
driver.OUT=Path(__file__).resolve().parent
meta=driver.read(driver.OUT/'upper-premises.json')
checks=meta['checks']; checks[str(driver.OUT/'upper-premises.json')]=driver.sha(driver.OUT/'upper-premises.json'); checks[str(Path(__file__).resolve())]=driver.sha(__file__)
mode=sys.argv[1]
if mode=='compile':
 record=driver.bounded('upper-compile',driver.read(driver.OUT/'upper-command.json'),checks)
 if record['exitCode']==0:
  record['products']={str(driver.OUT/'Acceptance'):driver.sha(driver.OUT/'Acceptance')}; driver.save(driver.OUT/'upper-compile-receipt.json',record)
else:
 record=driver.read(driver.OUT/'upper-compile-receipt.json'); assert record['exitCode']==0
 driver.bounded('runtime-'+mode,[str(driver.OUT/'Acceptance'),mode],checks,record['products'])
