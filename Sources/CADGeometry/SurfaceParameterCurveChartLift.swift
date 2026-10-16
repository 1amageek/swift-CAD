import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// A continuous endpoint lift of one pcurve into a surface chart's universal
/// cover. Geometry owns this contract because periodicity and parameter
/// singularities belong to the support surface, not to topology consumers.
package struct SurfaceParameterCurveChartLift: Hashable, Sendable {
    package let start: SurfaceParameter
    package let middle: SurfaceParameter
    package let end: SurfaceParameter
    package let visitsUSingularity: Bool
    private let samples: [SurfaceParameter]
    package let originalSource: SurfaceParameterCurve?
    package let originalSurface: Surface3D?
    package let originalSampleBounds: [SurfaceParameterBox]?

    fileprivate init(
        start: SurfaceParameter,
        middle: SurfaceParameter,
        end: SurfaceParameter,
        visitsUSingularity: Bool,
        samples: [SurfaceParameter],
        originalSource: SurfaceParameterCurve? = nil,
        originalSurface: Surface3D? = nil,
        originalSampleBounds: [SurfaceParameterBox]? = nil
    ) {
        self.start = start
        self.middle = middle
        self.end = end
        self.visitsUSingularity = visitsUSingularity
        self.samples = samples
        self.originalSource = originalSource
        self.originalSurface = originalSurface
        self.originalSampleBounds = originalSampleBounds
    }

    /// Interpolates numerical proposals; originalSampleBounds owns endpoint proof.
    package func parameter(
        atNormalizedFraction fraction: Double
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(atNormalizedFraction: fraction, using: &execution)
    }

    package func parameter(
        atNormalizedFraction fraction: Double
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        let clamped = min(max(fraction, 0.0), 1.0)
        guard clamped < 1.0 else { return end }
        let scaled = clamped * Double(samples.count - 1)
        let lowerIndex = min(Int(floor(scaled)), samples.count - 2)
        let local = scaled - Double(lowerIndex)
        let lower = samples[lowerIndex]
        let upper = samples[lowerIndex + 1]
        return SurfaceParameter(
            u: lower.u + (upper.u - lower.u) * local,
            v: lower.v + (upper.v - lower.v) * local
        )
    }

    /// Transports retained bounds when present; samples alone remain numerical proposals.
    package func translated(uShift: Double, vShift: Double) throws -> Self {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try translated(uShift: uShift, vShift: vShift, using: &execution)
    }

    package func translated(uShift: Double, vShift: Double,
        using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        guard uShift.isFinite, vShift.isFinite else {
            throw GeometryConversionError.invalidInput("Chart translation requires finite shifts.")
        }
        if let boxes = originalSampleBounds {
            guard let source = originalSource, let support = originalSurface,
                boxes.count == samples.count, boxes.count >= 3 else {
                throw GeometryConversionError.invalidInput("Original chart translation requires complete endpoint receipts.")
            }
            try OriginalCoefficientAllocation.reserve(count: boxes.count, of: SurfaceParameterBox.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: boxes.count, of: SurfaceParameter.self, using: &execution)
            var translatedBoxes: [SurfaceParameterBox] = []; translatedBoxes.reserveCapacity(boxes.count)
            var proposals: [SurfaceParameter] = []; proposals.reserveCapacity(boxes.count)
            for box in boxes {
                try execution.consumeWork(1)
                let originalU = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
                let u = uShift == 0 ? originalU : originalU + .exact(uShift)
                let originalV = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
                let v = vShift == 0 ? originalV : originalV + .exact(vShift)
                guard u.isFinite, v.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original translated chart endpoint enclosure is nonfinite.")
                }
                try translatedBoxes.append(.init(u: .init(lower: u.lower, upper: u.upper),
                    v: .init(lower: v.lower, upper: v.upper)))
                let proposal = SurfaceParameter(u: u.midpoint, v: v.midpoint)
                try proposal.validate(); proposals.append(proposal)
            }
            return .init(start: proposals[0], middle: proposals[proposals.count / 2],
                end: proposals[proposals.count - 1], visitsUSingularity: visitsUSingularity,
                samples: proposals, originalSource: .periodicTranslation(base: source, uShift: uShift, vShift: vShift),
                originalSurface: support, originalSampleBounds: translatedBoxes)
        }
        func translated(_ parameter: SurfaceParameter) -> SurfaceParameter {
            SurfaceParameter(u: parameter.u + uShift, v: parameter.v + vShift)
        }
        let proposals = try OriginalCoefficientAllocation.map(elements: samples, using: &execution) { value, _ in translated(value) }
        return .init(start: translated(start), middle: translated(middle), end: translated(end),
            visitsUSingularity: visitsUSingularity, samples: proposals,
            originalSource: originalSource.map { .periodicTranslation(base: $0, uShift: uShift, vShift: vShift) },
            originalSurface: originalSurface, originalSampleBounds: nil)
    }

}

