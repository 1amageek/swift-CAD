import CADCore

/// Publishes representatives of isolated L5 components while retaining complete L6 coverage.
struct NativeExactCurveSurfacePointProducer {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    typealias Polynomials = ExactPolynomialDomain<Field>
    typealias Cells = ExactRealCellDomain<Base>

    func resolve<A: ExactScalarAdmission & ~Copyable>(curve: BSplineCurve3D,
        surface: BSplineSurface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, maximumExtensionLevel: Int,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> CurveSurfaceIntersectionResult {
        do {
            try options.validate(tolerance: tolerance)
            try surface.validate(tolerance: tolerance, using: &admission)
            let u = try ScalarInterval(lower: surface.uKnots[surface.uDegree],
                upper: surface.uKnots[surface.uControlPointCount])
            let v = try ScalarInterval(lower: surface.vKnots[surface.vDegree],
                upper: surface.vKnots[surface.vControlPointCount])
            let requested = SurfaceParameterBox(u: options.surfaceURange ?? u,
                v: options.surfaceVRange ?? v)
            let topology = limits.topology
            let boundedLimits = try ExactGeometricRelationLimits(cells: limits.cells,
                topology: .init(maximumGeneratedCells: topology.maximumGeneratedCells,
                    maximumRootsPerStack: topology.maximumRootsPerStack,
                    maximumClosures: min(topology.maximumClosures, options.maximumCandidateCount),
                    maximumAttachmentPieces: topology.maximumAttachmentPieces,
                    maximumComponents: topology.maximumComponents),
                maximumStrata: limits.maximumStrata, maximumProjectionSpans: limits.maximumProjectionSpans)
            let receipt = try DefaultCurveSurfaceIntersector().exactGeometricRelation(
                curve: curve, surface: surface, curveRange: options.curveRange,
                surfaceDomain: options.surfaceURange == nil && options.surfaceVRange == nil ? nil : requested,
                tolerance: tolerance,
                maximumPolynomialDegree: options.maximumPolynomialDegree,
                maximumExtensionLevel: maximumExtensionLevel, limits: boundedLimits, using: &admission)
            let relation = receipt.parameterRelation.relation
            guard relation.selection.cells.count <= options.maximumCandidateCount,
                relation.components.count <= options.maximumCandidateCount else {
                throw exhausted(tolerance)
            }
            let cells = try Cells(retaining: relation.original.predicate.source, using: &admission)
            var count = 0
            for members in relation.components.memberRanges {
                var isolated = true
                for index in members {
                    try admission.consumeWork(1)
                    if relation.components.members[index].dimension > 0 { isolated = false }
                }
                if isolated {
                    let (sum, overflow) = count.addingReportingOverflow(members.count)
                    guard !overflow, sum <= options.maximumCandidateCount else {
                        throw exhausted(tolerance)
                    }
                    count = sum
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count,
                of: CurveSurfaceIntersection.self))
            var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(count)
            for members in relation.components.memberRanges {
                var isolated = true
                for index in members {
                    try admission.consumeWork(1)
                    if relation.components.members[index].dimension > 0 { isolated = false }
                }
                guard isolated else { continue }
                for index in members {
                    let sample = try cells.sample(of: relation.components.members[index],
                        in: relation.selection.partition, using: &admission)
                    points.append(try publish(sample: sample, original: relation.original,
                        coefficientField: receipt.parameterRelation.coefficientField,
                        curve: curve, surface: surface, options: options,
                        tolerance: tolerance, using: &admission))
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [],
                originalExactGeometricRelation: receipt)
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    private func publish<A: ExactScalarAdmission & ~Copyable>(sample: ExactRealCellSample<Base>,
        original: ExactParametricRelationSource<Base>, coefficientField: Field, curve: BSplineCurve3D,
        surface: BSplineSurface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using admission: inout A
    ) throws -> CurveSurfaceIntersection {
        guard sample.coordinates.count == 3 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let field = sample.field
        let first = try laws(original.first, field: field, using: &admission)
        let second = try laws(original.second, field: field, using: &admission)
        let cp = try Polynomials(retaining: first[0], using: &admission)
        let sp = try Polynomials(retaining: second[0], using: &admission)
        let numericalFirst = original.first.original.polynomials
        let numericalSecond = original.second.original.polynomials
        let numericalCP = try Polynomials(retaining: numericalFirst[0], using: &admission)
        let numericalSP = try Polynomials(retaining: numericalSecond[0], using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Field.Value.self))
        let t = [sample.coordinates[0]], uv = [sample.coordinates[1], sample.coordinates[2]]
        let position = try values(first, at: t, polynomials: cp, field: field, using: &admission)
        let kind = try classify(first: first, second: second, t: t, uv: uv,
            cp: cp, sp: sp, field: field, tolerance: tolerance, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Field.Value.self))
        let exact = sample.coordinates + position
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: ScalarInterval.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: ScalarInterval.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: ScalarInterval?.self))
        var bounds = try parameterBounds(curve: curve, surface: surface, options: options)
        bounds.reserveCapacity(6)
        for axis in 0..<3 {
            var lower = Double.infinity, upper = -Double.infinity
            for point in curve.controlPoints {
                try admission.consumeWork(1)
                let value = axis == 0 ? point.x : axis == 1 ? point.y : point.z
                lower = min(lower, value); upper = max(upper, value)
            }
            bounds.append(try .init(lower: lower, upper: upper))
        }
        // Positive authored weights and the closed Bezier basis prove the XYZ hull seed.
        for index in bounds.indices {
            let lowerOrder = try field.compare(exact[index], field.binary64(exactly: bounds[index].lower,
                using: &admission), using: &admission)
            let upperOrder = try field.compare(exact[index], field.binary64(exactly: bounds[index].upper,
                using: &admission), using: &admission)
            guard lowerOrder != .less, upperOrder != .greater else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
            // Source equality to a closed endpoint retains that exact dyadic value;
            // bisection must not replace it with an interior approximation.
            if lowerOrder == .equal { bounds[index] = try .init(lower: bounds[index].lower, upper: bounds[index].lower) }
            else if upperOrder == .equal { bounds[index] = try .init(lower: bounds[index].upper, upper: bounds[index].upper) }
        }
        let distance = try coefficientField.binary64(exactly: tolerance.distance, using: &admission)
        let squared = try coefficientField.multiplying(distance, distance, using: &admission)
        let originalSquared = try field.importing(squared, using: &admission)
        for iteration in 0..<options.maximumIterations {
            for index in bounds.indices {
                try admission.consumeWork(1)
                let midpoint = try representative(bounds[index])
                let order = try field.compare(exact[index],
                    field.binary64(exactly: midpoint, using: &admission), using: &admission)
                bounds[index] = try .init(lower: order == .greater ? midpoint : bounds[index].lower,
                    upper: order == .less ? midpoint : order == .equal ? midpoint : bounds[index].upper)
                if order == .equal { bounds[index] = try .init(lower: midpoint, upper: midpoint) }
            }
            try admission.consumeWork(bounds.count)
            guard bounds.allSatisfy({ $0.upper - $0.lower <= tolerance.distance }) else { continue }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
            let representatives = try bounds.map { try representative($0) }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Field.Value.self))
            // Candidate parameters are original dyadic values. Evaluate their source maps in
            // the retained coefficient field, without lifting rational residual work into
            // the exact sample's algebraic tower or inheriting its root-refinement depth.
            let nt = [try coefficientField.binary64(exactly: representatives[0], using: &admission)]
            let nuv = [try coefficientField.binary64(exactly: representatives[1], using: &admission),
                try coefficientField.binary64(exactly: representatives[2], using: &admission)]
            let numericalCurve = try values(numericalFirst, at: nt, polynomials: numericalCP,
                field: coefficientField, using: &admission)
            let numericalSurface = try values(numericalSecond, at: nuv, polynomials: numericalSP,
                field: coefficientField, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Field.Value.self))
            let numericalPoint = try [coefficientField.binary64(exactly: representatives[3], using: &admission),
                coefficientField.binary64(exactly: representatives[4], using: &admission),
                coefficientField.binary64(exactly: representatives[5], using: &admission)]
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Field.Value.self))
            let originalUV = try [field.importing(nuv[0], using: &admission),
                field.importing(nuv[1], using: &admission)]
            if try parametersWithin(sample.coordinates, t: field.importing(nt[0], using: &admission),
                uv: originalUV, squared: originalSquared,
                field: field, using: &admission),
                try positionWithinBounds(bounds, point: numericalPoint, distance: distance,
                    field: coefficientField, using: &admission),
                try within(numericalCurve, numericalSurface, squared: squared, field: coefficientField, using: &admission),
                try within(numericalCurve, numericalPoint, squared: squared, field: coefficientField, using: &admission),
                try within(numericalSurface, numericalPoint, squared: squared, field: coefficientField, using: &admission) {
                // The exact squared-distance predicate certifies this residual upper bound.
                return try .init(point: .init(x: representatives[3], y: representatives[4], z: representatives[5]),
                    curveParameter: representatives[0], surfaceU: representatives[1],
                    surfaceV: representatives[2], kind: kind, residual: tolerance.distance,
                    iterations: iteration)
            }
        }
        throw exhausted(tolerance)
    }

    private func positionWithinBounds<A: ExactScalarAdmission & ~Copyable>(_ bounds: [ScalarInterval],
        point: [Field.Value], distance: Field.Value, field: Field,
        using admission: inout A) throws -> Bool {
        let half = try field.dividing(distance, field.integer(2, using: &admission), using: &admission)
        for axis in 0..<3 {
            let lower = try field.binary64(exactly: bounds[axis + 3].lower, using: &admission)
            let upper = try field.binary64(exactly: bounds[axis + 3].upper, using: &admission)
            let fromLower = try field.subtracting(point[axis], lower, using: &admission)
            let toUpper = try field.subtracting(upper, point[axis], using: &admission)
            guard try field.compare(fromLower, half, using: &admission) != .greater,
                try field.compare(toUpper, half, using: &admission) != .greater else { return false }
        }
        // Exact authored XYZ remains inside these retained brackets. Per-axis error
        // <= distance/2 implies squared Euclidean error <= 3*distance^2/4.
        return true
    }

    private func representative(_ bounds: ScalarInterval) throws -> Double {
        let value = bounds.lower == bounds.upper ? bounds.lower : bounds.lower * 0.5 + bounds.upper * 0.5
        guard value.isFinite, value >= bounds.lower, value <= bounds.upper else {
            throw ExactGeometricRelationFailure.invalidCoverage
        }
        return value
    }

    private func parameterBounds(curve: BSplineCurve3D, surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions) throws -> [ScalarInterval] {
        let native = try [ScalarInterval(lower: curve.knots[curve.degree], upper: curve.knots[curve.controlPointCount]),
            ScalarInterval(lower: surface.uKnots[surface.uDegree], upper: surface.uKnots[surface.uControlPointCount]),
            ScalarInterval(lower: surface.vKnots[surface.vDegree], upper: surface.vKnots[surface.vControlPointCount])]
        let selected = [options.curveRange, options.surfaceURange, options.surfaceVRange]
        return try native.indices.map { i in
            try .init(lower: max(native[i].lower, selected[i]?.lower ?? native[i].lower),
                upper: min(native[i].upper, selected[i]?.upper ?? native[i].upper))
        }
    }

    private func laws<A: ExactScalarAdmission & ~Copyable>(_ map: ExactParametricMap<Base>,
        field: Field, using admission: inout A) throws -> [Polynomial] {
        guard map.original.polynomials.count == 4 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let p = try Polynomials(field: field, variableCount: map.parameterCount, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Polynomial.self))
        var result: [Polynomial] = []; result.reserveCapacity(4)
        for law in map.original.polynomials { result.append(try p.importing(law, using: &admission)) }
        return result
    }

    private func values<A: ExactScalarAdmission & ~Copyable>(_ laws: [Polynomial],
        at coordinates: [Field.Value], polynomials p: Polynomials, field: Field,
        using admission: inout A) throws -> [Field.Value] {
        let weight = try evaluated(laws[3], at: coordinates, p: p, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Field.Value.self))
        var result: [Field.Value] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            result.append(try field.dividing(evaluated(laws[axis], at: coordinates,
                p: p, using: &admission), weight, using: &admission))
        }
        return result
    }

    private func evaluated<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial,
        at coordinates: [Field.Value], p: Polynomials, using admission: inout A
    ) throws -> Field.Value {
        let result = try p.evaluated(law, at: coordinates, using: &admission)
        try admission.admitDepth(value: result.depth.value, coefficient: result.depth.coefficient)
        return result.value
    }

    private func parametersWithin<A: ExactScalarAdmission & ~Copyable>(_ original: [Field.Value],
        t: Field.Value, uv: [Field.Value], squared: Field.Value, field: Field,
        using admission: inout A) throws -> Bool {
        for axis in 0..<3 {
            let representative = axis == 0 ? t : uv[axis - 1]
            let error = try field.subtracting(original[axis], representative, using: &admission)
            guard try field.compare(field.multiplying(error, error, using: &admission), squared,
                using: &admission) != .greater else { return false }
        }
        return true
    }

    private func within<A: ExactScalarAdmission & ~Copyable>(_ first: [Field.Value],
        _ second: [Field.Value], squared: Field.Value, field: Field,
        using admission: inout A) throws -> Bool {
        var total = try field.integer(0, using: &admission)
        for axis in 0..<3 {
            let delta = try field.subtracting(first[axis], second[axis], using: &admission)
            total = try field.adding(total, field.multiplying(delta, delta, using: &admission), using: &admission)
        }
        return try field.compare(total, squared, using: &admission) != .greater
    }

    private func derivative<A: ExactScalarAdmission & ~Copyable>(_ laws: [Polynomial],
        variable: Int, at coordinates: [Field.Value], p: Polynomials,
        field: Field, using admission: inout A) throws -> [Field.Value] {
        let weight = try evaluated(laws[3], at: coordinates, p: p, using: &admission)
        let derivative = try evaluated(p.differentiated(laws[3], in: variable, using: &admission),
            at: coordinates, p: p, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Field.Value.self))
        var result: [Field.Value] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            let value = try evaluated(laws[axis], at: coordinates, p: p, using: &admission)
            let differentiated = try evaluated(p.differentiated(laws[axis], in: variable, using: &admission),
                at: coordinates, p: p, using: &admission)
            result.append(try field.subtracting(field.multiplying(differentiated, weight, using: &admission),
                field.multiplying(value, derivative, using: &admission), using: &admission))
        }
        return result
    }

    private func classify<A: ExactScalarAdmission & ~Copyable>(first: [Polynomial], second: [Polynomial],
        t: [Field.Value], uv: [Field.Value], cp: Polynomials, sp: Polynomials,
        field: Field, tolerance: ModelingTolerance, using admission: inout A
    ) throws -> CurveSurfaceIntersectionKind {
        let tangent = try derivative(first, variable: 0, at: t, p: cp, field: field, using: &admission)
        let du = try derivative(second, variable: 0, at: uv, p: sp, field: field, using: &admission)
        let dv = try derivative(second, variable: 1, at: uv, p: sp, field: field, using: &admission)
        var tangentSquared = try field.integer(0, using: &admission)
        var normalSquared = tangentSquared, dot = tangentSquared
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            let normal = try field.subtracting(field.multiplying(du[b], dv[c], using: &admission),
                field.multiplying(du[c], dv[b], using: &admission), using: &admission)
            tangentSquared = try field.adding(tangentSquared,
                field.multiplying(tangent[axis], tangent[axis], using: &admission), using: &admission)
            normalSquared = try field.adding(normalSquared,
                field.multiplying(normal, normal, using: &admission), using: &admission)
            dot = try field.adding(dot, field.multiplying(tangent[axis], normal, using: &admission), using: &admission)
        }
        if try field.sign(of: tangentSquared, using: &admission) == .zero { return .mixed }
        if try field.sign(of: normalSquared, using: &admission) == .zero { return .mixed }
        let angle = try field.binary64(exactly: tolerance.angle, using: &admission)
        let threshold = try field.multiplying(field.multiplying(tangentSquared, normalSquared, using: &admission),
            field.multiplying(angle, angle, using: &admission), using: &admission)
        return try field.compare(field.multiplying(dot, dot, using: &admission), threshold,
            using: &admission) == .greater ? .transverse : .tangent
    }

    private func exhausted(_ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "L6 curve-surface publication exhausted the existing result or refinement allowance.")
    }
}
