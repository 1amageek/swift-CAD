# M1 Family Query Verification

The actual compiler SwiftFileList inventories bind the immutable input hashes in
receipt.json. Native and ASAN each execute 19 behavioral tests. Ordinary WASM and
Embedded WASM compile/link and execute the same synchronous portable proof body,
including FamilyQueryFixtures through protocol requirements. Native async
reader/task cancellation remains a Native test; WASM proof does not claim real
threading or async execution. Swift 6.4.0 release and matching SDKs are fixed.
Every command uses the existing outer timeout, at most 120 seconds, with separate
scratch paths. Native witness tests retain signed arbitrary-size cycles, both
seam sides, zero rank, poles, explicit malformed inputs, injected source errors,
foreign period-owner refusal, work exhaustion and terminal cancellation. Existing
DI0-DI3 regressions execute unchanged. One scoped implementation review found
missing injected-owner checks; the guards and concrete refusal fixture were added
and confirmed on this final snapshot. No scoped finding remains.

All production state in this change is immutable Sendable ownership. Admission
and temporary arrays are invocation-local on every target; there is no conditional
storage/isolation/Sendable branch, pointer escape or shared mutable state. Existing
public defaults delegate through typed generic composition ports. M2/M3 and full
DI/7/87 completion remain open. This receipt deliberately records actual compiled
files and excludes concurrently developed M2/M3 files not in this snapshot.


## Concurrent main composition

Main advanced to69e0fcb4 with independently verified source/coordinate handoff
while M1 was closing. Mergeae807ef9 preserves both changes. The independent
integration target executes all19 Native tests on that composed snapshot.
Its isolated L2 target excludes the five new source-coordinate-transfer files,
whose same-module internal access is verified by the owning source-handoff proof;
these are not used by M1. No production source visibility is changed. The fresh
integration compiler inventory is bound by main-integration.json. Existing M1
ordinary/Embedded runtime evidence and the owning main handoff evidence remain
separate; this Native composition does not claim new asynchronous WASM behavior.
