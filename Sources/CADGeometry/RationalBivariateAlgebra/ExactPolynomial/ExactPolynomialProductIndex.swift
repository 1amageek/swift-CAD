#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// One translated, descending input-row stream; no coefficient or powers copy.
struct ExactPolynomialProductIndex {
    let row: Int
    let column: Int
}
