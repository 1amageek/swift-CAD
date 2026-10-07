#!/usr/bin/env python3
"""Bound the indivisible production WMO build; runtime tests use the 120s guard."""
import os,pathlib,signal,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[3]
command=['/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift','build',
 '--package-path',str(root/'Tests/NativeExactRelationVerification'),'--build-path',str(root/'.build/native-exact-embedded'),
 '--swift-sdk','swift-6.4.0-RELEASE_wasm-embedded','--target','CADGeometry','-j','4','-Xswiftc','-num-threads','-Xswiftc','8']
print('BUILD_ONLY_TIMEOUT=300s',flush=True)
print('COMMAND='+repr(command),flush=True)
process=subprocess.Popen(command,cwd=root,start_new_session=True)
def stop(sig):
 try:os.killpg(process.pid,sig)
 except ProcessLookupError:pass
try:code=process.wait(timeout=300)
except (subprocess.TimeoutExpired,KeyboardInterrupt) as error:
 print('Bounded WMO build stopped: '+str(error),file=sys.stderr)
 stop(signal.SIGTERM)
 try:process.wait(timeout=2)
 except subprocess.TimeoutExpired:pass
 stop(signal.SIGKILL);process.wait();sys.exit(124)
else:
 stop(signal.SIGTERM);stop(signal.SIGKILL);sys.exit(code if code>=0 else 128-code)
