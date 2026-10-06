import CADCore

/// Admits original endpoint equality without tolerance-based corner snapping.
package struct OriginalCurveTraversalEndpointRelation {
    package func proves<B: RationalAlgebraAdmitting>(first: OriginalCurveRootSpan3D, firstAtEnd: Bool,
        second: OriginalCurveRootSpan3D, secondAtEnd: Bool,
        remainingSourceDepth: Int = Int.max, maximumSubdivisionDepth: Int = Int.max,
        storageByteStride: Int = MemoryLayout<UInt32>.stride, usage: inout B,
        maximumAlgebraicDepth: Int? = nil) throws -> Bool {
        try proves(first: first, firstAtEnd: firstAtEnd,
            firstRemainingSourceDepth: min(remainingSourceDepth, first.remainingSourceDepth),
            second: second, secondAtEnd: secondAtEnd,
            secondRemainingSourceDepth: min(remainingSourceDepth, second.remainingSourceDepth),
            maximumSubdivisionDepth: maximumSubdivisionDepth, storageByteStride: storageByteStride, usage: &usage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    private func proves<B: RationalAlgebraAdmitting>(first: OriginalCurveRootSpan3D,
        firstAtEnd: Bool, firstRemainingSourceDepth: Int,
        second: OriginalCurveRootSpan3D, secondAtEnd: Bool,
        secondRemainingSourceDepth: Int, maximumSubdivisionDepth: Int, storageByteStride: Int, usage: inout B, maximumAlgebraicDepth: Int?) throws -> Bool {
        guard first.certificationTolerance == second.certificationTolerance,
            firstRemainingSourceDepth >= 0, secondRemainingSourceDepth >= 0,
            maximumSubdivisionDepth >= 0, maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original endpoint relation requires matching source tolerance and nonnegative caller capabilities.")
        }
        try usage.consumeExactWork(1)
        let a = firstAtEnd ? first.end : first.start
        let b = secondAtEnd ? second.end : second.start
        if case .authored(let parameter) = a,
           let retained = try OriginalCurveEndpointPositionRelation.retainedEndpoint(
               of: first.source, at: parameter,
               remainingSourceDepth: firstRemainingSourceDepth, usage: &usage) {
            return try proves(first: retained.boundary, firstAtEnd: retained.atEnd,
                firstRemainingSourceDepth: min(firstRemainingSourceDepth - 1,
                    retained.boundary.remainingSourceDepth),
                second: second, secondAtEnd: secondAtEnd,
                secondRemainingSourceDepth: secondRemainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, storageByteStride: storageByteStride, usage: &usage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        if case .authored(let parameter) = b,
           let retained = try OriginalCurveEndpointPositionRelation.retainedEndpoint(
               of: second.source, at: parameter,
               remainingSourceDepth: secondRemainingSourceDepth, usage: &usage) {
            return try proves(first: first, firstAtEnd: firstAtEnd,
                firstRemainingSourceDepth: firstRemainingSourceDepth,
                second: retained.boundary, secondAtEnd: retained.atEnd,
                secondRemainingSourceDepth: min(secondRemainingSourceDepth - 1,
                    retained.boundary.remainingSourceDepth),
                maximumSubdivisionDepth: maximumSubdivisionDepth, storageByteStride: storageByteStride, usage: &usage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        if case .authored(let ap) = a, case .authored(let bp) = b {
            if try OriginalConstructionChartEndpointRelation.matches(first: first.source, at: ap,
                second: second.source, at: bp,
                remainingSourceDepth: min(firstRemainingSourceDepth, secondRemainingSourceDepth),
                tolerance: first.certificationTolerance, usage: &usage) { return true }
            return try OriginalCurveEndpointPositionRelation.prove(first: first.source, at: ap,
                second: second.source, at: bp, firstNativeSpanIndex: first.nativeSpanIndex,
                secondNativeSpanIndex: second.nativeSpanIndex,
                remainingSourceDepth: min(firstRemainingSourceDepth, secondRemainingSourceDepth),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, first.maximumSubdivisionDepth, second.maximumSubdivisionDepth),
                tolerance: first.certificationTolerance, storageByteStride: storageByteStride, usage: &usage,
                maximumAlgebraicDepth: maximumAlgebraicDepth.map { min($0, first.maximumAlgebraicDepth, second.maximumAlgebraicDepth) }) != nil
        }
        func algebraicEqualsRational(_ algebraicSpan: OriginalCurveRootSpan3D,
            _ endpoint: OriginalCurveRootEndpoint, _ rationalSpan: OriginalCurveRootSpan3D,
            _ rationalEndpoint: OriginalCurveRootEndpoint, rationalRemainingSourceDepth: Int,
            usage: inout B) throws -> Bool? {
            guard case .algebraic(let root) = endpoint,
                  case .authored(let station) = rationalEndpoint else { return nil }
            let rational = try OriginalCurveEndpointPositionRelation.coordinates(rationalSpan.source,
                at: .originalDouble(station, usage: &usage), owningSpanIndex: rationalSpan.nativeSpanIndex,
                remainingSourceDepth: rationalRemainingSourceDepth,
                tolerance: rationalSpan.certificationTolerance, storageByteStride: storageByteStride, usage: &usage)
            let original = try OriginalRationalCurvePolynomial(source: root.source,
                spanIndex: root.spanIndex, tolerance: algebraicSpan.certificationTolerance, usage: &usage)
            for axis in 0..<3 {
                let residual = try original.homogeneous[axis].subtracting(
                    original.homogeneous[3].scaled(by: rational[axis], usage: &usage), usage: &usage)
                if try root.sign(of: residual, maximumSubdivisionDepth: min(maximumAlgebraicDepth ?? algebraicSpan.maximumAlgebraicDepth, algebraicSpan.maximumAlgebraicDepth),
                    usage: &usage) != .zero { return false }
            }
            return true
        }
        if let admitted = try algebraicEqualsRational(first, a, second, b,
            rationalRemainingSourceDepth: secondRemainingSourceDepth, usage: &usage) { return admitted }
        if let admitted = try algebraicEqualsRational(second, b, first, a,
            rationalRemainingSourceDepth: firstRemainingSourceDepth, usage: &usage) { return admitted }
        if case .algebraic(let firstRoot) = a, case .algebraic(let secondRoot) = b {
            let firstLaw = try OriginalRationalCurvePolynomial(source: firstRoot.source,
                spanIndex: firstRoot.spanIndex, tolerance: first.certificationTolerance, usage: &usage)
            let secondLaw = try OriginalRationalCurvePolynomial(source: secondRoot.source,
                spanIndex: secondRoot.spanIndex, tolerance: second.certificationTolerance, usage: &usage)
            let comparisonDepth = min(maximumAlgebraicDepth ?? min(first.maximumAlgebraicDepth, second.maximumAlgebraicDepth), first.maximumAlgebraicDepth, second.maximumAlgebraicDepth)
            for axis in 0..<3 {
                let firstCoordinate = try OriginalRationalCoordinateRoot.coordinate(
                    numerator: firstLaw.homogeneous[axis], denominator: firstLaw.homogeneous[3],
                    at: firstRoot.retainedRootEndpoint, maximumDepth: min(maximumAlgebraicDepth ?? first.maximumAlgebraicDepth, first.maximumAlgebraicDepth), usage: &usage)
                let secondCoordinate = try OriginalRationalCoordinateRoot.coordinate(
                    numerator: secondLaw.homogeneous[axis], denominator: secondLaw.homogeneous[3],
                    at: secondRoot.retainedRootEndpoint, maximumDepth: min(maximumAlgebraicDepth ?? second.maximumAlgebraicDepth, second.maximumAlgebraicDepth), usage: &usage)
                guard try firstCoordinate.hasSameValue(as: secondCoordinate, maximumDepth: comparisonDepth, usage: &usage) else { return false }
            }
            return true
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original endpoint comparison reaches
        // angular and other nonrational endpoint laws here. Exact
        // original endpoint incidence must be issued before those corners can
        // publish an equality receipt; midpoint distance cannot authorize them.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: first.certificationTolerance,
            message: "Original traversal requires exact endpoint incidence for these endpoint laws.")
    }
}
