import CADCore

/// A unique oriented normal proved over every original owning span of a collapsed boundary.
public struct OriginalUniquePoleNormalAuthority: Sendable {
    public let source: BSplineSurface3D
    public let boundary: SurfaceParameterBoundary
    public let tolerance: ModelingTolerance
    public let collapsedPoint: Point3D
    package let reference: [ExactRationalCoefficient]
    private let panels: [Panel]

    private struct Panel: Sendable {
        let span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
        let boundaryDomain: SurfaceParameterBox
        let normal: OriginalExactBSplinePoleNormal
    }

    private init(source: BSplineSurface3D, boundary: SurfaceParameterBoundary,
        tolerance: ModelingTolerance, collapsedPoint: Point3D,
        reference: [ExactRationalCoefficient], panels: [Panel]) {
        self.source = source; self.boundary = boundary; self.tolerance = tolerance
        self.collapsedPoint = collapsedPoint; self.reference = reference; self.panels = panels
    }

    package static func prepare<B: RationalAlgebraAdmitting>(source: BSplineSurface3D,
        boundary: SurfaceParameterBoundary, prepared: PreparedBSplineSurfaceDifferentialEncloser,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> Self? {
        try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Whole original pole normal needs the caller's native cover and depth allowance.")
        }
        let alongU = boundary == .uLower || boundary == .uUpper
        let collapsedDomain = alongU ? source.uDomain : source.vDomain
        let freeDomain = alongU ? source.vFundamentalDomain : source.uFundamentalDomain
        guard case .closed(let minimum, let maximum) = collapsedDomain,
            case .closed(let freeMinimum, let freeMaximum) = freeDomain else { return nil }
        let station = boundary == .uLower || boundary == .vLower ? minimum : maximum
        let fixed = try ScalarInterval(lower: station, upper: station)
        let free = try ScalarInterval(lower: freeMinimum, upper: freeMaximum)
        let whole = SurfaceParameterBox(u: alongU ? fixed : free, v: alongU ? free : fixed)
        let pole = OriginalBSplinePoleNormal(surface: source, tolerance: tolerance, prepared: prepared)
        let direction: OriginalBSplinePoleNormal.Direction = alongU ? .constantU : .constantV
        let native = try prepared.originalNativeSpans(over: whole, tolerance: tolerance,
            maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: { try usage.consumeExactWork(1) })
        guard !native.isEmpty else {
            throw GeometryConversionError.invalidInput("Whole original pole normal has no original native cover.")
        }
        var panels: [Panel] = [], reference: [ExactRationalCoefficient]?
        var originalPoint: Point3D?
        let originalStation = try ExactRationalCoefficient.originalDouble(station, usage: &usage)
        for span in native {
            try usage.visitExactCell(depth: 0)
            let bounds = alongU ? span.vBounds : span.uBounds
            let low = max(free.lower, bounds.lower), high = min(free.upper, bounds.upper)
            if low >= high { continue }
            let interval = try ScalarInterval(lower: low, upper: high)
            let local = SurfaceParameterBox(u: alongU ? fixed : interval, v: alongU ? interval : fixed)
            try span.validate(on: source, over: local, tolerance: tolerance,
                consumeWork: { try usage.consumeExactWork(1) })
            let point: Point3D
            do {
                point = try pole.collapsedPoint(at: .init(u: alongU ? station : interval.midpoint,
                    v: alongU ? interval.midpoint : station), direction: direction,
                    consumeWork: { try usage.consumeExactWork(1) })
            } catch let error as KernelError where error.code == .invalidInput {
                // Only the original collapse recognizer's explicit noncollapse
                // result authorizes absence of this optional source proof.
                return nil
            }
            if let first = originalPoint {
                guard point == first else { return nil }
            } else { originalPoint = point }
            guard let normal = try pole.prepareExactPanelIfCollapsed(over: local, owning: span, usage: &usage),
                normal.coefficients.count == 3 else { return nil }
            if reference == nil {
                try usage.retainExactStorage(3)
                var value: [ExactRationalCoefficient] = []
                let u = try ExactRationalCoefficient.originalDouble(alongU ? station : interval.midpoint, usage: &usage)
                let v = try ExactRationalCoefficient.originalDouble(alongU ? interval.midpoint : station, usage: &usage)
                for polynomial in normal.coefficients { value.append(try polynomial.evaluated(atU: u, v: v, usage: &usage)) }
                guard value.contains(where: { !$0.isZero }) else { return nil }
                reference = value
            }
            guard let reference else { throw rationalAlgebraFailure("Original pole reference publication lost its source value.") }
            try usage.retainExactStorage(3)
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let cross = try normal.coefficients[a].scaled(by: reference[b], usage: &usage)
                    .subtracting(normal.coefficients[b].scaled(by: reference[a], usage: &usage), usage: &usage)
                    .restricted(alongU: alongU, station: originalStation, usage: &usage)
                guard cross.isZero else { return nil }
            }
            var dot = ExactBivariatePolynomial.zero
            for axis in 0..<3 {
                dot = try dot.adding(normal.coefficients[axis].scaled(by: reference[axis], usage: &usage), usage: &usage)
            }
            dot = try dot.restricted(alongU: alongU, station: originalStation, usage: &usage)
            guard !dot.isZero else { return nil }
            let lower = try ExactRationalCoefficient.originalDouble(low, usage: &usage)
            let upper = try ExactRationalCoefficient.originalDouble(high, usage: &usage)
            guard try ExactUnivariateRootIsolator().isolate(dot, lower: lower, upper: upper,
                maximumDepth: maximumSubdivisionDepth, usage: &usage).isEmpty else { return nil }
            let midpoint = try lower.adding(upper, usage: &usage)
                .divided(by: .natural(2, usage: &usage), usage: &usage)
            guard try dot.evaluated(atU: midpoint, v: .zero, usage: &usage).isPositive else { return nil }
            try usage.retainExactStorage(1)
            panels.append(Panel(span: span, boundaryDomain: local, normal: normal))
        }
        guard !panels.isEmpty, let reference, let originalPoint else { return nil }
        let sorting = try rationalAlgebraCount(panels.count, panels.count)
        try usage.consumeExactWork(sorting)
        // Insertion sorting exposes every actual comparison to the same ledger.
        for i in 1..<panels.count {
            var j = i
            while j > 0 {
                try usage.consumeExactWork(1)
                let a = alongU ? panels[j - 1].boundaryDomain.v : panels[j - 1].boundaryDomain.u
                let b = alongU ? panels[j].boundaryDomain.v : panels[j].boundaryDomain.u
                if a.lower <= b.lower { break }
                panels.swapAt(j - 1, j); j -= 1
            }
        }
        var covered = free.lower
        for panel in panels {
            try usage.consumeExactWork(1)
            let interval = alongU ? panel.boundaryDomain.v : panel.boundaryDomain.u
            guard interval.lower <= covered else {
                throw GeometryConversionError.invalidInput("Whole original pole normal cover has a source-domain gap.")
            }
            covered = max(covered, interval.upper)
        }
        guard covered == free.upper else {
            throw GeometryConversionError.invalidInput("Whole original pole normal cover does not reach the source endpoint.")
        }
        return Self(source: source, boundary: boundary, tolerance: tolerance,
            collapsedPoint: originalPoint, reference: reference, panels: panels)
    }

    package func normalTaylor<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        owning span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        throughOrder order: Int, usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let polynomials = try coefficients(over: box, owning: span, usage: &usage)
        let original = try OriginalPolynomialSurfaceTaylor.vector(polynomials: polynomials,
            over: box, throughOrder: order, tolerance: tolerance, usage: &usage)
        return try OriginalPolynomialSurfaceTaylor.normalized(original, usage: &usage)
    }

    package func coefficients<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        owning span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        try span.validate(on: source, over: box, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        for panel in panels {
            try usage.consumeExactWork(1)
            if panel.span.uSpanIndex == span.uSpanIndex, panel.span.vSpanIndex == span.vSpanIndex,
                panel.span.uCycle == span.uCycle, panel.span.vCycle == span.vCycle,
                panel.span.originalUTranslation == span.originalUTranslation,
                panel.span.originalVTranslation == span.originalVTranslation {
                return panel.normal.coefficients
            }
        }
        throw GeometryConversionError.invalidInput("Unique original pole normal query uses an unadmitted owning native span.")
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout SurfaceSilhouetteUsage) throws {
        try emitter.emit(.beginRecord(type: "wholeUniquePoleNormal"), usage: &usage)
        try emitter.field("source", usage: &usage); try emitter.write(Surface3D.bSpline(source), usage: &usage)
        try emitter.field("boundary", usage: &usage); try emitter.emit(.text(boundary.rawValue), usage: &usage)
        try emitter.field("tolerance", usage: &usage); try emitter.write(tolerance, usage: &usage)
        try emitter.field("collapsedPoint", usage: &usage); try emitter.write(collapsedPoint, usage: &usage)
        try emitter.field("reference", usage: &usage); try emitter.emit(.beginArray(count: reference.count), usage: &usage)
        for value in reference { try emitter.write(value, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("panels", usage: &usage); try emitter.emit(.beginArray(count: panels.count), usage: &usage)
        for panel in panels {
            try emitter.emit(.beginRecord(type: "originalPolePanel"), usage: &usage)
            try emitter.field("span", usage: &usage); try emitter.write(panel.span, usage: &usage)
            try emitter.field("boundaryDomain", usage: &usage); try emitter.write(panel.boundaryDomain, usage: &usage)
            try emitter.field("normal", usage: &usage); try emitter.write(panel.normal, usage: &usage)
            try emitter.emit(.endRecord, usage: &usage)
        }
        try emitter.emit(.endArray, usage: &usage); try emitter.emit(.endRecord, usage: &usage)
    }

}
