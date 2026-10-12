#!/usr/bin/env python3
"""Compile the frozen source-owned original/unique-forward reduction once."""
import importlib.util
from pathlib import Path
ROOT=Path('/private/tmp/cad-m4-m8-completion-20261010')
spec=importlib.util.spec_from_file_location('driver',ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.py')
driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver)
driver.OUT=Path(__file__).resolve().parent
driver.NAMES['DefaultOriginalFiniteImplicitCurveGraphPreparer.swift']='b27d71a03a6c0498f1a89d5dbead88a8fd477fe1764c327677bb972103f543cb'
driver.NAMES['OriginalImplicitCurveGraphReduction.swift']='fa34287c9e1caf4688effef54fe01f4107a46dc6389d3afbb4e0a67748a8f903'
driver.prepare_source()
premises=driver.read(driver.OUT/'source-premises.json');checks=premises['checks'];checks[str(driver.OUT/'source-premises.json')]=driver.sha(driver.OUT/'source-premises.json');checks[str(Path(__file__).resolve())]=driver.sha(__file__)
driver.bounded('source-compile',driver.read(driver.OUT/'source-command.json'),checks)
