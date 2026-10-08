import CADCore

/// Numerical isolated representatives are subordinate to the retained complete L5/L6 authority.
struct NativeExactSurfaceSurfacePublisher {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Scalar = ExactAlgebraicScalar<Base>
    typealias Polynomial = ExactPolynomial<Field>

    static func publish<A: ExactScalarAdmission & ~Copyable>(
        _ result: borrowing NativeExactGeometricRelation,
        options: SurfaceSurfaceIntersectionOptions, using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> SurfaceSurfaceIntersectionResult {
        do {
            try admission.checkpoint()
            let binding = result.parameterRelation
            guard case .surfaceSurface(let first, let second, let firstBox, let secondBox) = binding.source else {
                throw ExactGeometricRelationFailure.invalidSourceBinding
            }
            try options.validate(tolerance: binding.tolerance)
            let relation = binding.relation, geometry = result.geometry
            let count = relation.components.count
            guard count <= options.maximumSeedCount else {
                throw failure(.resourceLimitExceeded,
                    "Exact SSI connected source components exceed the component limit.", binding.tolerance)
            }
            try retain(count, of: Int.self, using: &admission)
            var dimensions = Array(repeating: 0, count: count)
            for record in geometry.strata {
                try admission.consumeWork(1)
                guard record.sourceComponentOrdinal >= 0, record.sourceComponentOrdinal < count else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
                dimensions[record.sourceComponentOrdinal] = max(
                    dimensions[record.sourceComponentOrdinal], record.parameterDimension)
            }
            var isolatedCount = 0
            for record in geometry.strata where dimensions[record.sourceComponentOrdinal] == 0 {
                try admission.consumeWork(1)
                guard record.imageDimension == 0, record.fiberDimension == 0 else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
                let (next, overflow) = isolatedCount.addingReportingOverflow(1)
                guard !overflow else { throw ExactScalarFailure.countOverflow }
                isolatedCount = next
            }
            guard isolatedCount <= options.maximumRootAttempts else {
                throw failure(.resourceLimitExceeded, "Exact SSI isolated representatives exceed the result limit.", binding.tolerance)
            }
            try retain(isolatedCount, of: SurfaceSurfaceIntersection.self, using: &admission)
            var intersections: [SurfaceSurfaceIntersection] = []; intersections.reserveCapacity(isolatedCount)
            let cells = try ExactRealCellDomain<Base>(retaining: relation.original.predicate.source, using: &admission)
            for record in geometry.strata where dimensions[record.sourceComponentOrdinal] == 0 {
                try admission.consumeWork(1)
                let handle = try geometry.identifier(at: record.ordinal)
                let cell = try geometry.sourceCell(of: handle)
                guard cell.dimension == 0 else { throw ExactGeometricRelationFailure.invalidCoverage }
                let sample = try cells.sample(of: cell, in: relation.selection.partition, using: &admission)
                let numerical = try publishPoint(sample: sample, source: relation.original,
                    coefficientField: binding.coefficientField,
                    first: first, second: second, firstBox: firstBox, secondBox: secondBox,
                    options: options, tolerance: binding.tolerance, using: &admission)
                // Distinct source tuples remain distinct; numerical XYZ never establishes identity.
                intersections.append(.point(numerical))
            }
            try retain(1, of: SurfaceSurfaceIntersectionResult.self, using: &admission)
            let publication = SurfaceSurfaceIntersectionResult(intersections: intersections,
                originalExactGeometricRelation: copy result)
            try admission.checkpoint()
            return publication
        } catch { throw .preserving(error) }
    }

    private static func publishPoint<A: ExactScalarAdmission & ~Copyable>(
        sample: ExactRealCellSample<Base>, source: ExactParametricRelationSource<Base>, coefficientField: Field,
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using admission: inout A
    ) throws -> SurfaceSurfaceIntersectionPoint {
        guard sample.coordinates.count == 4 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let field = sample.field
        let polynomials = try ExactPolynomialDomain(field: field, variableCount: 2, using: &admission)
        guard source.first.original.polynomials.count == 4, source.second.original.polynomials.count == 4 else {
            throw ExactGeometricRelationFailure.invalidSourceBinding
        }
        try retain(4, of: Polynomial.self, using: &admission)
        var firstLaws: [Polynomial] = []; firstLaws.reserveCapacity(4)
        for law in source.first.original.polynomials {
            firstLaws.append(try polynomials.importing(law, using: &admission))
        }
        let numericalFirstLaws = source.first.original.polynomials
        let numericalSecondLaws = source.second.original.polynomials
        let numericalFirstDomain = try ExactPolynomialDomain(retaining: numericalFirstLaws[0], using: &admission)
        let numericalSecondDomain = try ExactPolynomialDomain(retaining: numericalSecondLaws[0], using: &admission)
        try retain(2, of: Scalar.self, using: &admission)
        let firstUV = [sample.coordinates[0], sample.coordinates[1]]
        let exactXYZ = try position(firstLaws, at: firstUV, polynomials: polynomials, field: field, using: &admission)
        try retain(7, of: Scalar.self, using: &admission)
        var originals = sample.coordinates; originals.reserveCapacity(7); originals.append(contentsOf: exactXYZ)
        let firstU = try selected(first.uKnots[first.uDegree], first.uKnots[first.uControlPointCount], firstBox?.u)
        let firstV = try selected(first.vKnots[first.vDegree], first.vKnots[first.vControlPointCount], firstBox?.v)
        let secondU = try selected(second.uKnots[second.uDegree], second.uKnots[second.uControlPointCount], secondBox?.u)
        let secondV = try selected(second.vKnots[second.vDegree], second.vKnots[second.vControlPointCount], secondBox?.v)
        try retain(11, of: ScalarInterval.self, using: &admission)
        var bounds = [firstU, firstV, secondU, secondV]
        bounds.reserveCapacity(7)
        for axis in 0..<3 {
            var lower = Double.infinity, upper = -Double.infinity
            for row in first.controlPoints {
                for point in row {
                    try admission.consumeWork(1)
                    let value = axis == 0 ? point.x : axis == 1 ? point.y : point.z
                    lower = min(lower, value); upper = max(upper, value)
                }
            }
            // Positive original weights and the closed nonnegative B-spline basis certify this hull.
            bounds.append(try .init(lower: lower, upper: upper))
        }
        for index in bounds.indices {
            let lower = try field.binary64(exactly: bounds[index].lower, using: &admission)
            let upper = try field.binary64(exactly: bounds[index].upper, using: &admission)
            let lowerOrder = try field.compare(originals[index], lower, using: &admission)
            let upperOrder = try field.compare(originals[index], upper, using: &admission)
            guard lowerOrder != .less, upperOrder != .greater else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
            // Source equality to a closed endpoint retains that exact dyadic value;
            // bisection must not replace it with an interior approximation.
            if lowerOrder == .equal {
                bounds[index] = try .init(lower: bounds[index].lower, upper: bounds[index].lower)
            } else if upperOrder == .equal {
                bounds[index] = try .init(lower: bounds[index].upper, upper: bounds[index].upper)
            }
        }
        let distance = try coefficientField.binary64(exactly: tolerance.distance, using: &admission)
        let squaredLimit = try coefficientField.multiplying(distance, distance, using: &admission)
        let originalParameterLimit = try field.importing(distance, using: &admission)
        let negativeParameterLimit = try field.negated(originalParameterLimit, using: &admission)
        let halfDistance = try coefficientField.dividing(distance, coefficientField.integer(2, using: &admission), using: &admission)
        try retain(7, of: Double.self, using: &admission)
        var representatives = Array(repeating: 0.0, count: 7)
        for iteration in 0..<options.maximumIterations {
            try admission.consumeWork(1)
            for index in bounds.indices {
                let lower = bounds[index].lower, upper = bounds[index].upper
                let middle = lower == upper ? lower : lower * 0.5 + upper * 0.5
                guard middle.isFinite, middle >= lower, middle <= upper else {
                    throw failure(.intersectionFailure, "An exact SSI coordinate has no finite contained representative.", tolerance)
                }
                let candidate = try field.binary64(exactly: middle, using: &admission)
                switch try field.compare(originals[index], candidate, using: &admission) {
                case .equal: bounds[index] = try .init(lower: middle, upper: middle)
                case .less: bounds[index] = try .init(lower: lower, upper: middle)
                case .greater: bounds[index] = try .init(lower: middle, upper: upper)
                }
                representatives[index] = middle
            }
            try admission.consumeWork(bounds.count)
            guard bounds.allSatisfy({ $0.upper - $0.lower <= tolerance.distance }) else { continue }
            try retain(4, of: Scalar.self, using: &admission)
            // Dyadic numerical candidates belong to the original coefficient field. Their
            // residual arithmetic does not inherit the selected algebraic root tower.
            let firstParameters = [try coefficientField.binary64(exactly: representatives[0], using: &admission),
                try coefficientField.binary64(exactly: representatives[1], using: &admission)]
            let secondParameters = [try coefficientField.binary64(exactly: representatives[2], using: &admission),
                try coefficientField.binary64(exactly: representatives[3], using: &admission)]
            let firstPosition = try position(numericalFirstLaws, at: firstParameters,
                polynomials: numericalFirstDomain, field: coefficientField, using: &admission)
            let secondPosition = try position(numericalSecondLaws, at: secondParameters,
                polynomials: numericalSecondDomain, field: coefficientField, using: &admission)
            try retain(3, of: Scalar.self, using: &admission)
            let point = [try coefficientField.binary64(exactly: representatives[4], using: &admission),
                try coefficientField.binary64(exactly: representatives[5], using: &admission),
                try coefficientField.binary64(exactly: representatives[6], using: &admission)]
            try retain(4, of: Scalar.self, using: &admission)
            let originalFirstParameters = try [field.importing(firstParameters[0], using: &admission),
                field.importing(firstParameters[1], using: &admission)]
            let originalSecondParameters = try [field.importing(secondParameters[0], using: &admission),
                field.importing(secondParameters[1], using: &admission)]
            // Residual and point error are exact inequalities, independent of numerical existence tests.
            if try within(firstPosition, secondPosition, squaredLimit: squaredLimit, field: coefficientField, using: &admission),
               try within(firstPosition, point, squaredLimit: squaredLimit, field: coefficientField, using: &admission),
               try within(secondPosition, point, squaredLimit: squaredLimit, field: coefficientField, using: &admission),
               try positionBoundsWithin(point, bounds: bounds, absoluteLimit: halfDistance,
                   field: coefficientField, using: &admission),
               try parametersWithin(sample.coordinates, first: originalFirstParameters, second: originalSecondParameters,
                   absoluteLimit: originalParameterLimit, negativeLimit: negativeParameterLimit,
                   field: field, using: &admission) {
                let numerical = Point3D(x: representatives[4], y: representatives[5], z: representatives[6])
                return try .init(point: numerical,
                    firstSurfaceParameter: .init(u: representatives[0], v: representatives[1], point: numerical,
                        residual: tolerance.distance, iterations: iteration + 1),
                    secondSurfaceParameter: .init(u: representatives[2], v: representatives[3], point: numerical,
                        residual: tolerance.distance, iterations: iteration + 1),
                    residual: tolerance.distance, tolerance: tolerance)
            }
        }
        throw failure(.resourceLimitExceeded, "Exact SSI numerical publication exhausted refinement iterations.", tolerance)
    }

    private static func position<A: ExactScalarAdmission & ~Copyable>(
        _ laws: [Polynomial], at coordinates: [Scalar], polynomials: ExactPolynomialDomain<Field>,
        field: Field, using admission: inout A
    ) throws -> [Scalar] {
        guard laws.count == 4 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let weight = try polynomials.evaluated(laws[3], at: coordinates, using: &admission)
        try admission.admitDepth(value: weight.depth.value, coefficient: weight.depth.coefficient)
        guard try field.sign(of: weight.value, using: &admission) == .positive else {
            throw ExactGeometricRelationFailure.invalidCoverage
        }
        try retain(3, of: Scalar.self, using: &admission)
        var result: [Scalar] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            let position = try polynomials.evaluated(laws[axis], at: coordinates, using: &admission)
            try admission.admitDepth(value: position.depth.value, coefficient: position.depth.coefficient)
            result.append(try field.dividing(position.value, weight.value, using: &admission))
        }
        return result
    }