package extension SurfaceParameterCurve {
    func continuousChartLift(
        on surface: Surface3D,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveChartLift {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try continuousChartLift(on: surface, maximumParameterFirstDerivativeMagnitude: maximumParameterFirstDerivativeMagnitude, tolerance: tolerance, using: &execution)
    }

    func continuousChartLift(
        on surface: Surface3D,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveChartLift {
        try execution.consumeWork(1)
        if maximumParameterFirstDerivativeMagnitude == nil {
            switch self {
            case let .certifiedAnalyticPair(curve):
                if let prepared = try curve.prepareParameterCellBounds(
                    tolerance: tolerance
                , using: &execution).continuousChartLift {
                    return prepared
                }
            case let .periodicTranslation(base, uShift, vShift):
                return try base.continuousChartLift(
                    on: surface,
                    tolerance: tolerance
                , using: &execution).translated(uShift: uShift, vShift: vShift, using: &execution)
            default:
                break
            }
        }
        return try continuousChartLift(
            topology: try SurfaceParameterTopology(surface: surface, using: &execution),
            maximumParameterFirstDerivativeMagnitude:
                maximumParameterFirstDerivativeMagnitude,
            tolerance: tolerance
        , using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded seam/unwrapper validation
    // consumes explicit original continuous UV endpoint laws and retained boxes.
    // Principal angular/implicit branch atlases still need original coverage
    // receipts before this facade can admit those additional chart families.
    func continuousChartLift(on surface: Surface3D, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution)
        throws -> SurfaceParameterCurveChartLift {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original chart lift requires remaining caller source admission.")
        }
        try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        try validateOriginalSource(on: surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        func admit(_ curve: SurfaceParameterCurve, _ depth: Int, using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            switch curve {
            case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation: return
            case .periodicTranslation(let base, _, _):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original chart translation exhausted source depth.") }
                try admit(base, depth - 1, using: &execution)
            case .originalAffineWord(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word chart exhausted source depth.") }
                try admit(image.source.parameterCurve, depth - 1, using: &execution)
            case .originalImage(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original image chart exhausted source depth.") }
                try admit(image.source.parameterCurve, depth - 1, using: &execution)
            case .offsetSurfaceImage(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset chart exhausted source depth.") }
                try admit(image.source, depth - 1, using: &execution)
            default:
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original continuous UV branch coverage is not supplied by this chart family.")
            }
        }
        try admit(self, remainingSourceDepth, using: &execution)
        func bounds(_ fraction: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
            let jet = try OriginalParameterCurveHigherTaylor.enclosure(self, over: fraction,
                order: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            let u = try jet.u.coefficient(0, 0), v = try jet.v.coefficient(0, 0)
            return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
        }
        let whole = try bounds(.init(lower: 0, upper: 1), using: &execution)
        func visits(_ support: Surface3D, _ box: SurfaceParameterBox, _ depth: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
            try execution.consumeWork(1)
            switch support {
            case .analytic(.sphere):
                return box.v.lower <= -Double.pi * 0.5 || box.v.upper >= Double.pi * 0.5
            case .analytic(.cone): return box.v.lower <= 0 && box.v.upper >= 0
            case .procedural(.originalRevolution(let value)):
                return value.hasOriginalAxisEndpoint(atEnd: false) && box.v.lower <= 0
                    || value.hasOriginalAxisEndpoint(atEnd: true) && box.v.upper >= 1
            case .procedural(.originalAffineWord(let image)):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word singular chart exhausted source depth.") }
                return try visits(image.source, box, depth - 1, using: &execution)
            case .procedural(.originalImage(let image)):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original singular chart exhausted source depth.") }
                let native = try image.nativeBox(box, using: &execution)
                let original = try visits(image.source, native, depth - 1, using: &execution)
                guard !image.swapAxes || !original else {
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original permuted singular chart needs both angular-axis role receipts.")
                }
                return original
            case .procedural(.offset(let offset)):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset singular chart exhausted source depth.") }
                return try visits(offset.source, box, depth - 1, using: &execution)
            default: return false
            }
        }
        let singular = try visits(surface, whole, remainingSourceDepth, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 3, of: SurfaceParameter.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 3, of: SurfaceParameterBox.self, using: &execution)
        var samples: [SurfaceParameter] = [], boxes: [SurfaceParameterBox] = []
        samples.reserveCapacity(3); boxes.reserveCapacity(3)
        for index in 0..<3 {
            try execution.consumeWork(1)
            let fraction = Double(index) * 0.5
            let box = try bounds(.init(lower: fraction, upper: fraction), using: &execution)
            let u = box.u.midpoint, v = box.v.midpoint
            guard u.isFinite, v.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Original chart endpoint representative is nonfinite.")
            }
            samples.append(.init(u: u, v: v)); boxes.append(box)
        }
        return .init(start: samples[0], middle: samples[1], end: samples[2],
            visitsUSingularity: singular, samples: samples, originalSource: self,
            originalSurface: surface, originalSampleBounds: boxes)
    }

    func continuousChartLift(
        topology: SurfaceParameterTopology,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveChartLift {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try continuousChartLift(topology: topology, maximumParameterFirstDerivativeMagnitude: maximumParameterFirstDerivativeMagnitude, tolerance: tolerance, using: &execution)
    }


    func continuousChartLift(
        topology: SurfaceParameterTopology,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveChartLift {
        try execution.consumeWork(1)
        try tolerance.validate()
        let derivativeBound: Double?
        if let maximumParameterFirstDerivativeMagnitude {
            derivativeBound = maximumParameterFirstDerivativeMagnitude
        } else if topology.uPeriod != nil || topology.vPeriod != nil {
            derivativeBound = try intrinsicMaximumParameterFirstDerivativeMagnitude(
                tolerance: tolerance
            , using: &execution)
        } else {
            derivativeBound = nil
        }
        let subdivisions = try Self.chartLiftSubdivisionCount(
            topology: topology,
            maximumParameterFirstDerivativeMagnitude: derivativeBound,
            tolerance: tolerance
        )
        let sampleCount = try exactScalarCount(subdivisions, 1, multiply: false)
        try OriginalCoefficientAllocation.reserve(count: sampleCount, of: SurfaceParameter.self, using: &execution)
        var samples: [SurfaceParameter] = []
        samples.reserveCapacity(sampleCount)
        for index in 0...subdivisions {
            try execution.consumeWork(1)
            samples.append(try parameter(
                atNormalizedFraction: Double(index) / Double(subdivisions),
                tolerance: tolerance
            , using: &execution))
        }
        guard let start = samples.first else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A surface-parameter curve lift produced no chart samples."
            )
        }
        var end = start
        var middle = start
        try OriginalCoefficientAllocation.reserve(count: samples.count, of: SurfaceParameter.self, using: &execution)
        var liftedSamples: [SurfaceParameter] = []; liftedSamples.reserveCapacity(samples.count)
        liftedSamples.append(start)
        var visitsUSingularity = topology.isUSingular(
            start,
            tolerance: tolerance
        )
        for index in 1..<samples.count {
            try execution.consumeWork(1)
            let previous = samples[index - 1]
            let current = samples[index]
            let crossesUSingularity = topology.isUSingular(
                previous,
                tolerance: tolerance
            ) || topology.isUSingular(
                current,
                tolerance: tolerance
            )
            visitsUSingularity = visitsUSingularity || crossesUSingularity
            if crossesUSingularity == false {
                end.u += try Self.continuousPeriodicDelta(
                    from: previous.u,
                    to: current.u,
                    period: topology.uPeriod,
                    tolerance: tolerance
                )
            }
            end.v += try Self.continuousPeriodicDelta(
                from: previous.v,
                to: current.v,
                period: topology.vPeriod,
                tolerance: tolerance
            )
            liftedSamples.append(end)
            if index == subdivisions / 2 {
                middle = end
            }
        }
        return SurfaceParameterCurveChartLift(
            start: start,
            middle: middle,
            end: end,
            visitsUSingularity: visitsUSingularity,
            samples: liftedSamples
        )
    }

    private func intrinsicMaximumParameterFirstDerivativeMagnitude(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        switch self {
        case let .affine(_, direction, start, end):
            return (hypot(direction.x, direction.y) * abs(end - start)).nextUp
        case let .constantU(_, vStart, vEnd):
            return abs(vEnd - vStart).nextUp
        case let .constantV(_, uStart, uEnd):
            return abs(uEnd - uStart).nextUp
        case let .harmonic(_, cosine, sine, start, end):
            let uAmplitude = hypot(cosine.x, sine.x).nextUp
            let vAmplitude = hypot(cosine.y, sine.y).nextUp
            return (hypot(uAmplitude, vAmplitude) * abs(end - start)).nextUp
        case let .polyline(points):
            var totalLength = 0.0
            for index in 1..<points.count {
                try execution.consumeWork(1)
                totalLength = (totalLength + hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                ).nextUp).nextUp
            }
            return totalLength
        case let .originalBSplineContinuation(curve):
            let jet = try curve.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution)
            return hypot(jet.u.derivativeU.absoluteUpperBound, jet.v.derivativeU.absoluteUpperBound).nextUp
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(
                tolerance: tolerance
            , using: &execution)
            guard case let .closed(lower, upper) = curve.domain,
                  patches.isEmpty == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A continuous chart lift requires a bounded non-empty B-spline pcurve."
                )
            }
            let domainWidth = upper - lower
            var maximumU = 0.0
            var maximumV = 0.0
            for patch in patches {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &execution)
                let x = try OriginalCoefficientAllocation.map(elements: patch.controlPoints, using: &execution) { point, _ in point.x }
                let y = try OriginalCoefficientAllocation.map(elements: patch.controlPoints, using: &execution) { point, _ in point.y }
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [x, y],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                , using: &execution)
                maximumU = max(
                    maximumU,
                    (bound.first[0] * domainWidth).nextUp
                )
                maximumV = max(
                    maximumV,
                    (bound.first[1] * domainWidth).nextUp
                )
            }
            return hypot(maximumU, maximumV).nextUp
        case let .originalAffineWord(image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else { return nil }
            return hypot(jet.u.derivativeU.absoluteUpperBound, jet.v.derivativeU.absoluteUpperBound).nextUp
        case let .originalImage(image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else { return nil }
            return hypot(jet.u.derivativeU.absoluteUpperBound, jet.v.derivativeU.absoluteUpperBound).nextUp
        case let .offsetSurfaceImage(image):
            return try image.source
                .intrinsicMaximumParameterFirstDerivativeMagnitude(
                    tolerance: tolerance
                , using: &execution)
        case let .periodicTranslation(base, _, _):
            return try base.intrinsicMaximumParameterFirstDerivativeMagnitude(
                tolerance: tolerance
            , using: &execution)
        case let .certifiedImplicit(curve):
            return try Self.certifiedImplicitFirstDerivativeMagnitude(
                curve,
                tolerance: tolerance
            , using: &execution)
        case let .certifiedAnalyticImplicit(curve):
            return try Self.certifiedAnalyticImplicitFirstDerivativeMagnitude(
                curve,
                tolerance: tolerance
            , using: &execution)
        case .sphericalGreatCircle, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
            // These curve owners either return an already continuous chart
            // representative or restrict traversal to one analytic turn. The
            // general torus-torus owner supplies its stronger prepared lift.
            return nil
        }
    }

    private static func certifiedImplicitFirstDerivativeMagnitude(
        _ curve: CertifiedImplicitSurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let intersection = curve.intersection
        let coordinateOffset = curve.role == .first ? 0 : 2
        var maximum = 0.0
        for cell in intersection.cells {
            try execution.consumeWork(1)
            let derivatives = try cell.parameterDerivativeBounds(
                firstSurface: intersection.firstSurface,
                secondSurface: intersection.secondSurface,
                tolerance: tolerance
            , using: &execution)
            guard derivatives.count == 4 else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A certified implicit pcurve lost its parameter derivative enclosure."
                )
            }
            maximum = max(
                maximum,
                hypot(
                    maximumAbsolute(derivatives[coordinateOffset]),
                    maximumAbsolute(derivatives[coordinateOffset + 1])
                ).nextUp
            )
        }
        let normalizedScale = (
            Double(intersection.cells.count)
                * abs(curve.endFraction - curve.startFraction)
        ).nextUp
        return (maximum * normalizedScale).nextUp
    }

    private static func certifiedAnalyticImplicitFirstDerivativeMagnitude(
        _ curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let intersection = curve.intersection.implicitCurve
        var maximum = 0.0
        for cell in intersection.cells {
            try execution.consumeWork(1)
            let subcell = try cell.restrictedBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                firstSurface: intersection.firstSurface,
                secondSurface: intersection.secondSurface,
                tolerance: tolerance
            , using: &execution)
            let enclosure = try curve.parameterEnclosure(
                for: subcell,
                tolerance: tolerance
            , using: &execution)
            maximum = max(
                maximum,
                hypot(
                    maximumAbsolute(enclosure.uDerivative),
                    maximumAbsolute(enclosure.vDerivative)
                ).nextUp
            )
        }
        let normalizedScale = (
            Double(intersection.cells.count)
                * abs(curve.endFraction - curve.startFraction)
        ).nextUp
        return (maximum * normalizedScale).nextUp
    }

    private static func maximumAbsolute(_ interval: ScalarInterval) -> Double {
        max(abs(interval.lower), abs(interval.upper)).nextUp
    }

    private static func chartLiftSubdivisionCount(
        topology: SurfaceParameterTopology,
        maximumParameterFirstDerivativeMagnitude: Double?,
        tolerance: ModelingTolerance
    ) throws -> Int {
        guard let maximumParameterFirstDerivativeMagnitude else { return 16 }
        guard maximumParameterFirstDerivativeMagnitude.isFinite,
              maximumParameterFirstDerivativeMagnitude >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: maximumParameterFirstDerivativeMagnitude,
                tolerance: tolerance,
                message: "A continuous chart lift requires a finite nonnegative parameter derivative bound."
            )
        }
        let minimumPeriod: Double
        switch (topology.uPeriod, topology.vPeriod) {
        case let (.some(u), .some(v)): minimumPeriod = min(u, v)
        case let (.some(u), .none): minimumPeriod = u
        case let (.none, .some(v)): minimumPeriod = v
        case (.none, .none): return 16
        }
        guard minimumPeriod.isFinite, minimumPeriod > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                residual: minimumPeriod,
                tolerance: tolerance,
                message: "A periodic surface chart requires a finite positive period."
            )
        }
        let requiredCount = ceil(
            maximumParameterFirstDerivativeMagnitude
                / (minimumPeriod * 0.25)
        )
        guard requiredCount.isFinite, requiredCount <= 65_536.0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: requiredCount,
                tolerance: tolerance,
                message: "A continuous chart lift exceeded its certified sampling budget."
            )
        }
        let certifiedCount = max(16, Int(requiredCount))
        // Keeping the subdivision count even makes the stored middle sample
        // exactly represent t = 0.5 instead of a neighboring sample.
        return certifiedCount.isMultiple(of: 2)
            ? certifiedCount
            : certifiedCount + 1
    }

    private static func continuousPeriodicDelta(
        from start: Double,
        to end: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let period else { return end - start }
        var delta = (end - start).truncatingRemainder(dividingBy: period)
        if delta > period * 0.5 {
            delta -= period
        } else if delta < -period * 0.5 {
            delta += period
        }
        guard abs(abs(delta) - period * 0.5)
            > max(tolerance.distance, tolerance.angle) else {
            throw KernelError(
                phase: .geometry,
                code: .classificationFailure,
                residual: abs(delta),
                tolerance: tolerance,
                message: "A surface-parameter curve contains an ambiguous half-period chart step."
            )
        }
        return delta
    }
}
