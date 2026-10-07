# Progress

- [x] ES.C1 Fixed the five scalar contracts against current scalar implementations and Swift 6.4 requirements. `depends:none` `parallel:none`
- [x] ES.C2 Specified the exact scalar contract design without a Numerics dependency. `depends:ES.C1` `parallel:none`
- [x] ES.C3 Typechecked the proposed declarations and generic call paths; numerical behavior was not claimed. `depends:ES.C2` `parallel:none`
- [x] ES.V Reviewed the scoped design and recorded implementation obligations. `depends:ES.C1,ES.C2,ES.C3` `parallel:none`
- [ ] L0.I Implement and verify the five L0 scalar contracts in one isolated worktree and coherent local commit. Existing geometry, relation, and application targets are outside the build scope. `depends:ES.V` `parallel:none`
  - [x] L0.I.1 Fix the source-only L0 boundary, operation domains, error publication and behavioral acceptance matrix in the numeric design. `depends:ES.V` `parallel:none`
  - [x] L0.I.2 Implement primitive protocols, cumulative noncopyable admission and retained rational/algebraic domain operations using the existing numeric algorithms. `depends:L0.I.1` `parallel:none`
  - [x] L0.I.3 Run only L0 success/failure/lifetime/resource/cancellation checks on Native, matching normal WASM and Embedded WASM SDKs; review the stable snapshot and fix concrete findings. `depends:L0.I.2` `parallel:none`
  - [ ] L0.I.4 Check the branch and commit message and commit the complete L0 change and scoped evidence. `depends:L0.I.3` `parallel:none`
- [ ] L0.V Confirm the committed L0 source inventory, isolated build graph and retained execution evidence; report any unverified scope separately. `depends:ES.C1,ES.C2,ES.C3,ES.V,L0.I` `parallel:none`