    private static func within<A: ExactScalarAdmission & ~Copyable>(
        _ first: [Scalar], _ second: [Scalar], squaredLimit: Scalar,
        field: Field, using admission: inout A
    ) throws -> Bool {
        var squared = try field.integer(0, using: &admission)
        for axis in 0..<3 {
            let difference = try field.subtracting(first[axis], second[axis], using: &admission)
            squared = try field.adding(squared, field.multiplying(difference, difference, using: &admission), using: &admission)
        }
        return try field.compare(squared, squaredLimit, using: &admission) != .greater
    }

    private static func parametersWithin<A: ExactScalarAdmission & ~Copyable>(
        _ originals: [Scalar], first: [Scalar], second: [Scalar], absoluteLimit: Scalar, negativeLimit: Scalar,
        field: Field, using admission: inout A
    ) throws -> Bool {
        for axis in 0..<4 {
            let value = axis < 2 ? first[axis] : second[axis - 2]
            let difference = try field.subtracting(originals[axis], value, using: &admission)
            if try field.compare(difference, absoluteLimit, using: &admission) == .greater
                || field.compare(difference, negativeLimit, using: &admission) == .less { return false }
        }
        return true
    }

    private static func positionBoundsWithin<A: ExactScalarAdmission & ~Copyable>(
        _ candidate: [Scalar], bounds: [ScalarInterval], absoluteLimit: Scalar,
        field: Field, using admission: inout A
    ) throws -> Bool {
        // Initial exact inclusion and each exact bisection comparison retain the
        // authored XYZ inside these bounds. Exact dyadic endpoint errors at most
        // distance/2 imply Euclidean authored-point error <= sqrt(3)*distance/2
        // < distance, without another nonlinear sign query in the algebraic tower.
        let zero = try field.integer(0, using: &admission)
        for axis in 0..<3 {
            let lower = try field.binary64(exactly: bounds[axis + 4].lower, using: &admission)
            let upper = try field.binary64(exactly: bounds[axis + 4].upper, using: &admission)
            let lowerError = try field.subtracting(candidate[axis], lower, using: &admission)
            let upperError = try field.subtracting(upper, candidate[axis], using: &admission)
            if try field.compare(lowerError, zero, using: &admission) == .less
                || field.compare(upperError, zero, using: &admission) == .less
                || field.compare(lowerError, absoluteLimit, using: &admission) == .greater
                || field.compare(upperError, absoluteLimit, using: &admission) == .greater { return false }
        }
        return true
    }

    private static func selected(_ lower: Double, _ upper: Double, _ requested: ScalarInterval?) throws -> ScalarInterval {
        try .init(lower: max(lower, requested?.lower ?? lower), upper: min(upper, requested?.upper ?? upper))
    }

    private static func retain<T, A: ExactScalarAdmission & ~Copyable>(
        _ count: Int, of type: T.Type, using admission: inout A
    ) throws {
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }

    private static func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
