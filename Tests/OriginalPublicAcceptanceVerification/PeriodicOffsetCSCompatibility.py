"""Check the shared type boundary and retained Coons/rolling public witnesses."""
from pathlib import Path
import hashlib, json, os, subprocess, time
r=Path.cwd(); out=r/'.build/periodic-offset-cs-20261013/compatibility';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
base=r/'.build/periodic-offset-cs-20261013/native'
checks=json.loads((base/'linked-products.json').read_text())
for p,h in checks.items():assert sha(p)==h,p
for p,h in json.loads((base/'objects.json').read_text())['inputs'].items():assert sha(p)==h,p
lower=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-ROLLING-BALL-PLANE-01/accepted/standalone-l0/receipt.json'
for p,h in json.loads(lower.read_text())['checks'].items():assert sha(p)==h,p
records=[]
def run(command,name,env=None):
    start=time.monotonic();p=subprocess.run(command,capture_output=True,text=True,timeout=120,env=env)
    log=out/(name+'.log');log.write_text(p.stdout+p.stderr)
    record=dict(command=command,exitCode=p.returncode,elapsedSeconds=time.monotonic()-start,logSHA256=sha(log))
    records.append(record);print(name,p.returncode,flush=True)
    if p.returncode:print(log.read_text()[-3000:]);raise SystemExit(p.returncode)
    return p.stdout
swift='/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc'
flags=['-parse-as-library','-swift-version','6','-Onone','-I',str(out),'-I',str(r/'.build/rolling-ssi-20261013/standalone-l0')]
g=r/'Sources/CADGeometry'
def module(name,define,paths):
    paths=sorted(paths);checks.update({str(p):sha(p)for p in paths})
    run([swift,*flags,'-module-name',name,'-D',define,'-emit-module','-emit-module-path',str(out/(name+'.swiftmodule')),*map(str,paths)],name)
    checks[str(out/(name+'.swiftmodule'))]=sha(out/(name+'.swiftmodule'))
module('L1','L1_ISOLATED_VERIFICATION',(g/'RationalBivariateAlgebra/ExactPolynomial').rglob('*.swift'))
module('DI0','EXACT_DOMAIN_ISOLATED_VERIFICATION',(g/'OriginalDomainIdentity/ExactParameterDomain').rglob('*.swift'))
module('SourceIssuer','ORIGINAL_SOURCE_ISOLATED_VERIFICATION',[g/'OriginalSourceIssuance'/n for n in ['OriginalSourceIssuanceFailure.swift','OriginalSourceIssuanceLimits.swift']])
module('DI','ORIGINAL_DOMAIN_ISOLATED_VERIFICATION',[g/'OriginalDomainIdentity'/n for n in ['OriginalDomainAccess.swift','OriginalDomainIdentityFailure.swift','OriginalDomainIdentityLimits.swift','OriginalParameterTransport/OriginalParameterCycle.swift']])
module('PeriodicOffsetSharedBoundary','ISSUED_GEOMETRY_ISOLATED_VERIFICATION',[r/'Tests/OriginalGraphRelationVerification/Sources/IssuedGeometry'/n for n in ['OriginalPeriodicOffsetContactTemplate.swift','OriginalPeriodicOffsetContactMember.swift']])
fixtureCommand=json.loads((base/'fixture.json').read_text())['command']
for name,path in [('rolling',r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift'),('coons',r/'.build/rolling-ssi-20261013/native/coons-regression/CoonsWitnessRegression.swift')]:
    text=path.read_text();needle='        guard let receipt = result.originalIssuedGeometricRelation else'
    assert needle in text
    line=next(line for line in text.splitlines()if needle in line)
    text=text.replace(line,line+'\n        try require(receipt.periodicOffsetContacts.isEmpty)',1)
    fixture=out/(name+'.swift');fixture.write_text(text);checks[str(fixture)]=sha(fixture)
    command=[str(fixture)if x.endswith('PeriodicOffsetCSStop.swift')else x for x in fixtureCommand];command[-1]=str(out/name)
    run(command,name+'-compile');checks[str(out/name)]=sha(out/name)
    for group in ['success','empty']:
        stdout=run([str(out/name)],name+'-'+group,dict(os.environ,CAD_PROOF_GROUP=group))
        assert 'PASS '+group in stdout,(name,group)
for p,h in checks.items():assert sha(p)==h,p
(out/'receipt.json').write_text(json.dumps(dict(status='PASS',checks=checks,records=records,scope='Actual shared scalar/domain type closure; full L1/DI0, minimal actual SourceIssuer/DI declarations, no substitute types. Coons/rolling current public witness success and complete empty.'),indent=2)+'\n')
