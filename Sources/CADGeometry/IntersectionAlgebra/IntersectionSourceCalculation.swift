/// Observes a source calculation on the original admission, without a forwarding handle.
func intersectionSourceCalculation<A:ExactScalarAdmission & ~Copyable,Result>(
    originalParameterDepth:Int,originalCoefficientDepth:Int,
    inheritedParameterDepth:Int,inheritedCoefficientDepth:Int,
    maximumDepth:Int,maximumCoefficientDepth:Int,usage:inout A,
    _ body:(inout A)throws->Result) throws -> (value:Result,parameterDepth:Int,coefficientDepth:Int) {
    try usage.withProofScope(original:try .init(value:originalParameterDepth,coefficient:originalCoefficientDepth),
        inherited:try .init(value:inheritedParameterDepth,coefficient:inheritedCoefficientDepth),
        maximum:try .init(value:maximumDepth,coefficient:maximumCoefficientDepth)) { a in
        let value=try body(&a),depth=try a.depth
        return (value,depth.value,depth.coefficient)
    }
}
