import CADCore

/// Consumes the shared original endpoint relation for Coons corner admission.
struct OriginalCoonsCornerIncidence {
    func proves<B: RationalAlgebraAdmitting>(first: OriginalCurveRootSpan3D, firstAtEnd: Bool,
        second: OriginalCurveRootSpan3D, secondAtEnd: Bool, usage: inout B) throws -> Bool {
        try OriginalCurveTraversalEndpointRelation().proves(first: first, firstAtEnd: firstAtEnd,
            second: second, secondAtEnd: secondAtEnd, usage: &usage)
    }
}
