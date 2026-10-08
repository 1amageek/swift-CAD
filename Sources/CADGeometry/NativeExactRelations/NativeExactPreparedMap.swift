/// Preparation owns source provenance and the checked L5 map together.
struct NativeExactPreparedMap: Sendable {
    let map: ExactParametricMap<ExactRationalScalarDomain>
    let sourceLaw: NativeExactIssuedSourceLaw
}
