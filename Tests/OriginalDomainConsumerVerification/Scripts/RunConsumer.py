import hashlib, json, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parents[3]
cache = Path(sys.argv[1]).resolve()
lane = sys.argv[2] if len(sys.argv)>2 else "native"
wasm = lane in ("wasm","embedded")
configuration = "Debug-webassembly-wasm32" if wasm else "Debug"
subprocess.run([sys.executable,str(Path(__file__).with_name("CheckGeometryCache.py")),str(cache),lane],check=True,timeout=120)
swiftc = Path("/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc")
lower_cache = root / (".build/di-consumer-"+lane)
lower = lower_cache / "out/Products" / configuration
out = lower_cache / "consumer"; out.mkdir(parents=True,exist_ok=True)
if wasm:
 base = Path("/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1")
 desc = base / ("embedded-swift-sdk.json" if lane=="embedded" else "swift-sdk.json")
 data = json.loads(desc.read_text())["targetTriples"]["wasm32-unknown-wasip1"]
 resources = base / data["swiftResourcesPath"]
 toolset = json.loads((base/data["toolsetPaths"][0]).read_text())
 common = [str(swiftc),"-sdk",str(base/data["sdkRootPath"]),"-target","wasm32-unknown-wasip1","-resource-dir",str(resources),"-tools-directory",str(base/toolset["rootPath"]),*toolset["swiftCompiler"]["extraCLIOptions"],"-Xclang-linker","-resource-dir","-Xclang-linker",str(resources/"clang")]
else:
 sdk = subprocess.check_output(["xcrun","--sdk","macosx","--show-sdk-path"],text=True).strip()
 common = [str(swiftc),"-sdk",sdk,"-target","arm64-apple-macos15.0"]
 if lane=="asan": common += ["-sanitize=address","-Xlinker","-dead_strip"]
common += ["-swift-version","6","-package-name","nativeexactrelationverification","-I",str(cache),"-I",str(lower),"-I",str(out)]
commands = []
def run(command):
 commands.append(command)
 subprocess.run(command,check=True,timeout=120)
source = root / "Sources/CADGeometry/OriginalSourceIssuance"
names = ["BSplineCurve3D+OriginalSourceReading.swift","BSplineSurface3D+OriginalSourceReading.swift","OriginalBSplineCurveSnapshotProvider.swift","OriginalBSplineSurfaceSnapshotProvider.swift"]
compiled = [source/n for n in names]
def module(name,files,defines):
 run(common+["-parse-as-library","-emit-module","-emit-library","-static","-module-name",name,*defines,*map(str,files),"-emit-module-path",str(out/(name+".swiftmodule")),"-o",str(out/("lib"+name+".a"))])
module("SourceGeometryAdapters",compiled,["-D","ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION"])
consumer = sorted((root / "Sources/CADGeometry/NativeExactRelations").glob("*.swift"))
module("NativeDomainAdapters",consumer,["-D","NATIVE_DOMAIN_ISOLATED_VERIFICATION"])
fixtures = [root / "Tests/NativeExactRelationVerification/Sources/Fixtures"/n for n in ["NativeExactFixtures.swift","FinalPublicationAdmission.swift"]]
module("ConsumerFixtures",fixtures,["-D","NATIVE_DOMAIN_ISOLATED_VERIFICATION"])
proof = root / "Tests/OriginalDomainConsumerVerification/Sources/Proof/Proof.swift"
objects = []
archives = [out/("lib"+n+".a") for n in ["ConsumerFixtures","NativeDomainAdapters","SourceGeometryAdapters"]]
for products,modules in [(cache,["CADCore","CADGeometry","HashTreeCollections","InternalCollectionsUtilities"]),(lower,["L0","L1","DI0","L2","L3","L4","L5","SourceIssuer","DI"])]:
 for name in modules:
  merged = products/(name+".o")
  if merged.is_file(): objects.append(merged); continue
  files = sorted((products/(name+".objlib")).rglob("*.o"))
  if not files:
   build = products.parents[2]
   files = sorted(build.glob("out/Intermediates.noindex/*/"+configuration+"/"+name+"-t.build/Objects-normal/wasm32/*.o"))
  if not files: raise RuntimeError("Missing object inventory: "+name)
  objects += files
  archive = out/("libCache"+name+".a"); archive.unlink(missing_ok=True)
  run([str(swiftc.parent/"llvm-ar"),"-rcs",str(archive),*map(str,files)])
  archives.append(archive)
extras = []
if wasm: extras += ["-Xlinker","-z","-Xlinker","stack-size=67108864"]
if lane=="embedded":
 receipt=json.loads((root/"Tests/NativeExactRelationVerification/PublicReviewFixEvidence/receipt.json").read_text())
 unicode=Path(receipt["unicode_library"]["path"])
 assert hashlib.sha256(unicode.read_bytes()).hexdigest()==receipt["unicode_library"]["sha256"]
 extras.append(str(unicode))
artifact = out/("DomainConsumerProof.wasm" if wasm else "DomainConsumerProof")
# Objects already archived must not be linked a second time.
merged_objects = [p for p in objects if p.parent in (cache,lower)]
run(common+["-parse-as-library",str(proof),*map(str,archives),*map(str,merged_objects),*extras,"-o",str(artifact)])
if wasm: run(["/usr/local/bin/node",str(root/"Tests/OriginalDomainIdentityVerification/Scripts/RunWASI.mjs"),str(artifact)])
else: run([str(artifact)])
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
compiled += consumer + fixtures + [proof]
inputs = {}
for name in ["L0","L1","DI0","L2","L3","L4","L5","SourceIssuer","DI"]:
 lists = lower_cache.glob("out/Intermediates.noindex/*/"+configuration+"/"+name+"-t.build/Objects-normal/"+("wasm32" if wasm else "arm64")+"/*.SwiftFileList")
 for listing in lists:
  for line in listing.read_text().splitlines():
   p=Path(line.strip().strip('"')).resolve()
   inputs[str(p.relative_to(root))]=digest(p)
for p in compiled: inputs[str(p.relative_to(root))]=digest(p)
manifest={"lane":lane,"compiled_sources":inputs,"commands":commands,"products":{str(p):digest(p) for p in objects+archives+[artifact]},"cache_premises":json.loads((lower_cache/"cache-premises.json").read_text()),"compiler":subprocess.check_output([str(swiftc),"--version"],text=True).strip(),"scope":"Actual public Native parameter consumers and source/domain proof composition; cached unchanged geometry DTOs. No full module build."}
(out/"receipt.json").write_text(json.dumps(manifest,indent=2)+"\n")
