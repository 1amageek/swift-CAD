import CADCore

/// Original coefficient slices, with no extraction, insertion or rounded trimming.
struct OriginalCorrespondenceNativeCurve {
    struct Span {
        let lower: Double
        let upper: Double
        let firstControl: Int
    }
    let source: BSplineCurve3D
    let spans: [Span]
    let lower: Double
    let upper: Double

    init(source: BSplineCurve3D, maximumDegree: Int, budget: inout OriginalCorrespondenceBudget) throws {
        // Main-native BSplineCurve3D has no cyclic metadata or cyclic evaluator;
        // exact closed-domain, clamped-knot and multiplicity checks below are the
        // nonperiodic admission authority for this certificate.
        guard (1...maximumDegree).contains(source.degree) else { throw budget.unsupported() }
        try source.validate(tolerance: budget.tolerance)
        guard source.knots.prefix(source.degree + 1).allSatisfy({ $0 == source.knots[source.degree] }),
              source.knots.suffix(source.degree + 1).allSatisfy({ $0 == source.knots[source.controlPointCount] }) else {
            throw budget.unsupported()
        }
        lower = source.knots[source.degree]
        upper = source.knots[source.controlPointCount]
        self.source = source
        var index = source.degree + 1
        while index < source.controlPointCount {
            var end = index + 1
            while end < source.controlPointCount, source.knots[end] == source.knots[index] { end += 1 }
            guard end - index == source.degree else { throw budget.unsupported() }
            index = end
        }
        var records: [Span] = []
        for index in source.degree..<source.controlPointCount where source.knots[index] < source.knots[index + 1] {
            try budget.charge()
            records.append(Span(lower: source.knots[index], upper: source.knots[index + 1],
                firstControl: index - source.degree))
        }
        spans = records
    }

    func enclose(parameter: OriginalCorrespondenceScalarJet,
                 budget: inout OriginalCorrespondenceBudget) throws -> [OriginalCorrespondenceScalarJet] {
        // Caller has independently established that the exact parameter stays in this domain.
        let parameter = try parameter.contained(in: OutwardScalarInterval(lower: lower, upper: upper),
            tolerance: budget.tolerance)
        var first = 0, last = spans.count
        while first < last {
            let mid = first + (last - first) / 2
            if spans[mid].upper < parameter.value.lower { first = mid + 1 } else { last = mid }
        }
        var result: [OriginalCorrespondenceScalarJet]?
        var index = first
        while index < spans.count, spans[index].lower <= parameter.value.upper {
            try budget.charge()
            let span = spans[index]
            let selected = try parameter.contained(in: OutwardScalarInterval(lower: span.lower, upper: span.upper),
                tolerance: budget.tolerance)
            let q = try (selected - .constant(span.lower)).divided(
                by: .constant(span.upper) - .constant(span.lower), tolerance: budget.tolerance)
                .contained(in: OutwardScalarInterval(lower: 0, upper: 1), tolerance: budget.tolerance)
            let jets = try patch(span, at: q, tolerance: budget.tolerance)
            if let old = result { result = zip(old, jets).map { $0.union($1) } } else { result = jets }
            index += 1
        }
        guard let result else {
            throw OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance,
                "The original parameter does not intersect a retained native curve span.")
        }
        return result
    }

    private func patch(_ span: Span, at q: OriginalCorrespondenceScalarJet,
                       tolerance: ModelingTolerance) throws -> [OriginalCorrespondenceScalarJet] {
        let indices = span.firstControl...(span.firstControl + source.degree)
        var weightLower = Double.infinity, weightUpper = -Double.infinity
        for index in indices {
            weightLower = min(weightLower, source.weights[index])
            weightUpper = max(weightUpper, source.weights[index])
        }
        var weights = indices.map { OriginalCorrespondenceScalarJet.constant(source.weights[$0]) }
        let commonWeight = weightLower == weightUpper
        let weight = commonWeight ? OriginalCorrespondenceScalarJet.constant(weightLower)
            : try evaluate(&weights, at: q).contained(
                in: OutwardScalarInterval(lower: weightLower, upper: weightUpper), tolerance: tolerance)
        var result: [OriginalCorrespondenceScalarJet] = []
        for axis in 0..<3 {
            func coordinate(_ index: Int) -> Double {
                let p = source.controlPoints[index]
                return axis == 0 ? p.x : axis == 1 ? p.y : p.z
            }
            var low = Double.infinity, high = -Double.infinity
            var controls: [OriginalCorrespondenceScalarJet] = []
            for index in indices {
                let value = coordinate(index)
                low = min(low, value); high = max(high, value)
                controls.append(.constant(value) * .constant(source.weights[index]))
            }
            // A common Cartesian coordinate is an exact rational identity.
            if low == high { result.append(.constant(low)); continue }
            let value = try evaluate(&controls, at: q).divided(by: weight, tolerance: tolerance)
                .contained(in: OutwardScalarInterval(lower: low, upper: high), tolerance: tolerance)
            result.append(value)
        }
        return result
    }

    private func evaluate(_ level: inout [OriginalCorrespondenceScalarJet],
                          at q: OriginalCorrespondenceScalarJet) -> OriginalCorrespondenceScalarJet {
        var count = level.count
        let complement = OriginalCorrespondenceScalarJet.constant(1) - q
        while count > 1 {
            for index in 0..<(count - 1) { level[index] = level[index] * complement + level[index + 1] * q }
            count -= 1
        }
        return level[0]
    }
}
