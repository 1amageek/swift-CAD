import CADCore

/// Affine refinement of authored spline expressions, independent of their current values.
public struct SketchSplineRefinement: Sendable {
    public init() {}

    /// Raises an interior knot to `multiplicity`, preserving every coordinate dependency.
    public func insertingKnot(
        in spline: SketchSpline, at parameter: Double, multiplicity: Int
    ) throws -> SketchSpline {
        var knots = try validatedKnots(spline)
        guard parameter.isFinite,
              parameter > knots[spline.degree], parameter < knots[knots.count - spline.degree - 1],
              (1...spline.degree).contains(multiplicity) else {
            throw SketchError.unsupportedEntity("Spline refinement requires an interior knot and valid multiplicity.")
        }
        let degree = spline.degree
        var points = spline.controlPoints
        let existing = knots.filter { $0 == parameter }.count
        guard existing <= multiplicity else {
            throw SketchError.unsupportedEntity("Knot insertion cannot reduce multiplicity.")
        }
        for current in existing..<multiplicity {
            guard let span = knots.lastIndex(where: { $0 <= parameter }) else {
                throw SketchError.unsupportedEntity("Spline refinement could not resolve the knot span.")
            }
            var next = Array(points.prefix(span - degree + 1))
            for index in (span - degree + 1)...(span - current) {
                let denominator = knots[index + degree] - knots[index]
                guard denominator.isFinite, denominator > 0 else {
                    throw SketchError.unsupportedEntity("Spline refinement has an invalid knot interval.")
                }
                next.append(interpolate(points[index - 1], points[index], fraction: (parameter - knots[index]) / denominator))
            }
            next.append(contentsOf: points[(span - current)...])
            knots.insert(parameter, at: span + 1)
            points = next
        }
        let result = SketchSpline(controlPoints: points, isClosed: spline.isClosed, degree: degree, knots: knots)
        try result.validateForm()
        return result
    }

    /// Splits on the existing parameter domain. Both outputs are clamped at the shared point.
    public func split(_ spline: SketchSpline, at parameter: Double) throws -> (lower: SketchSpline, upper: SketchSpline) {
        guard !spline.isClosed else {
            throw SketchError.unsupportedEntity("Open a closed spline before splitting its parameter domain.")
        }
        let refined = try insertingKnot(in: spline, at: parameter, multiplicity: spline.degree)
        guard let knots = refined.knots, let first = knots.firstIndex(of: parameter) else {
            throw SketchError.unsupportedEntity("Spline split could not resolve its inserted knot.")
        }
        let seam = first - 1
        let clamped = Array(repeating: parameter, count: spline.degree + 1)
        let lower = SketchSpline(
            controlPoints: Array(refined.controlPoints[...seam]), degree: spline.degree,
            knots: Array(knots.prefix(first)) + clamped
        )
        let upper = SketchSpline(
            controlPoints: Array(refined.controlPoints[seam...]), degree: spline.degree,
            knots: clamped + knots.dropFirst(first + spline.degree)
        )
        try lower.validateForm()
        try upper.validateForm()
        return (lower, upper)
    }

    /// Elevates each exact Bezier span and retains its original parameter interval.
    public func degreeElevated(_ spline: SketchSpline) throws -> SketchSpline {
        let sourceKnots = try validatedKnots(spline)
        guard spline.degree < SketchSpline.maximumDegree else {
            throw SketchError.unsupportedEntity("Spline degree cannot be raised beyond its supported range.")
        }
        let degree = spline.degree
        let breaks = sourceKnots.reduce(into: [Double]()) { values, knot in
            if values.last != knot { values.append(knot) }
        }
        var refined = spline
        for value in breaks.dropFirst().dropLast() {
            refined = try insertingKnot(in: refined, at: value, multiplicity: degree)
        }
        let raised = degree + 1
        var points: [SketchPoint] = []
        for span in 0..<(breaks.count - 1) {
            let start = span * degree
            if span == 0 { points.append(refined.controlPoints[start]) }
            for index in 1...degree {
                points.append(interpolate(
                    refined.controlPoints[start + index - 1], refined.controlPoints[start + index],
                    fraction: 1 - Double(index) / Double(raised)
                ))
            }
            points.append(refined.controlPoints[start + degree])
        }
        let knots = Array(repeating: breaks[0], count: raised + 1)
            + breaks.dropFirst().dropLast().flatMap { Array(repeating: $0, count: raised) }
            + Array(repeating: breaks[breaks.count - 1], count: raised + 1)
        let chain = SketchSpline(controlPoints: points, isClosed: spline.isClosed, degree: raised)
        let result = chain.knotVector == knots ? chain : SketchSpline(
            controlPoints: points, isClosed: spline.isClosed, degree: raised, knots: knots
        )
        try result.validateForm()
        return result
    }

    private func validatedKnots(_ spline: SketchSpline) throws -> [Double] {
        try spline.validateForm()
        guard let knots = spline.knotVector,
              knots.dropFirst(spline.degree + 1).dropLast(spline.degree + 1).allSatisfy({
                  $0 > knots[0] && $0 < knots[knots.count - 1]
              }) else {
            throw SketchError.unsupportedEntity("Spline refinement requires exactly degree + 1 knots at each endpoint.")
        }
        return knots
    }

    private func interpolate(_ first: SketchPoint, _ second: SketchPoint, fraction: Double) -> SketchPoint {
        func coordinate(_ a: CADExpression, _ b: CADExpression) -> CADExpression {
            if fraction == 0 { return a }
            if fraction == 1 { return b }
            return .add(.multiply(.constant(.scalar(1 - fraction)), a), .multiply(.constant(.scalar(fraction)), b))
        }
        return SketchPoint(x: coordinate(first.x, second.x), y: coordinate(first.y, second.y))
    }
}
