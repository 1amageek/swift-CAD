import CADCore

/// Certified numerical representatives of retained original rational graph tuples.
struct OriginalRationalGraphPointPublisher<S: Sendable, E: Sendable, C: Sendable,
    T: Sendable, F: Sendable, D: Sendable> {
    private typealias Base = OriginalExactScalarDomain
    private typealias Algebraic = ExactAlgebraicScalarDomain<Base>
    private typealias Geometry = OriginalIssuedGeometricRelations<S,E,C,T,F,D>

    func publish<A: ExactScalarAdmission & ~Copyable>(_ geometry: OriginalIssuedGeometricRelations<S,E,C,T,F,D>,
        field: OriginalExactScalarDomain, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        maximumDepth: Int, using a: inout A
    ) throws -> (points: [CurveSurfaceIntersection], receipt: OriginalIssuedNumericalCurveSurfacePoints) {
        try a.checkpoint(); try geometry.original.admitProof(limits: limits, using: &a)
        guard geometry.kind == .curveSurface else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        for graph in geometry.original.first.graphs { try requireIdentity(graph.original.graph, arity: 1, using: &a) }
        for graph in geometry.original.second.graphs { try requireIdentity(graph.original.graph, arity: 2, using: &a) }
        let count = geometry.exactPoints.count
        guard count <= options.maximumCandidateCount else { throw ExactScalarFailure.resourceLimit(.work) }
        let total = count.multipliedReportingOverflow(by: 6)
        guard !total.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: total.partialValue, of: Algebraic.Value.self))
        var exact: [Algebraic.Value] = []; exact.reserveCapacity(total.partialValue)
        for point in geometry.exactPoints {
            try a.consumeWork(1)
            guard point.firstParameters.count == 1, point.secondParameters.count == 2 else {
                throw ExactGeometricRelationFailure.invalidSourceBinding
            }
            exact.append(point.firstParameters[0]); exact.append(contentsOf: point.secondParameters)
            exact.append(point.position.x); exact.append(point.position.y); exact.append(point.position.z)
        }
        let transferred = try DefaultExactOriginalScalarTransporter().transfer(exact, into: field, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Int.self))
        var ordinals: [Int] = []; ordinals.reserveCapacity(count)
        for index in 0..<count { try a.consumeWork(1); ordinals.append(index) }
        func order(_ left: Int, _ right: Int, _ a: inout A) throws -> ExactOrder {
            for axis in 0..<3 {
                let answer = try transferred.field.compare(transferred.values[6*left+axis],
                    transferred.values[6*right+axis], using: &a)
                if answer != .equal { return answer }
            }
            return .equal
        }
        // One admitted index buffer preserves every incident and avoids sort scratch.
        func sift(_ start: Int, _ end: Int, _ indices: inout [Int], _ a: inout A) throws {
            var parent = start
            while parent < end/2 {
                try a.consumeWork(1)
                var child = parent*2+1
                if child+1 < end, try order(indices[child], indices[child+1], &a) == .less { child += 1 }
                if try order(indices[parent], indices[child], &a) != .less { return }
                indices.swapAt(parent, child); parent = child
            }
        }
        if count > 1 {
            for start in stride(from: count/2-1, through: 0, by: -1) { try sift(start, count, &ordinals, &a) }
            for end in stride(from: count-1, through: 1, by: -1) {
                ordinals.swapAt(0, end); try sift(0, end, &ordinals, &a)
            }
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Range<Int>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: CurveSurfaceIntersection.self))
        var ranges: [Range<Int>] = []; ranges.reserveCapacity(count)
        var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(count)
        var start = 0
        while start < count {
            var end = start+1
            while end < count, try order(ordinals[start], ordinals[end], &a) == .equal { end += 1 }
            let range = start..<end
            let kind = try classify(geometry, ordinals: ordinals, range: range, tolerance: tolerance, using: &a)
            points.append(try representative(geometry, transfer: transferred, ordinals: ordinals, range: range,
                kind: kind, options: options, tolerance: tolerance, limits: limits, maximumDepth: maximumDepth, using: &a))
            ranges.append(range); start = end
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedNumericalCurveSurfacePoints.self))
        let receipt = OriginalIssuedNumericalCurveSurfacePoints(geometry: geometry, coordinates: transferred,
            incidenceOrdinals: ordinals, incidenceRanges: ranges)
        try a.checkpoint(); return (points, receipt)
    }

    private func requireIdentity<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,Base,Evidence>, arity: Int, using a: inout A) throws {
        try a.admitDepth(value: graph.proofDepth.value, coefficient: graph.proofDepth.coefficient)
        guard graph.layout.variableCount == arity, graph.layout.parameters.count == arity,
            graph.polynomials.variableCount == arity, graph.homogeneous.count == 4,
            graph.parameterTransport.numerators.count == arity,
            graph.parameterTransport.denominators.count == arity else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        for axis in 0..<arity {
            try a.consumeWork(1)
            guard graph.layout.parameters[axis] == axis else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let ring = graph.polynomials
            let difference = try ring.subtracting(graph.parameterTransport.numerators[axis],
                ring.multiplying(ring.variable(axis, using: &a), graph.parameterTransport.denominators[axis], using: &a), using: &a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary rational graph point
            // publisher currently accepts proved identity parameter transports.
            // Nonidentity/auxiliary charts need checked local numeric preimages
            // before their authored tuples may be evaluated for publication.
            guard try ring.isZero(difference, using: &a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        }
    }

    private func classify<A: ExactScalarAdmission & ~Copyable>(_ geometry: Geometry,
        ordinals: [Int], range: Range<Int>, tolerance: ModelingTolerance, using a: inout A
    ) throws -> CurveSurfaceIntersectionKind {
        var answer: CurveSurfaceIntersectionKind?
        for ordinal in range {
            let point = geometry.exactPoints[ordinals[ordinal]], f = point.local.witness.field
            let pair = geometry.original.pairs[point.pairOrdinal]
            let first = geometry.original.first.graphs[pair.firstGraphIndex].original.graph
            let second = geometry.original.second.graphs[pair.secondGraphIndex].original.graph
            let curve = try derivative(first, at: point.firstParameters, axis: 0, field: f, using: &a)
            let u = try derivative(second, at: point.secondParameters, axis: 0, field: f, using: &a)
            let v = try derivative(second, at: point.secondParameters, axis: 1, field: f, using: &a)
            var tangentSquared = try f.integer(0, using: &a), normalSquared = tangentSquared, dot = tangentSquared
            for axis in 0..<3 {
                let i = (axis+1)%3, j = (axis+2)%3
                let normal = try f.subtracting(f.multiplying(u[i], v[j], using: &a), f.multiplying(u[j], v[i], using: &a), using: &a)
                tangentSquared = try f.adding(tangentSquared, f.multiplying(curve[axis], curve[axis], using: &a), using: &a)
                normalSquared = try f.adding(normalSquared, f.multiplying(normal, normal, using: &a), using: &a)
                dot = try f.adding(dot, f.multiplying(curve[axis], normal, using: &a), using: &a)
            }
            let kind: CurveSurfaceIntersectionKind
            if try f.sign(of: tangentSquared, using: &a) == .zero || f.sign(of: normalSquared, using: &a) == .zero { kind = .mixed }
            else {
                let angle = try f.binary64(exactly: tolerance.angle, using: &a)
                let threshold = try f.multiplying(f.multiplying(tangentSquared, normalSquared, using: &a),
                    f.multiplying(angle, angle, using: &a), using: &a)
                kind = try f.compare(f.multiplying(dot, dot, using: &a), threshold, using: &a) == .greater ? .transverse : .tangent
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Disagreeing incident germs need
            // a scoped multi-classification receipt before ordinary success.
            guard answer == nil || answer == kind else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            answer = kind
        }
        guard let answer else { throw ExactGeometricRelationFailure.invalidCoverage }
        return answer
    }

    private func derivative<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,Base,Evidence>, at: [Algebraic.Value], axis: Int,
        field: Algebraic, using a: inout A) throws -> [Algebraic.Value] {
        let ring = try ExactPolynomialDomain(field: field, variableCount: at.count, using: &a)
        let w = try imported(graph.homogeneous[3], into: ring, using: &a)
        let weight = try ring.evaluated(w, at: at, using: &a).value
        guard try field.sign(of: weight, using: &a) != .zero else { throw ExactGeometricRelationFailure.invalidCoverage }
        let dw = try ring.evaluated(ring.differentiated(w, in: axis, using: &a), at: at, using: &a).value
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Algebraic.Value.self))
        var result: [Algebraic.Value] = []; result.reserveCapacity(3)
        for coordinate in 0..<3 {
            let p = try imported(graph.homogeneous[coordinate], into: ring, using: &a)
            let value = try ring.evaluated(p, at: at, using: &a).value
            let dp = try ring.evaluated(ring.differentiated(p, in: axis, using: &a), at: at, using: &a).value
            result.append(try field.subtracting(field.multiplying(dp, weight, using: &a), field.multiplying(value, dw, using: &a), using: &a))
        }
        return result
    }

    private func representative<A: ExactScalarAdmission & ~Copyable>(_ geometry: Geometry,
        transfer: ExactOriginalScalarTransferReceipt, ordinals: [Int], range: Range<Int>, kind: CurveSurfaceIntersectionKind,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        maximumDepth: Int, using a: inout A) throws -> CurveSurfaceIntersection {
        let f = transfer.field, offset = ordinals[range.lowerBound]*6
        let maximum = try ExactScalarDepth(value: maximumDepth, coefficient: maximumDepth)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalSingularFieldValueIsolation.self))
        var isolations: [OriginalSingularFieldValueIsolation] = []; isolations.reserveCapacity(6)
        var inherited = ExactScalarDepth.zero
        for axis in 0..<6 {
            let value = transfer.values[offset+axis]
            let seed = try ExactScalarNumericAccess.withAdmission(&a, original: value.depth, inherited: value.depth, maximum: maximum) { usage in
                try OriginalSingularFieldValueIsolation(original: value.original, inheritedDepth: value.depth.value,
                    maximumDepth: maximumDepth, usage: &usage)
            }
            inherited = try .init(value: max(inherited.value, seed.depth.value), coefficient: max(inherited.coefficient, seed.depth.coefficient))
            isolations.append(seed.value)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        var numbers: [Double] = []; numbers.reserveCapacity(6)
        let epsilon = try f.binary64(exactly: tolerance.distance, using: &a)
        let squared = try f.multiplying(epsilon, epsilon, using: &a)
        var width = ExactRationalCoefficient.one
        for iteration in 0..<options.maximumIterations {
            numbers.removeAll(keepingCapacity: true)
            var narrow = true
            for axis in 0..<6 {
                let isolation = isolations[axis]
                let depth = try ExactScalarDepth(value: isolation.sourceDepth, coefficient: transfer.values[offset+axis].depth.coefficient)
                let refined = try ExactScalarNumericAccess.withAdmission(&a, original: depth, inherited: depth, maximum: maximum) { usage in
                    let next = try isolation.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
                    return (next, try next.enclosure(usage: &usage))
                }
                inherited = try .init(value: max(inherited.value, refined.depth.value), coefficient: max(inherited.coefficient, refined.depth.coefficient))
                isolations[axis] = refined.value.0
                let bounds = refined.value.1
                if bounds.upper-bounds.lower > tolerance.distance { narrow = false }
                var number = bounds.lower*0.5+bounds.upper*0.5
                let request = axis == 0 ? options.curveRange : axis == 1 ? options.surfaceURange : axis == 2 ? options.surfaceVRange : nil
                if let request { number = max(request.lower, min(request.upper, number)) }
                guard number.isFinite, number >= bounds.lower, number <= bounds.upper else { throw ExactGeometricRelationFailure.invalidCoverage }
                numbers.append(number)
            }
            if narrow {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                var numeric: [OriginalExactScalar] = []; numeric.reserveCapacity(6)
                for number in numbers { numeric.append(try f.binary64(exactly: number, using: &a)) }
                var parametersValid = true
                for axis in 0..<3 {
                    let delta = try f.subtracting(transfer.values[offset+axis], numeric[axis], using: &a)
                    if try f.compare(f.multiplying(delta, delta, using: &a), squared, using: &a) == .greater { parametersValid = false }
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                let published = [numeric[3],numeric[4],numeric[5]]
                let original = [transfer.values[offset+3],transfer.values[offset+4],transfer.values[offset+5]]
                for index in range {
                    let point = geometry.exactPoints[ordinals[index]], pair = geometry.original.pairs[point.pairOrdinal]
                    let first = geometry.original.first.graphs[pair.firstGraphIndex].original.graph
                    let second = geometry.original.second.graphs[pair.secondGraphIndex].original.graph
                    if let curve = try position(first, numbers: numbers, offset: 0, field: f, limits: limits, using: &a),
                        let surface = try position(second, numbers: numbers, offset: 1, field: f, limits: limits, using: &a),
                        parametersValid, try within(original, published, squared: squared, field: f, using: &a),
                        try within(curve, surface, squared: squared, field: f, using: &a),
                        try within(curve, published, squared: squared, field: f, using: &a),
                        try within(surface, published, squared: squared, field: f, using: &a) {
                        return try .init(point: .init(x: numbers[3], y: numbers[4], z: numbers[5]), curveParameter: numbers[0],
                            surfaceU: numbers[1], surfaceV: numbers[2], kind: kind, residual: tolerance.distance, iterations: iteration)
                    }
                }
            }
            width = try ExactScalarNumericAccess.withAdmission(&a, inherited: inherited, maximum: maximum) { usage in
                try width.divided(by: .natural(2, usage: &usage), usage: &usage)
            }.value
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original rational graph publication exhausted the caller's refinement iterations.")
    }

    private func position<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<Source,Base,Evidence>, numbers: [Double], offset: Int,
        field: Base, limits: OriginalDomainIdentityLimits, using a: inout A) throws -> [OriginalExactScalar]? {
        let n = graph.layout.variableCount
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: OriginalExactScalar.self))
        var at: [OriginalExactScalar] = []; at.reserveCapacity(n)
        for axis in 0..<n { at.append(try graph.field.binary64(exactly: numbers[offset+axis], using: &a)) }
        guard try graph.admits(at, limits: limits.source, using: &a) else { return nil }
        let weight = try graph.polynomials.evaluated(graph.homogeneous[3], at: at, using: &a).value
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: OriginalExactScalar.self))
        var result: [OriginalExactScalar] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            result.append(try field.importing(graph.field.dividing(graph.polynomials.evaluated(graph.homogeneous[axis], at: at, using: &a).value,
                weight, using: &a), using: &a))
        }
        return result
    }

    private func imported<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<Base>,
        into ring: ExactPolynomialDomain<Algebraic>, using a: inout A) throws -> ExactPolynomial<Algebraic> {
        try a.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: law.terms.count, of: ExactPolynomialTerm<Algebraic.Value>.self))
        var terms: [ExactPolynomialTerm<Algebraic.Value>] = []; terms.reserveCapacity(law.terms.count)
        for term in law.terms {
            try a.consumeWork(1)
            terms.append(.init(powers: term.powers, coefficient: try ring.field.importingBase(term.coefficient, using: &a)))
        }
        return try ring.polynomial(terms: terms, using: &a)
    }

    private func within<A: ExactScalarAdmission & ~Copyable>(_ first: [OriginalExactScalar], _ second: [OriginalExactScalar],
        squared: OriginalExactScalar, field: Base, using a: inout A) throws -> Bool {
        var total = try field.integer(0, using: &a)
        for axis in 0..<3 {
            let delta = try field.subtracting(first[axis], second[axis], using: &a)
            total = try field.adding(total, field.multiplying(delta, delta, using: &a), using: &a)
        }
        return try field.compare(total, squared, using: &a) != .greater
    }
}
