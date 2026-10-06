import CADCore

/// Exact original homogeneous curve law bound to one positive native knot span.
package struct OriginalRationalCurvePolynomial: Sendable {
    package let source: BSplineCurve3D
    package let originalCurve: Curve3D
    package let spanIndex: Int
    package let originalTranslation: Double
    package let lowerParameter: ExactRationalCoefficient
    package let upperParameter: ExactRationalCoefficient
    package let homogeneous: [ExactBivariatePolynomial]

    package init<B: RationalAlgebraAdmitting>(source: BSplineCurve3D, spanIndex: Int,
        originalTranslation: Double = 0, tolerance: ModelingTolerance, usage: inout B) throws {
        try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        guard spanIndex >= source.degree, spanIndex < source.controlPoints.count,
              source.knots[spanIndex] < source.knots[spanIndex + 1], originalTranslation.isFinite else {
            throw rationalAlgebraFailure("Original homogeneous curve requires its positive source knot span.")
        }
        let translation = try ExactRationalCoefficient.originalDouble(originalTranslation, usage: &usage)
        if !translation.isZero {
            guard source.isPeriodic else {
                throw rationalAlgebraFailure("An aperiodic original curve cannot carry a periodic native translation.")
            }
            let period = source.knots[source.knots.count - source.degree - 1] - source.knots[source.degree]
            let cycles = try translation.divided(by: .originalDouble(period, usage: &usage), usage: &usage)
            guard cycles.denominator == .one else {
                throw rationalAlgebraFailure("Original native translation must be an exact integer multiple of the source wrapping period.")
            }
        }
        self.source = source; originalCurve = .bSpline(source); self.spanIndex = spanIndex; self.originalTranslation = originalTranslation
        lowerParameter = try ExactRationalCoefficient.originalDouble(source.knots[spanIndex], usage: &usage)
            .adding(translation, usage: &usage)
        upperParameter = try ExactRationalCoefficient.originalDouble(source.knots[spanIndex + 1], usage: &usage)
            .adding(translation, usage: &usage)
        let basis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.knots,
            degree: source.degree, span: spanIndex, alongU: true,
            translation: originalTranslation, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var h = [ExactBivariatePolynomial](repeating: .zero, count: 4)
        for index in (spanIndex - source.degree)...spanIndex {
            try Task.checkCancellation()
            guard let polynomial = basis[index] else {
                throw rationalAlgebraFailure("Original curve basis omitted a selected control coefficient.")
            }
            let weight = try ExactRationalCoefficient.originalDouble(source.weights[index], usage: &usage)
            let point = source.controlPoints[index]
            for axis in 0..<3 {
                let value = try ExactRationalCoefficient.originalDouble(axis == 0 ? point.x : axis == 1 ? point.y : point.z, usage: &usage)
                    .multiplied(by: weight, usage: &usage)
                h[axis] = try h[axis].adding(polynomial.scaled(by: value, usage: &usage), usage: &usage)
            }
            h[3] = try h[3].adding(polynomial.scaled(by: weight, usage: &usage), usage: &usage)
        }
        homogeneous = h
    }

    /// Exact spatial image of an original native law; parameter ownership is unchanged.
    package init<B: RationalAlgebraAdmitting>(source original: Curve3D, spanIndex: Int,
        originalTranslation: Double = 0, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, usage: inout B) throws {
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original homogeneous spatial image exhausted source depth.")
        }
        try usage.consumeExactWork(1)
        let descendant: Curve3D
        let coefficients: [ExactRationalCoefficient]
        var localTolerance = tolerance
        switch original {
        case .bSpline(let native):
            try self.init(source: native, spanIndex: spanIndex, originalTranslation: originalTranslation,
                tolerance: tolerance, usage: &usage)
            return
        case .rigidImage(let image):
            try image.transform.validate(tolerance: tolerance)
            let transform = try AffineTransform3D(basisX: image.transform.basisX,
                basisY: image.transform.basisY, basisZ: image.transform.basisZ,
                translation: image.transform.translation)
            coefficients = try OriginalAffineRationalMatrix.original(transform, usage: &usage)
            descendant = image.source
        case .affineImage(let image):
            coefficients = try OriginalAffineRationalMatrix.original(image.transform, usage: &usage)
            descendant = image.source
        case .originalAffineWord(let image):
            // FIXME(INCOMPLETE_IMPLEMENTATION): The S7 native homogeneous consumer
            // requires an ordered-field carrier for normalized original words. This
            // rational-only producer must not publish rounded algebraic coefficients.
            guard image.operationWord.isRational else {
                throw rationalAlgebraFailure("Normalized original spatial words require ordered-field homogeneous authority.")
            }
            try image.operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
            try RationalAlgebraStorage.retain(12, of: ExactRationalCoefficient.self, usage: &usage)
            var exactColumns: [ExactRationalCoefficient] = []
            exactColumns.reserveCapacity(12)
            for row in 0..<3 {
                for column in 0..<4 {
                    try usage.consumeExactWork(1)
                    exactColumns.append(try column == 3
                        ? image.preparedWord.translationCoefficient(row: row)
                        : image.preparedWord.linearCoefficient(row: row, column: column))
                }
            }
            coefficients = exactColumns
            func work() throws { try usage.consumeExactWork(1) }
            func bytes(_ count: Int) throws { try RationalAlgebraStorage.retainBytes(count, usage: &usage) }
            localTolerance = try withoutActuallyEscaping(bytes) { storage in
                try image.sourceCalculationTolerance(tolerance: tolerance,
                    consumeWork: work, consumeStorage: storage)
            }
            descendant = image.source
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original S7 spatial-image pole
            // consumers currently admit native B-spline descendants only. Other
            // original curve families need their genuine homogeneous producer.
            throw rationalAlgebraFailure("Original spatial image has no native B-spline homogeneous descendant.")
        }
        let native = try Self(source: descendant, spanIndex: spanIndex,
            originalTranslation: originalTranslation, tolerance: localTolerance,
            remainingSourceDepth: remainingSourceDepth - 1, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var transformed: [ExactBivariatePolynomial] = []
        transformed.reserveCapacity(4)
        for row in 0..<3 {
            var value = try native.homogeneous[3].scaled(by: coefficients[row * 4 + 3], usage: &usage)
            for column in 0..<3 {
                try usage.consumeExactWork(1)
                value = try value.adding(native.homogeneous[column].scaled(
                    by: coefficients[row * 4 + column], usage: &usage), usage: &usage)
            }
            transformed.append(value)
        }
        transformed.append(native.homogeneous[3])
        self.init(native: native, original: original, homogeneous: transformed)
    }

    private init(native: Self, original: Curve3D, homogeneous: [ExactBivariatePolynomial]) {
        source = native.source; originalCurve = original; spanIndex = native.spanIndex
        originalTranslation = native.originalTranslation
        lowerParameter = native.lowerParameter; upperParameter = native.upperParameter
        self.homogeneous = homogeneous
    }

    /// All three original axis-cross numerators; a single coordinate is not incidence.
    package func axisIncidenceNumerators<B: RationalAlgebraAdmitting>(origin: Point3D,
        direction: Vector3D, usage: inout B) throws -> [ExactBivariatePolynomial] {
        try origin.validate(); try direction.validate()
        guard direction.x != 0 || direction.y != 0 || direction.z != 0 else {
            throw rationalAlgebraFailure("Original axis incidence requires a nonzero source direction.")
        }
        try RationalAlgebraStorage.retain(6, of: ExactBivariatePolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
        var displacement: [ExactBivariatePolynomial] = []
        var exactDirection: [ExactRationalCoefficient] = []
        displacement.reserveCapacity(3); exactDirection.reserveCapacity(3)
        for axis in 0..<3 {
            displacement.append(try homogeneous[axis].subtracting(homogeneous[3].scaled(by:
                .originalDouble(axis == 0 ? origin.x : axis == 1 ? origin.y : origin.z, usage: &usage), usage: &usage), usage: &usage))
            exactDirection.append(try .originalDouble(axis == 0 ? direction.x : axis == 1 ? direction.y : direction.z, usage: &usage))
        }
        var result: [ExactBivariatePolynomial] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            result.append(try displacement[b].scaled(by: exactDirection[c], usage: &usage)
                .subtracting(displacement[c].scaled(by: exactDirection[b], usage: &usage), usage: &usage))
        }
        return result
    }

    package func planeIncidenceNumerator<B: RationalAlgebraAdmitting>(origin: Point3D,
        normal: Vector3D, usage: inout B) throws -> ExactBivariatePolynomial {
        try origin.validate(); try normal.validate()
        guard normal.x != 0 || normal.y != 0 || normal.z != 0 else {
            throw rationalAlgebraFailure("Original plane incidence requires a nonzero source normal.")
        }
        var result = ExactBivariatePolynomial.zero
        for axis in 0..<3 {
            let displacement = try homogeneous[axis].subtracting(homogeneous[3].scaled(by:
                .originalDouble(axis == 0 ? origin.x : axis == 1 ? origin.y : origin.z, usage: &usage), usage: &usage), usage: &usage)
            result = try result.adding(displacement.scaled(by:
                .originalDouble(axis == 0 ? normal.x : axis == 1 ? normal.y : normal.z, usage: &usage), usage: &usage), usage: &usage)
        }
        return result
    }
}
