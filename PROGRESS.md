# Progress

- [x] ES.C1 Fixed the five scalar contracts against current scalar implementations and Swift 6.4 requirements. `commit:e0722edb` `depends:none` `parallel:none`
- [x] ES.C2 Fixed the exact scalar contract design without a Numerics dependency. `commit:e0722edb` `depends:ES.C1` `parallel:none`
- [x] ES.C3 Typechecked the primitive declarations and generic call paths. `commit:e0722edb` `depends:ES.C2` `parallel:none`
- [x] ES.V Reviewed the scoped design and recorded implementation obligations. `commit:e0722edb` `depends:ES.C1,ES.C2,ES.C3` `parallel:none`
- [x] L01.RD Fixed the native-first L0/L1 redesign in their authoritative DESIGN.md files: standard Swift ownership/cancellation/sizing, one caller ledger, shared checked payload sizing, legacy unit conversion boundary and certified zero shortcut; implementation and affected behavioral verification remain pending. `depends:ES.V` `parallel:none`
- [ ] L0.I Reopened by review R1: univariateDivision and quotientAndRemainder admit one UInt32 word before constructing a 40-byte monomial payload; public cubic-root sign execution reproduced the undercharge. Implement shared native payload sizing and correct local admission before verifying the affected scalar path. Preserve existing arithmetic, lifetime and portability evidence. `commit:e0722edb` `depends:ES.V,L01.RD` `parallel:none`
- [ ] L0.V Reconfirm L0 completion after R1; unchanged source inventories, hashes and unaffected runtime evidence remain reusable. Higher consumers and main integration remain outside scope. `depends:ES.C1,ES.C2,ES.C3,ES.V,L0.I` `parallel:none`

- [ ] L1.1 Reopened by review R2: multiplying a 5,000-term left operand by zero traverses the outer loop while publishing zero with work 3 and storage 0. Add a certified zero shortcut after existing owner/depth checks, or admit the traversal, and verify this resource/cancellation boundary. Preserve unaffected primitive evidence. `commit:4358e99c` `depends:L0.I,L0.V` `parallel:none`
- [ ] L1.2 Reconfirm affected algebraic-coefficient resource paths after R1 and R2; division, iterative multivariate GCD, square-free and resultant arithmetic evidence remains reusable where assumptions do not change. `commit:66e6c8fd` `depends:L1.1` `parallel:none`
- [ ] L1.V Close R1/R2 and record scoped cumulative verification of the repaired snapshot; reuse unchanged Native/ASAN/WASM/Embedded evidence and source inventories. Earlier portability evidence is in commit 9c4a203e. `depends:ES.C1,ES.C2,ES.C3,ES.V,L01.RD,L0.I,L0.V,L1.1,L1.2` `parallel:none`
