#!/usr/bin/env python3
"""Build full portable production modules with a build-only 300-second guard."""
import os,pathlib,signal,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[3]
lane=sys.argv[1]
if lane not in ['wasm','embedded']:raise ValueError('Unknown portable lane')
sdk='swift-6.4.0-RELEASE_wasm'+('-embedded' if lane=='embedded' else '')
command=['/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift','build',
 '--package-path',str(root/'Tests/NativeExactRelationVerification'),'--build-path',str(root/'.build'/('native-exact-'+lane)),
 '--swift-sdk',sdk,'-j','4','-Xswiftc','-num-threads','-Xswiftc','8']
if lane=='embedded':command += ['-Xlinker','/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a']
print('BUILD_ONLY_TIMEOUT=300s',flush=True)
print('COMMAND='+repr(command),flush=True)
process=subprocess.Popen(command,cwd=root,start_new_session=True)
def stop(sig):
 try:os.killpg(process.pid,sig)
 except ProcessLookupError:pass
try:code=process.wait(timeout=300)
except (subprocess.TimeoutExpired,KeyboardInterrupt) as error:
 print('Build guard stopped: '+str(error),file=sys.stderr)
 stop(signal.SIGTERM)
 try:process.wait(timeout=2)
 except subprocess.TimeoutExpired:pass
 stop(signal.SIGKILL);process.wait();sys.exit(124)
else:
 stop(signal.SIGTERM);stop(signal.SIGKILL);sys.exit(code if code>=0 else 128-code)
