#!/usr/bin/env python3
"""Compile only the additive identity bodies against their actual retained owner."""
import argparse,json,subprocess
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[2];out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
prior=root/'.build/s-ruled-closed-guide-seam-native-20261012-v2'
flags=json.loads((prior/'compile-proof.json').read_text())
prefix=(root/'.build/s-ruled-closed-guide-seam-native-20261012-v1/OriginalRuledSurfaceSnapshot.swift').read_text().split('/// The original ruled value',1)[0]
prefix+='\nimport enum RetainedHostAdapters.OriginalDomainAccess\nimport class RetainedHostAdapters.OriginalIdentityReadmission\n'
owner=root/'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity'
inputs=[owner/n for n in ['OriginalRationalSourceBoundaryDeclaration.swift','OriginalLawBoundParameterIdentityIssuing.swift','DefaultOriginalParameterIdentityIssuer+LawBoundBoundary.swift']]
inputs.append(Path(__file__).with_suffix('.swift'))
generated=[]
for source in inputs:
    target=out/source.name;target.write_text(prefix+'\n'+source.read_text());generated.append(str(target))
archives=[v for v in flags if v.endswith('.a')]
command=flags[:flags.index('-emit-executable')]+['-emit-executable',*generated,*archives,'-o',str(out/'Proof')]
(out/'compile.json').write_text(json.dumps(command,indent=2)+'\n')
with (out/'compile.log').open('w') as log:
    subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120,check=True)
with (out/'run.log').open('w') as log:
    subprocess.run([str(out/'Proof')],cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120,check=True)
print((out/'run.log').read_text(),end='')
