"""Run the existing concrete callback port through the production embedding API."""
from pathlib import Path
import sys
r=Path.cwd()
driver=r/'Tests/OriginalPublicAcceptanceVerification/EmbeddingCallerAcceptance.py'
source=driver.read_text()
old="fixture = r / 'Tests/OriginalPublicAcceptanceVerification/EmbeddingCallerAcceptance.swift'"
assert source.count(old)==1
source=source.replace(old,"fixture = r / 'Tests/OriginalPublicAcceptanceVerification/EmbeddingCallerSharedAdmission.swift'")
old="flags[1:1] = ['-I', str(geometry)]"
assert source.count(old)==1
source=source.replace(old,old+"\nif lane=='embedded': flags[flags.index('-num-threads')+1]='4'")
source=source.replace('for p in (fixture, frozen, Path(__file__).resolve())','for p in (fixture, frozen, driver, Path(__file__).resolve())')
exec(compile(source,str(driver),'exec'))
