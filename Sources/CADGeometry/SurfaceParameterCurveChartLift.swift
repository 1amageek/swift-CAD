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
    ) -> SurfaceParameter {
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

    /// Preserves original endpoint enclosures; caller proves period-lattice admission separately.
    package func translated(uShift: Double, vShift: Double,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> Self {
        guard uShift.isFinite, vShift.isFinite, let source = originalSource,
            let support = originalSurface, let boxes = originalSampleBounds,
            boxes.count == samples.count, boxes.count >= 3 else {
            throw GeometryConversionError.invalidInput("Bounded chart translation requires finite shifts and original endpoint receipts.")
        }
        try consumeWork()
        try OriginalCoefficientAllocation.reserve(count: boxes.count, of: SurfaceParameterBox.self,
            consumeStorage: consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: boxes.count, of: SurfaceParameter.self,
            consumeStorage: consumeStorage)
        var translatedBoxes: [SurfaceParameterBox] = []; translatedBoxes.reserveCapacity(boxes.count)
        var proposals: [SurfaceParameter] = []; proposals.reserveCapacity(boxes.count)
        for box in boxes {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
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

    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy chart consumers use numerical
    // translation proposals. This overload cannot preserve an original endpoint
    // proof without fallible outward bounds and caller accounting; bounded
    // consumers must use the explicit work/storage translation overload.
    package func translated(
        uShift: Double,
        vShift: Double
    ) -> SurfaceParameterCurveChartLift {
        func translated(_ parameter: SurfaceParameter) -> SurfaceParameter {
            SurfaceParameter(
                u: parameter.u + uShift,
                v: parameter.v + vShift
            )
        }
        return SurfaceParameterCurveChartLift(
            start: translated(start),
            middle: translated(middle),
            end: translated(end),
            visitsUSingularity: visitsUSingularity,
            samples: samples.map(translated),
            originalSource: originalSource.map { .periodicTranslation(base: $0, uShift: uShift, vShift: vShift) },
            originalSurface: originalSurface,
            originalSampleBounds: nil
        )
    }
}

package extension SurfaceParameterCurve {
    func continuousChartLift(
        on surface: Surface3D,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveChartLift {
        if maximumParameterFirstDerivativeMagnitude == nil {
            switch self {
            case let .certifiedAnalyticPair(curve):
                if let prepared = try curve.prepareParameterCellBounds(
                    tolerance: tolerance
                ).continuousChartLift {
                    return prepared
                }
            case let .periodicTranslation(base, uShift, vShift):
                return try base.continuousChartLift(
                    on: surface,
                    tolerance: tolerance
                ).translated(uShift: uShift, vShift: vShift)
            default:
                break
            }
        }
        return try continuousChartLift(
            topology: SurfaceParameterTopology(surface: surface),
            maximumParameterFirstDerivativeMagnitude:
                maximumParameterFirstDerivativeMagnitude,
            tolerance: tolerance
        )
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded seam/unwrapper validation
    // consumes explicit original continuous UV endpoint laws and retained boxes.
    // Principal angular/implicit branch atlases and lower query temporary bytes
    // must be connected before this facade claims all legacy chart families.
    func continuousChartLift(on surface: Surface3D, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?,
        maximumAlgebraicDepth: Int? = nil)
        throws -> SurfaceParameterCurveChartLift {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original chart lift requires remaining caller source admission.")
        }
        try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try validateOriginalSource(on: surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        func admit(_ curve: SurfaceParameterCurve, _ depth: Int) throws {
            try consumeWork()
            switch curve {
            case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation: return
            case .periodicTranslation(let base, _, _):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original chart translation exhausted source depth.") }
                try admit(base, depth - 1)
            case .originalAffineWord(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word chart exhausted source depth.") }
                try admit(image.source.parameterCurve, depth - 1)
            case .originalImage(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original image chart exhausted source depth.") }
                try admit(image.source.parameterCurve, depth - 1)
            case .offsetSurfaceImage(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset chart exhausted source depth.") }
                try admit(image.source, depth - 1)
            default:
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original continuous UV branch coverage is not supplied by this chart family.")
            }
        }
        try admit(self, remainingSourceDepth)
        func bounds(_ fraction: ScalarInterval) throws -> SurfaceParameterBox {
            let jet = try OriginalParameterCurveHigherTaylor.enclosure(self, over: fraction,
                order: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            let u = try jet.u.coefficient(0, 0), v = try jet.v.coefficient(0, 0)
            return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
        }
        let whole = try bounds(.init(lower: 0, upper: 1))
        func visits(_ support: Surface3D, _ box: SurfaceParameterBox, _ depth: Int) throws -> Bool {
            try consumeWork()
            switch support {
            case .analytic(.sphere):
                return box.v.lower <= -Double.pi * 0.5 || box.v.upper >= Double.pi * 0.5
            case .analytic(.cone): return box.v.lower <= 0 && box.v.upper >= 0
            case .procedural(.originalRevolution(let value)):
                return value.hasOriginalAxisEndpoint(atEnd: false) && box.v.lower <= 0
                    || value.hasOriginalAxisEndpoint(atEnd: true) && box.v.upper >= 1
            case .procedural(.originalAffineWord(let image)):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word singular chart exhausted source depth.") }
                return try visits(image.source, box, depth - 1)
            case .procedural(.originalImage(let image)):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original singular chart exhausted source depth.") }
                let native = try image.nativeBox(box, consumeWork: consumeWork)
                let original = try visits(image.source, native, depth - 1)
                guard !image.swapAxes || !original else {
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original permuted singular chart needs both angular-axis role receipts.")
                }
                return original
            case .procedural(.offset(let offset)):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset singular chart exhausted source depth.") }
                return try visits(offset.source, box, depth - 1)
            default: return false
            }
        }
        let singular = try visits(surface, whole, remainingSourceDepth)
        try OriginalCoefficientAllocation.reserve(count: 3, of: SurfaceParameter.self, consumeStorage: consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: 3, of: SurfaceParameterBox.self, consumeStorage: consumeStorage)
        var samples: [SurfaceParameter] = [], boxes: [SurfaceParameterBox] = []
        samples.reserveCapacity(3); boxes.reserveCapacity(3)
        for index in 0..<3 {
            try consumeWork()
            let fraction = Double(index) * 0.5
            let box = try bounds(.init(lower: fraction, upper: fraction))
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
        try tolerance.validate()
        let derivativeBound: Double?
        if let maximumParameterFirstDerivativeMagnitude {
            derivativeBound = maximumParameterFirstDerivativeMagnitude
        } else if topology.uPeriod != nil || topology.vPeriod != nil {
            derivativeBound = try intrinsicMaximumParameterFirstDerivativeMagnitude(
                tolerance: tolerance
            )
        } else {
            derivativeBound = nil
        }
        let subdivisions = try Self.chartLiftSubdivisionCount(
            topology: topology,
            maximumParameterFirstDerivativeMagnitude: derivativeBound,
            tolerance: tolerance
        )
        var samples: [SurfaceParameter] = []
        samples.reserveCapacity(subdivisions + 1)
        for index in 0...subdivisions {
            samples.append(try parameter(
                atNormalizedFraction: Double(index) / Double(subdivisions),
                tolerance: tolerance
            ))
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
        var liftedSamples = [start]
        liftedSamples.reserveCapacity(samples.count)
        var visitsUSingularity = topology.isUSingular(
            start,
            tolerance: tolerance
        )
        for index in 1..<samples.count {
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
    ) throws -> Double? {
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
                totalLength = (totalLength + hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                ).nextUp).nextUp
            }
            return totalLength
        case let .originalBSplineContinuation(curve):
            let jet = try curve.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance)
            return hypot(jet.u.derivativeU.absoluteUpperBound, jet.v.derivativeU.absoluteUpperBound).nextUp
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(
                tolerance: tolerance
            )
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
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map({ $0.x }),
                        patch.controlPoints.map({ $0.y }),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
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
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) else { return nil }
            return hypot(jet.u.derivativeU.absoluteUpperBound, jet.v.derivativeU.absoluteUpperBound).nextUp
        case let .originalImage(image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) else { return nil }
            return hypot(jet.u.derivativeU.absoluteUpperBound, jet.v.derivativeU.absoluteUpperBound).nextUp
        case let .offsetSurfaceImage(image):
            return try image.source
                .intrinsicMaximumParameterFirstDerivativeMagnitude(
                    tolerance: tolerance
                )
        case let .periodicTranslation(base, _, _):
            return try base.intrinsicMaximumParameterFirstDerivativeMagnitude(
                tolerance: tolerance
            )
        case let .certifiedImplicit(curve):
            return try Self.certifiedImplicitFirstDerivativeMagnitude(
                curve,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(curve):
            return try Self.certifiedAnalyticImplicitFirstDerivativeMagnitude(
                curve,
                tolerance: tolerance
            )
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
    ) throws -> Double {
        let intersection = curve.intersection
        let coordinateOffset = curve.role == .first ? 0 : 2
        var maximum = 0.0
        for cell in intersection.cells {
            let derivatives = try cell.parameterDerivativeBounds(
                firstSurface: intersection.firstSurface,
                secondSurface: intersection.secondSurface,
                tolerance: tolerance
            )
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
    ) throws -> Double {
        let intersection = curve.intersection.implicitCurve
        var maximum = 0.0
        for cell in intersection.cells {
            let subcell = try cell.restrictedBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                firstSurface: intersection.firstSurface,
                secondSurface: intersection.secondSurface,
                tolerance: tolerance
            )
            let enclosure = try curve.parameterEnclosure(
                for: subcell,
                tolerance: tolerance
            )
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
        guard let minimumPeriod = [topology.uPeriod, topology.vPeriod]
            .compactMap({ $0 }).min() else {
            return 16
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
