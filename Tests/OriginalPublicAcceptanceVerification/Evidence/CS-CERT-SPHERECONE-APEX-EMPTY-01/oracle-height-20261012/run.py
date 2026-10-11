import hashlib,json,os,resource,signal,subprocess,time
from pathlib import Path
out=Path(__file__).resolve().parent
swift=Path("/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc")
def limit():
 resource.setrlimit(resource.RLIMIT_CPU,(120,120))
sdk=subprocess.check_output(["xcrun","--sdk","macosx","--show-sdk-path"],text=True).strip()
runs=[]
commands=[("compiler",[str(swift),"--version"]),("compile",[str(swift),"-sdk",sdk,"-target","arm64-apple-macos15.0","-swift-version","6","-Onone","-package-name","apexheightscalarprobe","-parse-as-library",str(out/"OutwardScalarInterval.swift"),str(out/"ApexHeightScalarProbe.swift"),"-o",str(out/"ApexHeightScalarProbe")]),("scalar-calculation",[str(out/"ApexHeightScalarProbe")])]
for name,cmd in commands:
 start=time.monotonic()
 with (out/(name+".log")).open("w") as log:
  p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=limit)
  try: code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:
   os.killpg(p.pid,signal.SIGKILL);p.wait();raise
 runs.append(dict(name=name,command=cmd,exitCode=code,elapsedSeconds=time.monotonic()-start,wallBoundSeconds=120,cpuBoundSeconds=120))
 if code: raise RuntimeError(name)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
(out/"calculation-metadata.json").write_text(json.dumps(dict(scope="Standalone scalar coefficient calculation, not geometry runtime acceptance",runs=runs,files={p.name:sha(p) for p in out.iterdir() if p.is_file() and p.name!="calculation-metadata.json"}),indent=2)+"\n")
print((out/"scalar-calculation.log").read_text())
print(json.dumps(runs))
