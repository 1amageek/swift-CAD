import CADCore
import CADGeometry

/// Original polynomial Green coefficients and prefixes, in retained native charts.
struct CertifiedPiecewisePolynomialSurfaceFluxPrimitive {
    typealias Interval = CertifiedUnivariateTaylorJet.Interval
    typealias Jet = CertifiedUnivariateTaylorJet
    typealias Span = CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan

    struct NativePanel {
        let uSpan: Span
        let vSpan: Span
        let fluxCoefficients: [[Interval]]
    }
    struct Panel {
        let uSpan: Span
        let coefficients: [[Interval]]
    }
    struct Band {
        let vSpan: Span
        let panels: [Panel]
    }

    let source: BSplineSurface3D
    let reference: Point3D
    let tolerance: ModelingTolerance
    let uBase: Double
    let uSpans: [Span]
    let vSpans: [Span]
    let bands: [Band]
    let field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField

    init(source: BSplineSurface3D, reference: Point3D, tolerance: ModelingTolerance,
         uBase: Double, uSpans: [Span], vSpans: [Span], panels: [NativePanel],
         field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
         consume: (Int) throws -> Void) throws {
        guard let firstU = uSpans.first, let lastU = uSpans.last,
              uBase.isFinite, uBase >= firstU.lower, uBase <= lastU.upper,
              !vSpans.isEmpty else { throw Self.failure(.invalidInput, tolerance, "Green preparation requires a contained native base and nonempty spans.") }
        let count = uSpans.count.multipliedReportingOverflow(by: vSpans.count)
        guard !count.overflow, count.partialValue == panels.count else {
            throw Self.failure(.topologyFailure, tolerance, "Green preparation lost its original tensor cover.")
        }
        var metadataCount = 8
        for amount in [uSpans.count, vSpans.count, vSpans.count] {
            let next = metadataCount.addingReportingOverflow(amount)
            guard !next.overflow else { throw Self.failure(.resourceLimitExceeded, tolerance, "Green metadata count overflowed.") }
            metadataCount = next.partialValue
        }
        try consume(metadataCount)
        for spans in [uSpans, vSpans] {
            for index in spans.indices {
                try consume(3)
                guard spans[index].lower.isFinite, spans[index].upper.isFinite,
                      spans[index].upper > spans[index].lower,
                      index == 0 || spans[index - 1].upper == spans[index].lower else {
                    throw Self.failure(.topologyFailure, tolerance, "Green preparation requires a complete contiguous native cover.")
                }
            }
        }
        var prepared: [Band] = []
        prepared.reserveCapacity(vSpans.count)
        var cursor = 0
        for vSpan in vSpans {
            try CurrentTaskCancellationChecker().checkCancellation()
            try consume(1)
            let vWidth = Interval.exact(vSpan.upper) - .exact(vSpan.lower)
            guard vWidth.lower > 0 else { throw Self.failure(.topologyFailure, tolerance, "Green preparation has a degenerate V chart.") }
            var prefix: [Interval] = []
            var row: [Panel] = []
            try consume(uSpans.count)
            row.reserveCapacity(uSpans.count)
            for uSpan in uSpans {
                try CurrentTaskCancellationChecker().checkCancellation()
                try consume(5)
                let input = panels[cursor]; cursor += 1
                try consume(input.fluxCoefficients.count)
                guard input.uSpan == uSpan, input.vSpan == vSpan,
                      !input.fluxCoefficients.isEmpty,
                      let width = input.fluxCoefficients.first?.count, width > 0,
                      input.fluxCoefficients.allSatisfy({ $0.count == width }) else {
                    throw Self.failure(.topologyFailure, tolerance, "Green preparation requires every ordered original panel exactly once.")
                }
                if prefix.isEmpty {
                    try consume(input.fluxCoefficients.count)
                    prefix = Array(repeating: .exact(0), count: input.fluxCoefficients.count)
                }
                guard prefix.count == input.fluxCoefficients.count else {
                    throw Self.failure(.unsupportedCapability, tolerance, "Green prefixes require matching native V degrees.")
                }
                var coefficients: [[Interval]] = []
                try consume(input.fluxCoefficients.count)
                coefficients.reserveCapacity(input.fluxCoefficients.count)
                for index in input.fluxCoefficients.indices {
                    let values = input.fluxCoefficients[index]
                    let capacity = width.addingReportingOverflow(1)
                    guard !capacity.overflow else { throw Self.failure(.resourceLimitExceeded, tolerance, "Green coefficient capacity overflowed.") }
                    try consume(capacity.partialValue)
                    try consume(1)
                    var primitive = [prefix[index] / vWidth]
                    primitive.reserveCapacity(capacity.partialValue)
                    var integral = Interval.exact(0)
                    for value in values {
                        try consume(4)
                        integral = integral + value / .exact(Double(width))
                        primitive.append((prefix[index] + integral) / vWidth)
                    }
                    try consume(1)
                    prefix[index] = prefix[index] + integral
                    coefficients.append(primitive)
                }
                row.append(Panel(uSpan: uSpan, coefficients: coefficients))
            }
            // At a closed U knot both incident originals enclose the same primitive value.
            var anchor: [Interval] = []
            try consume(row.count)
            for panel in row where uBase >= panel.uSpan.lower && uBase <= panel.uSpan.upper {
                try consume(5)
                let coordinate = (Interval.exact(uBase) - .exact(panel.uSpan.lower)) /
                    (Interval.exact(panel.uSpan.upper) - .exact(panel.uSpan.lower))
                guard let normalized = Self.intersection(coordinate, Self.unit) else {
                    throw Self.failure(.topologyFailure, tolerance, "Green base left its native U chart.")
                }
                if anchor.isEmpty {
                    try consume(panel.coefficients.count)
                    anchor = Array(repeating: .exact(0), count: panel.coefficients.count)
                    for i in anchor.indices { anchor[i] = try Self.range(panel.coefficients[i], at: normalized, tolerance: tolerance, consume: consume) }
                } else {
                    for i in anchor.indices {
                        let candidate = try Self.range(panel.coefficients[i], at: normalized, tolerance: tolerance, consume: consume)
                        try consume(2)
                        anchor[i] = Self.hull(anchor[i], candidate)
                    }
                }
            }
            guard !anchor.isEmpty else { throw Self.failure(.topologyFailure, tolerance, "Green base has no owning panel.") }
            try consume(row.count)
            var anchored: [Panel] = []
            anchored.reserveCapacity(row.count)
            for panel in row {
                try consume(panel.coefficients.count)
                var net: [[Interval]] = []
                for i in panel.coefficients.indices {
                    try consume(panel.coefficients[i].count)
                    var values: [Interval] = []
                    values.reserveCapacity(panel.coefficients[i].count)
                    for value in panel.coefficients[i] {
                        try consume(1)
                        let result = value - anchor[i]
                        guard result.lower.isFinite, result.upper.isFinite else {
                            throw Self.failure(.resourceLimitExceeded, tolerance, "Green coefficients exceeded finite arithmetic.")
                        }
                        values.append(result)
                    }
                    net.append(values)
                }
                anchored.append(Panel(uSpan: panel.uSpan, coefficients: net))
            }
            prepared.append(Band(vSpan: vSpan, panels: anchored))
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        self.source = source; self.reference = reference; self.tolerance = tolerance
        self.uBase = uBase; self.uSpans = uSpans; self.vSpans = vSpans; bands = prepared
        self.field = field
    }

    func range(overClosedUV u: Interval, v: Interval) throws -> Interval {
        try validate(u: u, v: v)
        var result: Interval?
        for band in bands where v.lower <= band.vSpan.upper && v.upper >= band.vSpan.lower {
            let y = try normalized(v, in: band.vSpan)
            for panel in band.panels where u.lower <= panel.uSpan.upper && u.upper >= panel.uSpan.lower {
                let x = try normalized(u, in: panel.uSpan)
                let values = try panel.coefficients.map { try Self.range($0, at: x, tolerance: tolerance) }
                let value = try Self.range(values, at: y, tolerance: tolerance)
                result = result.map { Self.hull($0, value) } ?? value
            }
        }
        guard let result else { throw Self.failure(.topologyFailure, tolerance, "Green range lost its original closed cover.") }
        return result
    }

    func directionalJet(u: Jet, v: Jet, uSpan: Span, vSpan: Span) throws -> Jet {
        try validate(u: u.value, v: v.value)
        guard u.value.lower >= uSpan.lower, u.value.upper <= uSpan.upper,
              v.value.lower >= vSpan.lower, v.value.upper <= vSpan.upper,
              let band = bands.first(where: { $0.vSpan == vSpan }),
              let panel = band.panels.first(where: { $0.uSpan == uSpan }) else {
            throw Self.failure(.topologyFailure, tolerance, "Green derivative requires one retained owning native panel.")
        }
        var x = try (u - .constant(uSpan.lower)).divided(by: .constant(.exact(uSpan.upper) - .exact(uSpan.lower)), tolerance: tolerance)
        var y = try (v - .constant(vSpan.lower)).divided(by: .constant(.exact(vSpan.upper) - .exact(vSpan.lower)), tolerance: tolerance)
        guard let clippedX = Self.intersection(x.value, Self.unit), let clippedY = Self.intersection(y.value, Self.unit) else {
            throw Self.failure(.topologyFailure, tolerance, "Green derivative left its native chart.")
        }
        x.coefficients[0] = clippedX; y.coefficients[0] = clippedY
        let rows = panel.coefficients.map { Self.jet($0.map(Jet.constant), at: x) }
        return Self.jet(rows, at: y)
    }

    private func validate(u: Interval, v: Interval) throws {
        guard u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite,
              u.lower <= u.upper, v.lower <= v.upper,
              u.lower >= uSpans[0].lower, u.upper <= uSpans[uSpans.count - 1].upper,
              v.lower >= vSpans[0].lower, v.upper <= vSpans[vSpans.count - 1].upper else {
            throw Self.failure(.invalidInput, tolerance, "Green query requires its original closed domain.")
        }
    }
    private func normalized(_ value: Interval, in span: Span) throws -> Interval {
        let clipped = Interval(lower: max(value.lower, span.lower), upper: min(value.upper, span.upper))
        let result = (clipped - .exact(span.lower)) / (.exact(span.upper) - .exact(span.lower))
        guard let unit = Self.intersection(result, Self.unit) else { throw Self.failure(.topologyFailure, tolerance, "Green range left an incident chart.") }
        return unit
    }
    private static func range(_ coefficients: [Interval], at parameter: Interval, tolerance: ModelingTolerance,
                              consume: (Int) throws -> Void = { _ in }) throws -> Interval {
        guard !coefficients.isEmpty else { throw failure(.topologyFailure, tolerance, "Green range has no original coefficients.") }
        try consume(coefficients.count)
        var level = coefficients
        try consume(1)
        let complement = Interval.exact(1) - parameter
        while level.count > 1 {
            for i in 0..<(level.count - 1) {
                try consume(3)
                level[i] = level[i] * complement + level[i + 1] * parameter
            }
            level.removeLast()
        }
        try consume(coefficients.count)
        var originalHull = coefficients[0]
        for coefficient in coefficients.dropFirst() { originalHull = hull(originalHull, coefficient) }
        guard let value = intersection(level[0], originalHull), value.lower.isFinite, value.upper.isFinite else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance, message: "Green polynomial enclosure cannot intersect its original coefficient hull.")
        }
        return value
    }
    private static let unit = Interval(lower: 0, upper: 1)
    private static func intersection(_ lhs: Interval, _ rhs: Interval) -> Interval? {
        let lower = max(lhs.lower, rhs.lower), upper = min(lhs.upper, rhs.upper)
        return lower <= upper ? Interval(lower: lower, upper: upper) : nil
    }
    private static func hull(_ lhs: Interval, _ rhs: Interval) -> Interval {
        Interval(lower: min(lhs.lower, rhs.lower), upper: max(lhs.upper, rhs.upper))
    }
    private static func jet(_ coefficients: [Jet], at parameter: Jet) -> Jet {
        var level = coefficients
        let complement = Jet.constant(1) - parameter
        while level.count > 1 {
            for i in 0..<(level.count - 1) { level[i] = level[i] * complement + level[i + 1] * parameter }
            level.removeLast()
        }
        return level[0]
    }
    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
