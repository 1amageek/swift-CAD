#!/usr/bin/env python3
"""Compile fresh issued-graph/M5/self upper bodies against admitted retained contracts."""
from pathlib import Path
import argparse,ast,hashlib,json,os,resource,signal,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--reuse-port',type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[2];out=args.output.resolve();out.mkdir(exist_ok=False,parents=True)
prior=root/'.build/s-ruled-closed-guide-seam-native-20261012-v2';oldport=root/'.build/cs-draft-zero-ruled-native-20261011-v2'
r=json.loads((prior/'failure-receipt.json').read_text());checks={};fresh=r['freshProduction'].copy();runs=[];historical=r['historicalComparators'].copy()
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h=None):
 p=Path(p);h=h or sha(p);assert sha(p)==h,str(p);checks[str(p)]=h
def recheck():
 for n,h in checks.items():assert sha(n)==h,n
 for n,h in fresh.items():assert sha(n)==h,n
# Preserve exact cached prechange source comparators instead of calling them current.
for n,h in r['checks'].items():
 path=Path(n)
 if sha(path)==h:admit(path,h);continue
 assert path.parent == root/'Sources/CADGeometry/NativeExactRelations',n
 generated=oldport/'generated'/path.name;source=generated.read_text();body=source[source.index('#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION'):]
 assert hashlib.sha256(body.encode()).hexdigest()==h,n
 target=out/'historical-source'/path.name;target.parent.mkdir(exist_ok=True);target.write_text(body);admit(target,h)
 historical[n]=dict(path=str(target),sha256=h,scope='Original admitted prechange source; current source compiled separately')
admit(prior/'failure-receipt.json');admit(__file__)
fixture=Path(__file__).with_suffix('.swift');admit(fixture)
code=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.py';node=next(x for x in ast.parse(code.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='execute');exec(compile(ast.Module(body=[node],type_ignores=[]),str(code),'exec'))
prefix=(root/'.build/s-ruled-closed-guide-seam-native-20261012-v1/OriginalRuledSurfaceSnapshot.swift').read_text().split('/// The original ruled value',1)[0]
prefix+='\nimport enum RetainedHostAdapters.OriginalDomainAccess\nimport class RetainedHostAdapters.OriginalIdentityReadmission\n'
owner=root/'Sources/CADGeometry/NativeExactRelations'
names=['NativeExactRelationFailure','OriginalIssuedGraphPreparation','OriginalIssuedGraphFamily','OriginalIssuedGraphCompiling','OriginalIssuedGraphFamilyPreparing','DefaultOriginalIssuedGraphCompiler','DefaultOriginalRationalGraphFamilyPreparer','OriginalIssuedGraphRelationResolving','OriginalIssuedGraphRelationOwning','OriginalIssuedGraphRelationPair','OriginalIssuedGraphRelations','OriginalIssuedGraphPredicateEquivalence','OriginalIssuedGraphSolverEquivalence','DefaultOriginalIssuedGraphRelationResolver','OriginalIssuedGraphParameterRefining','OriginalIssuedGraphParameterRefinement','DefaultOriginalIssuedGraphParameterRefiner']
originals=[owner/(n+'.swift') for n in names]
identity=root/'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity'
originals += [identity/n for n in ['OriginalRationalSourceBoundaryDeclaration.swift','OriginalLawBoundParameterIdentityIssuing.swift','DefaultOriginalParameterIdentityIssuer+LawBoundBoundary.swift']]
embedding=root/'Sources/CADGeometry/OriginalSurfaceEmbedding'
originals += [embedding/n for n in ['OriginalIssuedGraphSelfContactQuerying.swift','OriginalIssuedGraphSelfContacts.swift','DefaultOriginalIssuedGraphSelfContactQuery.swift','OriginalIssuedGraphSelfIdentityCompiler.swift','OriginalIssuedGraphSelfContactRequestReading.swift','OriginalIssuedDomainCover+SelfContactRequest.swift']]
for path in originals:fresh[str(path)]=sha(path)
module=args.reuse_port.resolve() if args.reuse_port else out
try:
 save('admission.json',dict(checks=checks,freshProduction=fresh,historicalComparators=historical,selectedUpperBodies=len(originals),sameLedger=True))
 if args.reuse_port:
  cached=json.loads((module/'port-receipt.json').read_text());assert cached['freshProduction']==fresh
  for n,h in cached['checks'].items():
   if n not in [str(__file__),str(fixture)]:admit(n,h)
  admit(module/'port-receipt.json')
 else:
  generated=[]
  for path in originals:
   target=out/path.name;target.write_text(prefix+path.read_text());admit(target);generated.append(str(target))
  command=json.loads((root/'.build/s-ruled-closed-guide-seam-native-20261012-v1/compile-module.json').read_text());flags=command[:command.index('-emit-library')]
  command=flags+['-emit-library','-static','-emit-module','-module-name','GuideSeamPort',*generated,'-emit-module-path',str(out/'GuideSeamPort.swiftmodule'),'-o',str(out/'libGuideSeamPort.a')]
  save('compile-port.json',command);recheck();execute('compile-port',command)
  for name in ['GuideSeamPort.swiftmodule','libGuideSeamPort.a']:admit(out/name)
  save('port-receipt.json',dict(state='successful-fresh-upper-port',checks=checks,freshProduction=fresh,runs=runs));admit(out/'port-receipt.json')
 proof=out/'Proof.swift';proof.write_text(prefix+fixture.read_text());admit(proof)
 command=json.loads((prior/'compile-proof.json').read_text());flags=command[:command.index('-emit-executable')]+['-I',str(module)]
 archives=[x for x in command if x.endswith('.a') and not x.endswith('/libDraftZeroRuledPort.a')]
 command=flags+['-emit-executable',str(proof),str(module/'libGuideSeamPort.a'),*archives,'-o',str(out/'Acceptance')]
 save('compile-proof.json',command);recheck();execute('compile-proof',command);admit(out/'Acceptance')
 log=execute('runtime',[str(out/'Acceptance')]);recheck();save('receipt.json',dict(success=True,cellComplete=False,focusedNative=True,checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True))
 print(log);print('RECEIPT',sha(out/'receipt.json'))
except BaseException:
 recheck();save('failure-receipt.json',dict(success=False,cellComplete=False,checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True));raise
