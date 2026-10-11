#!/usr/bin/env python3
"""Verify the one-chart Native directed whole-edge self-contact cell."""
import argparse, hashlib, json, os, resource, signal, subprocess, time
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('lane',choices=['native','asan','wasm','embedded'])
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--reuse-self4',type=Path)
parser.add_argument('--group',choices=['complete','controls','resources','all'],default='complete')
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
out=args.output.resolve()
assert out.is_relative_to(root/'.build')
out.mkdir(parents=True,exist_ok=False)
checks,fresh,products,runs,historical={},{},{},[],{}
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_text())

def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def admit(path, expected):
    path = Path(path)
    assert path.is_file() and sha(path) == expected, 'Receipt premise differs: ' + str(path)
    checks[str(path)] = expected

def recheck():
    for mapping in [checks, fresh, products]:
        for path, expected in mapping.items():
            assert sha(path) == expected, 'Changed admitted input: ' + path

def execute(label, command):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
    log = out / (label + '.log')
    started = time.monotonic()
    descendants, peak_rss, cpu_by_pid = set(), 0, {}
    with log.open('w') as stream:
        with subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain) as process:
            def sample():
                nonlocal peak_rss
                rows = [line.split() for line in subprocess.check_output(
                    ['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True, timeout=5).splitlines() if line.strip()]
                owners = {process.pid} | descendants
                while True:
                    found = {int(pid) for pid, parent, rss, cpu in rows if int(parent) in owners}
                    if found <= owners:
                        break
                    owners |= found
                descendants.update(owners - {process.pid})
                peak_rss = max(peak_rss, sum(int(rss) for pid, parent, rss, cpu in rows if int(pid) in owners))
                for pid, parent, rss, cpu in rows:
                    if int(pid) in owners:
                        seconds = sum(float(value) * 60 ** index for index, value in enumerate(reversed(cpu.split(':'))))
                        cpu_by_pid[int(pid)] = max(cpu_by_pid.get(int(pid), 0), seconds)
                return {int(pid) for pid, parent, rss, cpu in rows}
            stop = None
            try:
                while process.poll() is None:
                    sample()
                    if time.monotonic() - started >= 120:
                        stop = 'wall-limit'
                    elif sum(cpu_by_pid.values()) >= 120:
                        stop = 'sampled-owned-cpu-limit'
                    if stop:
                        break
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                survivors = descendants & sample()
                if stop or survivors:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    for pid in survivors:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                process.wait()
                remaining = descendants & sample()
    record = dict(label=label, command=command, exitCode=process.returncode, boundedStop=stop,
        elapsedSeconds=time.monotonic() - started, wallLimitSeconds=120, cpuLimitSecondsPerProcess=120,
        sampledOwnedCPULimitSeconds=120, sampledCPUSeconds=sum(cpu_by_pid.values()),
        peakOwnedProcessResidentSumKiB=peak_rss, ownedDescendantsRemaining=sorted(remaining), logSHA256=sha(log))
    runs.append(record)
    save('runs.json', runs)
    admit(log, record['logSHA256'])
    print(label, process.returncode, round(record['elapsedSeconds'], 3), flush=True)
    assert not remaining, record
    return process.returncode


# Exact archived text comparators preserve old module admission without asserting current equality.
immutable={}
for cell in ['B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01','CS-ANGULAR-PHYSICAL-ARC-PLANE-01','CS-CERT-SPHERECONE-APEX-EMPTY-01']:
    base=root/'Tests/OriginalPublicAcceptanceVerification/Evidence'/cell
    manifest=base/('manifest.json' if cell.startswith('B-') else 'acceptance/manifest.json')
    data=read(manifest);admit(manifest,sha(manifest))
    for name,item in data['files'].items():
        if isinstance(item,str):candidate=base/name;digest=item
        elif 'path' in item:candidate=root/item['path'];digest=item['sha256']
        else:candidate=base/name;digest=item['sha256']
        immutable[digest]=candidate

def retained(name,digest):
    p=Path(name)
    if p.is_file() and sha(p)==digest:admit(p,digest);return
    assert digest in immutable,'Missing exact archived premise: '+name
    snapshot=immutable[digest];admit(snapshot,digest)
    historical[name]=dict(path=str(snapshot),sha256=digest)

cert=root/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance/summary.json'
admit(cert,sha(cert));nominal=read(cert)['cachedCertifiedNominal']
admit(nominal['originalPath'],nominal['currentSHA256'])
admit(root/nominal['cachedBase']['path'],nominal['cachedBase']['sha256'])
text=Path(nominal['originalPath']).read_text();marker='\nextension CertifiedSphereConeIntersectionCurve {'
assert hashlib.sha256((text[:text.rindex(marker)].rstrip('\n')+'\n').encode()).hexdigest()==nominal['cachedBase']['sha256']
for item in nominal['selectedRanges']:admit(root/item['path'],item['sha256'])
save('cached-certified-compatibility.json',nominal)

base=root/'Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01'
summary=read(base/'summary.json');admit(base/'summary.json',sha(base/'summary.json'))
part=next(a for a in summary['accepted'] if a['lane']==args.lane and a.get('scope','current-boundary')=='current-boundary')
# Native source-only first part is intentionally excluded.
if args.lane=='native':part=next(a for a in summary['accepted'] if a['lane']=='native' and a['scope']=='current-boundary')
prior_path=base/part['receipt'];prior=read(prior_path);admit(prior_path,part['receiptSHA256'])
for n,d in prior['checks'].items():retained(n,d)
for n,d in prior['products'].items():admit(n,d)
for module in part['modules']:
    p=base/module['receipt'];q=read(p);admit(p,module['sha256'])
    for n,d in q['freshProduction'].items():admit(n,d)
    for n,d in q['checks'].items():retained(n,d)
    for n,d in q['products'].items():admit(n,d)
old=next(x['command'] for x in prior['runs'] if x['label']=='compile-link-cell')
first=next(i for i,x in enumerate(old) if x.endswith('.swift'))
flags=old[:first]
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
assert ('Embedded' in flags)==(args.lane=='embedded')
assert ('-sanitize=address' in flags)==(args.lane=='asan')
flags[1:1]=['-I',str(out)]
fixture=Path(__file__).with_suffix('.swift')
for p in [fixture,Path(__file__).resolve()]:
    admit(p,sha(p));(out/p.name).write_bytes(p.read_bytes());admit(out/p.name,sha(p))
for p in [Path(flags[0]),Path(flags[0]).with_name('swift-frontend')]:admit(p,sha(p))
source=root/'Sources/CADGeometry/OriginalSurfaceEmbedding'
selected=[source/n for n in ['DefaultOriginalExactNativeSelfContactQuery.swift','OriginalExactNativeSelfContactQuerying.swift','OriginalExactNativeSelfContacts.swift','OriginalExactSelfIdentityCompiler.swift']]
generated=[]
for p in selected:
    fresh[str(p)]=sha(p);destination=out/p.name
    destination.write_text('@testable import NativeDomainAdapters\n'+p.read_text());admit(destination,sha(destination));generated.append(str(destination))
module=flags+['-enable-testing','-emit-module','-emit-library','-static','-module-name','NativeDeclaredWholeEdgeSelf',*generated,
    '-emit-module-path',str(out/'NativeDeclaredWholeEdgeSelf.swiftmodule'),'-o',str(out/'libNativeDeclaredWholeEdgeSelf.a')]
save('compile-self4.json',module)
recheck()
self_directory=out
if args.reuse_self4:
    self_directory=args.reuse_self4.resolve();previous=self_directory/'module-receipt.json';q=read(previous)
    admit(previous,sha(previous));assert q['lane']==args.lane and q['freshProduction']==fresh
    for n,d in q['checks'].items():
        saved=self_directory/Path(n).name
        if saved.is_file() and sha(saved)==d:immutable[d]=saved
        retained(n,d)
    for n,d in q['products'].items():admit(n,d)
    for run in q['runs']:
        assert run['exitCode']==0 and run['boundedStop'] is None
        admit(self_directory/(run['label']+'.log'),run['logSHA256'])
    flags[1:1]=['-I',str(self_directory)]
else:
    code=execute('compile-self4',module)
    if code:save('failure-receipt.json',dict(cell='S-NATIVE-DECLARED-WHOLE-EDGE-01',lane=args.lane,state='self4-compile-failed',success=False,checks=checks,freshProduction=fresh,runs=runs,historicalComparators=historical));raise SystemExit(code)
    for name in ['NativeDeclaredWholeEdgeSelf.swiftmodule','libNativeDeclaredWholeEdgeSelf.a']:products[str(out/name)]=sha(out/name)
    save('module-receipt.json',dict(lane=args.lane,freshProduction=fresh,checks=checks,products=products,runs=runs))
# Reuse the exact previously selected link objects; remove boundary-only fixtures and Kernel adapter.
link=flags+[str(fixture),str(self_directory/'libNativeDeclaredWholeEdgeSelf.a')]+[x for x in old[first:] if not x.endswith('.swift')]
link=[x for x in link if not x.endswith('/libNativeKernelAdapters.a')]
proof=out/('WholeEdge.wasm' if args.lane in ['wasm','embedded'] else 'WholeEdge')
link[link.index('-o')+1]=str(proof)
save('compile-link.json',link)
code=execute('compile-link',link)
if code:save('failure-receipt.json',dict(cell='S-NATIVE-DECLARED-WHOLE-EDGE-01',lane=args.lane,state='fixture-compile-failed',success=False,checks=checks,freshProduction=fresh,products=products,runs=runs,historicalComparators=historical));raise SystemExit(code)
products[str(proof)]=sha(proof)
runtime=[str(proof),args.group]
if args.lane in ['wasm','embedded']:
    old_runtime=next(x['command']for x in prior['runs']if x['label'].startswith('runtime-'))
    runtime=old_runtime[:2]+[str(proof),args.group]
recheck();save('ready-to-run.json',dict(checks=checks,freshProduction=fresh,products=products,runs=runs,runtime=runtime))
code=execute('runtime-'+args.group,runtime);recheck()
save('receipt.json' if code==0 else 'failure-receipt.json',dict(cell='S-NATIVE-DECLARED-WHOLE-EDGE-01',lane=args.lane,
    groups=[args.group],success=code==0,state='complete-oracle-verified' if code==0 else 'observed-runtime-stop',cellComplete=False,
    checks=checks,freshProduction=fresh,products=products,runs=runs,historicalComparators=historical,
    reusedNative32=part['modules'],cachedCertifiedCompatibility=nominal,preAndPostAdmission=True,
    scope='One original once-bound same-owner one-chart fold, closed full D x D; directed whole edge plus authored diagonal exclusion, complete raw/refined iff and every ordinal. Position-only; image2/fiber0 are oracle meaning. Controls and portable acceptance are separate pending work.'))
raise SystemExit(code)
