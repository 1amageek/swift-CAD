from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time
r=Path.cwd();lane='native';base=r/'.build/coincident-cone-ssi-20261014/v2';out=base/'compatibility-native';out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
products=json.loads((base/lane/'geometry-products.json').read_text());products.update(json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-BOUNDED-01/reused-products.json').read_text()))
for p,h in products.items():assert sha(p)==h,p
flags=json.loads((base/lane/'public-compile.json').read_text())['command'];flags=flags[:flags.index('-module-name')]
inputs={};artifacts={}
for name in ['CommonApexConeFamilyAcceptance','ApexSphereConeSSIAcceptance']:
 p=r/'Tests/OriginalPublicAcceptanceVerification'/(name+'.swift');q=out/p.name;data=p.read_text()
 if name=='CertifiedSphereConeApexEmptyAcceptance':
  for prefix in ['RetainedHostAdapters.','CertifiedApexSourcePhase.','AngularSourcePhase.']:data=data.replace(prefix,'')
  data=data.replace('DefaultSurfaceSurfaceIntersector().intersections(\n            first: sphere, second: cone, tolerance: .standard)', 'SphereConeApexContactIntersector().intersectionsIfApplicable(sphereSurface: sphere, coneSurface: cone, firstSurface: sphere, secondSurface: cone, options: .init(), tolerance: .standard)!')
  data=data.replace('DefaultSurfaceSurfaceIntersector().intersections(first: selectedOriginal.sphereSurface,\n            second: selectedOriginal.coneSurface, tolerance: .standard)', 'SphereConeApexContactIntersector().intersectionsIfApplicable(sphereSurface: selectedOriginal.sphereSurface, coneSurface: selectedOriginal.coneSurface, firstSurface: selectedOriginal.sphereSurface, secondSurface: selectedOriginal.coneSurface, options: .init(), tolerance: .standard)!')
 q.write_text(data);inputs[str(p.relative_to(r))]=sha(p)
 exe=out/name;run(flags+['-module-name',name,str(q),str(base/lane/'libCADGeometry.a'),'@'+str(r/'.build/drafted-sheet-20261014/native/dependencies.rsp'),'-o',str(exe)],name+'-compile',seconds=180)
 if name=='CertifiedSphereConeApexEmptyAcceptance':
  for group in ['complete','dispatch','source']:run([str(exe),group],name+'-'+group,seconds=180)
 else:run([str(exe)],name+'-runtime',seconds=180)
 artifacts[str(exe)]=sha(exe)
paths=[]
for name in ['BooleanIntersectionGraph','BooleanFaceSurfaceIntersection','BooleanFacePairCandidate','BooleanBoundaryContact','BooleanBoundaryContactGeometry']:
 p=r/'Sources/CADKernel'/(name+'.swift');q=out/p.name;q.write_bytes(p.read_bytes());paths.append(str(q));inputs[str(p.relative_to(r))]=sha(p)
p=r/'Tests/OriginalPublicAcceptanceVerification/CoincidentConeSSIKernelAcceptance.swift';q=out/p.name;q.write_bytes(p.read_bytes());paths.append(str(q));inputs[str(p.relative_to(r))]=sha(p)
topo=r/'.build/trimmed-fold-20261013/edge-native/libCADTopology.a';assert sha(topo)==products[str(topo)]
exe=out/'KernelGraph';run(flags+['-module-name','CoincidentConeSSIKernelAcceptance',*paths,str(base/lane/'libCADGeometry.a'),str(topo),'@'+str(r/'.build/drafted-sheet-20261014/native/dependencies.rsp'),'-o',str(exe)],'kernel-compile',seconds=180)
run([str(exe)],'kernel-runtime',seconds=180);artifacts[str(exe)]=sha(exe)
(out/'accepted.json').write_text(json.dumps(dict(sources=inputs,reusedProducts=products,products=artifacts),indent=2)+'\n')
