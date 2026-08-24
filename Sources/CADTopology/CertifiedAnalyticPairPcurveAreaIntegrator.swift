import CADCore
import CADGeometry
import Foundation

struct CertifiedAnalyticPairPcurveAreaIntegrator {
    private enum LocalProofFailure: Error {
        case intervalSingularity
        case periodicSeam
    }

    private struct Interval {
        let lower: Double
        let upper: Double

        static let zero = Interval(lower: 0.0, upper: 0.0)
        static let one = Interval(lower: 1.0, upper: 1.0)

        static func scalar(_ value: Double) -> Interval {
            guard value != 0.0 else { return .zero }
            return Interval(lower: value.nextDown, upper: value.nextUp)
        }

        var width: Double {
            (upper - lower).nextUp
        }

        var maximumAbsoluteValue: Double {
            max(abs(lower), abs(upper))
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

        func adding(_ other: Interval) -> Interval {
            Interval(
                lower: (lower + other.lower).nextDown,
                upper: (upper + other.upper).nextUp
            )
        }

        func subtracting(_ other: Interval) -> Interval {
            Interval(
                lower: (lower - other.upper).nextDown,
                upper: (upper - other.lower).nextUp
            )
        }

        func multiplied(by other: Interval) -> Interval {
            let lowerLower = lower * other.lower
            let lowerUpper = lower * other.upper
            let upperLower = upper * other.lower
            let upperUpper = upper * other.upper
            return Interval(
                lower: min(
                    min(lowerLower, lowerUpper),
                    min(upperLower, upperUpper)
                ).nextDown,
                upper: max(
                    max(lowerLower, lowerUpper),
                    max(upperLower, upperUpper)
                ).nextUp
            )
        }

        func scaled(by scalar: Double) -> Interval {
            guard scalar != 0.0 else { return .zero }
            let first = lower * scalar
            let second = upper * scalar
            return Interval(
                lower: min(first, second).nextDown,
                upper: max(first, second).nextUp
            )
        }

        func reciprocal() throws -> Interval {
            guard containsZero == false else {
                throw LocalProofFailure.intervalSingularity
            }
            return Interval(
                lower: (1.0 / upper).nextDown,
                upper: (1.0 / lower).nextUp
            )
        }

        func divided(by other: Interval) throws -> Interval {
            try multiplied(by: other.reciprocal())
        }

        func squareRoot() throws -> Interval {
            guard lower > 0.0 else {
                throw LocalProofFailure.intervalSingularity
            }
            return Interval(
                lower: sqrt(lower).nextDown,
                upper: sqrt(upper).nextUp
            )
        }

        func expanded(toInclude value: Double) -> Interval {
            Interval(
                lower: min(lower, value.nextDown),
                upper: max(upper, value.nextUp)
            )
        }
    }

    private struct Jet {
        static let order = 3
        var coefficients: [Interval]

        static func variable(_ interval: Interval) -> Jet {
            Jet(coefficients: [interval, .one, .zero, .zero])
        }

        static func constant(_ value: Double) -> Jet {
            Jet(coefficients: [.scalar(value), .zero, .zero, .zero])
        }

        static func constant(_ value: Interval) -> Jet {
            Jet(coefficients: [value, .zero, .zero, .zero])
        }

        static func fromCoefficients(_ coefficients: [Interval]) -> Jet {
            var result = Array(repeating: Interval.zero, count: order + 1)
            for index in 0..<min(coefficients.count, result.count) {
                result[index] = coefficients[index]
            }
            return Jet(coefficients: result)
        }

        func adding(_ other: Jet) -> Jet {
            Jet.fromCoefficients(zip(coefficients, other.coefficients).map { pair in
                pair.0.adding(pair.1)
            })
        }

        func subtracting(_ other: Jet) -> Jet {
            Jet.fromCoefficients(zip(coefficients, other.coefficients).map { pair in
                pair.0.subtracting(pair.1)
            })
        }

        func multiplied(by other: Jet) -> Jet {
            var result = Array(repeating: Interval.zero, count: Self.order + 1)
            for degree in 0...Self.order {
                var coefficient = Interval.zero
                for index in 0...degree {
                    coefficient = coefficient.adding(
                        coefficients[index].multiplied(by: other.coefficients[degree - index])
                    )
                }
                result[degree] = coefficient
            }
            return Jet(coefficients: result)
        }

        func scaled(by scalar: Double) -> Jet {
            Jet.fromCoefficients(coefficients.map { $0.scaled(by: scalar) })
        }

        func scaled(by scalar: Interval) -> Jet {
            Jet.fromCoefficients(coefficients.map { $0.multiplied(by: scalar) })
        }

        func derivative() -> Jet {
            Jet.fromCoefficients([
                coefficients[1],
                coefficients[2].scaled(by: 2.0),
                coefficients[3].scaled(by: 3.0),
                .zero,
            ])
        }

        func reciprocal() throws -> Jet {
            let inverseConstant = try coefficients[0].reciprocal()
            var result = Array(repeating: Interval.zero, count: Self.order + 1)
            result[0] = inverseConstant
            if Self.order > 0 {
                for degree in 1...Self.order {
                    var sum = Interval.zero
                    for index in 1...degree {
                        sum = sum.adding(
                            coefficients[index].multiplied(by: result[degree - index])
                        )
                    }
                    result[degree] = inverseConstant.multiplied(by: sum).scaled(by: -1.0)
                }
            }
            return Jet(coefficients: result)
        }

        func divided(by other: Jet) throws -> Jet {
            try multiplied(by: other.reciprocal())
        }

        func squareRoot() throws -> Jet {
            let rootConstant = try coefficients[0].squareRoot()
            let denominator = rootConstant.scaled(by: 2.0)
            var result = Array(repeating: Interval.zero, count: Self.order + 1)
            result[0] = rootConstant
            if Self.order > 0 {
                for degree in 1...Self.order {
                    var crossTerms = Interval.zero
                    if degree > 1 {
                        for index in 1..<degree {
                            crossTerms = crossTerms.adding(
                                result[index].multiplied(by: result[degree - index])
                            )
                        }
                    }
                    result[degree] = try coefficients[degree]
                        .subtracting(crossTerms)
                        .divided(by: denominator)
                }
            }
            return Jet(coefficients: result)
        }

        func sineAndCosine() -> (sine: Jet, cosine: Jet) {
            var sine = Array(repeating: Interval.zero, count: Self.order + 1)
            var cosine = Array(repeating: Interval.zero, count: Self.order + 1)
            sine[0] = Self.trigonometricBounds(coefficients[0], phase: 0.0)
            cosine[0] = Self.trigonometricBounds(
                coefficients[0],
                phase: Double.pi * 0.5
            )
            if Self.order > 0 {
                for degree in 1...Self.order {
                    var sineSum = Interval.zero
                    var cosineSum = Interval.zero
                    for index in 1...degree {
                        let derivativeCoefficient = coefficients[index].scaled(by: Double(index))
                        sineSum = sineSum.adding(
                            derivativeCoefficient.multiplied(by: cosine[degree - index])
                        )
                        cosineSum = cosineSum.adding(
                            derivativeCoefficient.multiplied(by: sine[degree - index])
                        )
                    }
                    sine[degree] = sineSum.scaled(by: 1.0 / Double(degree))
                    cosine[degree] = cosineSum.scaled(by: -1.0 / Double(degree))
                }
            }
            return (Jet(coefficients: sine), Jet(coefficients: cosine))
        }

        static func trigonometricBounds(
            _ interval: Interval,
            phase: Double
        ) -> Interval {
            let lower = interval.lower + phase
            let upper = interval.upper + phase
            guard upper - lower < 2.0 * Double.pi else {
                return Interval(lower: -1.0, upper: 1.0)
            }
            var values = [sin(lower), sin(upper)]
            let firstCriticalIndex = Int(ceil(
                (lower - Double.pi * 0.5) / Double.pi
            ))
            let lastCriticalIndex = Int(floor(
                (upper - Double.pi * 0.5) / Double.pi
            ))
            if firstCriticalIndex <= lastCriticalIndex {
                for index in firstCriticalIndex...lastCriticalIndex {
                    values.append(sin(Double.pi * 0.5 + Double(index) * Double.pi))
                }
            }
            return Interval(
                lower: (values.min() ?? -1.0).nextDown,
                upper: (values.max() ?? 1.0).nextUp
            )
        }
    }

    private struct BivariateJet {
        let value: Interval
        let u: Interval
        let v: Interval
        let uu: Interval
        let uv: Interval
        let vv: Interval

        static func constant(_ value: Interval) -> BivariateJet {
            BivariateJet(
                value: value,
                u: .zero,
                v: .zero,
                uu: .zero,
                uv: .zero,
                vv: .zero
            )
        }

        static func parameterU(_ value: Interval) -> BivariateJet {
            BivariateJet(
                value: value,
                u: .one,
                v: .zero,
                uu: .zero,
                uv: .zero,
                vv: .zero
            )
        }

        static func parameterV(_ value: Interval) -> BivariateJet {
            BivariateJet(
                value: value,
                u: .zero,
                v: .one,
                uu: .zero,
                uv: .zero,
                vv: .zero
            )
        }

        func adding(_ other: BivariateJet) -> BivariateJet {
            BivariateJet(
                value: value.adding(other.value),
                u: u.adding(other.u),
                v: v.adding(other.v),
                uu: uu.adding(other.uu),
                uv: uv.adding(other.uv),
                vv: vv.adding(other.vv)
            )
        }

        func subtracting(_ other: BivariateJet) -> BivariateJet {
            adding(other.scaled(by: -1.0))
        }

        func multiplied(by other: BivariateJet) -> BivariateJet {
            BivariateJet(
                value: value.multiplied(by: other.value),
                u: u.multiplied(by: other.value)
                    .adding(value.multiplied(by: other.u)),
                v: v.multiplied(by: other.value)
                    .adding(value.multiplied(by: other.v)),
                uu: uu.multiplied(by: other.value)
                    .adding(u.multiplied(by: other.u).scaled(by: 2.0))
                    .adding(value.multiplied(by: other.uu)),
                uv: uv.multiplied(by: other.value)
                    .adding(u.multiplied(by: other.v))
                    .adding(v.multiplied(by: other.u))
                    .adding(value.multiplied(by: other.uv)),
                vv: vv.multiplied(by: other.value)
                    .adding(v.multiplied(by: other.v).scaled(by: 2.0))
                    .adding(value.multiplied(by: other.vv))
            )
        }

        func scaled(by scalar: Double) -> BivariateJet {
            BivariateJet(
                value: value.scaled(by: scalar),
                u: u.scaled(by: scalar),
                v: v.scaled(by: scalar),
                uu: uu.scaled(by: scalar),
                uv: uv.scaled(by: scalar),
                vv: vv.scaled(by: scalar)
            )
        }

        func scaled(by scalar: Interval) -> BivariateJet {
            multiplied(by: .constant(scalar))
        }

        func sineAndCosine() -> (sine: BivariateJet, cosine: BivariateJet) {
            let sineValue = Jet.trigonometricBounds(value, phase: 0.0)
            let cosineValue = Jet.trigonometricBounds(
                value,
                phase: Double.pi * 0.5
            )
            let sine = BivariateJet(
                value: sineValue,
                u: cosineValue.multiplied(by: u),
                v: cosineValue.multiplied(by: v),
                uu: cosineValue.multiplied(by: uu)
                    .subtracting(sineValue.multiplied(by: u.multiplied(by: u))),
                uv: cosineValue.multiplied(by: uv)
                    .subtracting(sineValue.multiplied(by: u.multiplied(by: v))),
                vv: cosineValue.multiplied(by: vv)
                    .subtracting(sineValue.multiplied(by: v.multiplied(by: v)))
            )
            let cosine = BivariateJet(
                value: cosineValue,
                u: sineValue.multiplied(by: u).scaled(by: -1.0),
                v: sineValue.multiplied(by: v).scaled(by: -1.0),
                uu: sineValue.multiplied(by: uu).scaled(by: -1.0)
                    .subtracting(cosineValue.multiplied(by: u.multiplied(by: u))),
                uv: sineValue.multiplied(by: uv).scaled(by: -1.0)
                    .subtracting(cosineValue.multiplied(by: u.multiplied(by: v))),
                vv: sineValue.multiplied(by: vv).scaled(by: -1.0)
                    .subtracting(cosineValue.multiplied(by: v.multiplied(by: v)))
            )
            return (sine, cosine)
        }
    }

    private struct OneFormInterval {
        let du: Interval
        let dv: Interval
    }

    private struct BivariateOneForm {
        let du: BivariateJet
        let dv: BivariateJet
    }

    private struct Configuration {
        let planeOrigin: Point3D
        let planeNormal: Vector3D
        let planeBasisU: Vector3D
        let planeBasisV: Vector3D
        let torusCenter: Point3D
        let torusAxis: Vector3D
        let torusBasisU: Vector3D
        let torusBasisV: Vector3D
        let majorRadius: Double
        let minorRadius: Double
        let radialNormal: Vector3D
        let radialPerpendicular: Vector3D
        let radialNormalLength: Double
        let axialNormal: Double
        let centerDistance: Double
        let componentKind: CertifiedPlaneTorusIntersectionCurve.ComponentKind
        let lowerMinorAngle: Double
        let upperMinorAngle: Double

        var characteristicLength: Double {
            max(majorRadius + minorRadius, abs(centerDistance), 1.0)
        }
    }

    private struct GeometryJets {
        let along: Jet
        let across: Jet
        let height: Jet
        let minor: Jet
    }

    private struct GeometryRanges {
        let along: Interval
        let across: Interval
        let height: Interval
        let minor: Interval
    }

    private struct WorkItem {
        let lower: Double
        let upper: Double
        let depth: Int
        let bounds: SurfaceParameterAreaBounds
        let parameterStart: SurfaceParameter?
        let parameterMiddle: SurfaceParameter?
        let parameterEnd: SurfaceParameter?

        init(
            lower: Double,
            upper: Double,
            depth: Int,
            bounds: SurfaceParameterAreaBounds,
            parameterStart: SurfaceParameter? = nil,
            parameterMiddle: SurfaceParameter? = nil,
            parameterEnd: SurfaceParameter? = nil
        ) {
            self.lower = lower
            self.upper = upper
            self.depth = depth
            self.bounds = bounds
            self.parameterStart = parameterStart
            self.parameterMiddle = parameterMiddle
            self.parameterEnd = parameterEnd
        }

        var width: Double {
            bounds.width
        }
    }

    private struct WorkHeap {
        private(set) var storage: [WorkItem] = []

        var isEmpty: Bool { storage.isEmpty }
        var count: Int { storage.count }

        mutating func push(_ item: WorkItem) {
            storage.append(item)
            var index = storage.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard priority(storage[index]) > priority(storage[parent]) else { break }
                storage.swapAt(index, parent)
                index = parent
            }
        }

        mutating func popMaximum() -> WorkItem? {
            guard storage.isEmpty == false else { return nil }
            if storage.count == 1 { return storage.removeLast() }
            let result = storage[0]
            storage[0] = storage.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var largest = index
                if left < storage.count,
                   priority(storage[left]) > priority(storage[largest]) {
                    largest = left
                }
                if right < storage.count,
                   priority(storage[right]) > priority(storage[largest]) {
                    largest = right
                }
                guard largest != index else { break }
                storage.swapAt(index, largest)
                index = largest
            }
            return result
        }

        private func priority(_ item: WorkItem) -> Double {
            item.width.isFinite ? item.width : .infinity
        }
    }

    private enum GenericBoundaryIntegrand {
        case parameterArea(uShift: Double)
        case volume(TrimmedAnalyticSurfaceVolumeEvaluator.Integrand)
    }

    private let maximumSubdivisionDepth: Int
    private let maximumCellCount: Int

    init(
        maximumSubdivisionDepth: Int = 64,
        maximumCellCount: Int = 2_097_152
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
    }

    func fluxBounds(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
        try tolerance.validate()
        try curve.validate(
            on: curve.intersection.surface(for: curve.role),
            tolerance: tolerance
        )
        guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Analytic-pair flux integration requires a finite positive enclosure width."
            )
        }
        if case .cylinder = integrand {
            let result = try cylinderBoundaryBounds(
                for: curve,
                integrand: .volume(integrand),
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
            return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                lower: result.lower,
                upper: result.upper
            )
        }
        guard usesSpecializedPlaneTorusPath(curve, requireTorusRole: true),
              integrand.requiresNonzeroPeriodicReferenceGauge == false else {
            let result = try genericIntegralBounds(
                for: curve,
                integrand: .volume(integrand),
                usesPeriodicBoundaryGauge: integrand.usesPeriodicBoundaryGauge,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
            return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                lower: result.lower,
                upper: result.upper
            )
        }
        guard case .torus = integrand else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The specialized plane-torus flux path requires a torus integrand."
            )
        }
        let configuration = try makeConfiguration(curve: curve, tolerance: tolerance)
        guard !isPlaneRole(curve, configuration: configuration) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Plane analytic-pair flux must use the exact planar Green path."
            )
        }
        let period = 2.0 * Double.pi
        let lower = min(curve.startFraction, curve.endFraction) * period
        let upper = max(curve.startFraction, curve.endFraction) * period
        var breakpoints = [lower]
        if configuration.componentKind == .boundedMinorAngle,
           Double.pi > lower,
           Double.pi < upper {
            breakpoints.append(Double.pi)
        }
        breakpoints.append(upper)
        breakpoints.sort()
        func cellContribution(
            lower cellLower: Double,
            upper cellUpper: Double
        ) throws -> Interval {
            let envelope = try geometricFluxFallbackBounds(
                lower: cellLower,
                upper: cellUpper,
                curve: curve,
                configuration: configuration,
                integrand: integrand,
                tolerance: tolerance
            )
            let jetBounds: Interval
            do {
                jetBounds = try midpointFluxBounds(
                    lower: cellLower,
                    upper: cellUpper,
                    curve: curve,
                    configuration: configuration,
                    integrand: integrand,
                    tolerance: tolerance
                )
            } catch LocalProofFailure.intervalSingularity,
                    LocalProofFailure.periodicSeam {
                return envelope
            }
            // Both enclosures certify the same integral, so their overlap
            // does too: the geometric envelope wins on the square-root
            // shoulder, where interval jets cannot see the substitution's
            // cancellation, and the midpoint jets win in the interior.
            let lower = max(jetBounds.lower, envelope.lower)
            let upper = min(jetBounds.upper, envelope.upper)
            guard lower <= upper else {
                return jetBounds.upper - jetBounds.lower
                    <= envelope.upper - envelope.lower
                    ? jetBounds
                    : envelope
            }
            return Interval(lower: lower, upper: upper)
        }
        // Per-cell width budgets halve faster than a square-root endpoint
        // singularity can converge, so the proof refines the globally widest
        // cell until the summed enclosure width meets the request, mirroring
        // the certified area path.
        var heap = WorkHeap()
        for index in 1..<breakpoints.count {
            let segmentLower = breakpoints[index - 1]
            let segmentUpper = breakpoints[index]
            guard segmentUpper > segmentLower else { continue }
            let contribution = try cellContribution(
                lower: segmentLower,
                upper: segmentUpper
            )
            heap.push(WorkItem(
                lower: segmentLower,
                upper: segmentUpper,
                depth: 0,
                bounds: SurfaceParameterAreaBounds(
                    lower: contribution.lower,
                    upper: contribution.upper
                )
            ))
        }
        var totalWidth = outwardWidthSum(heap.storage)
        var subdivisionCount = 0
        while totalWidth > requestedWidth {
            guard let item = heap.popMaximum() else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Analytic-pair flux integration lost its active proof cells."
                )
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: item.width,
                    tolerance: tolerance,
                    message: "Analytic-pair flux integration exceeded its subdivision depth."
                )
            }
            guard heap.count + 2 <= maximumCellCount else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: Double(heap.count),
                    tolerance: tolerance,
                    message: "Analytic-pair flux integration exceeded its certified cell budget."
                )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Analytic-pair flux subdivision reached floating-point resolution."
                )
            }
            var childWidthSum = 0.0
            for (childLower, childUpper) in [
                (item.lower, midpoint),
                (midpoint, item.upper),
            ] {
                let contribution = try cellContribution(
                    lower: childLower,
                    upper: childUpper
                )
                let child = WorkItem(
                    lower: childLower,
                    upper: childUpper,
                    depth: item.depth + 1,
                    bounds: SurfaceParameterAreaBounds(
                        lower: contribution.lower,
                        upper: contribution.upper
                    )
                )
                childWidthSum = (childWidthSum + child.width).nextUp
                heap.push(child)
            }
            subdivisionCount += 1
            totalWidth = replacingWidthUpperBound(
                totalWidth,
                removing: item.width,
                addingUpperBound: childWidthSum
            )
            if subdivisionCount.nonzeroBitCount == 1 {
                // Geometric checkpoints bound accumulated roundoff while
                // keeping total heap scans linear in the final cell count.
                totalWidth = outwardWidthSum(heap.storage)
            }
        }
        let composed = CertifiedIntervalSummation.sum(
            heap.storage,
            bounds: \.bounds
        )
        let result = Interval(
            lower: composed.lower,
            upper: composed.upper
        )
        let oriented = curve.startFraction <= curve.endFraction ? result : result.scaled(by: -1.0)
        return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
            lower: oriented.lower,
            upper: oriented.upper
        )
    }

    func bounds(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        uShift: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        try tolerance.validate()
        try curve.validate(
            on: curve.intersection.surface(for: curve.role),
            tolerance: tolerance
        )
        guard uShift.isFinite,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair area integration requires finite positive options."
            )
        }
        if usesCylinderChart(curve) {
            return try cylinderBoundaryBounds(
                for: curve,
                integrand: .parameterArea(uShift: uShift),
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        }
        guard usesSpecializedPlaneTorusPath(curve, requireTorusRole: false) else {
            return try genericIntegralBounds(
                for: curve,
                integrand: .parameterArea(uShift: uShift),
                usesPeriodicBoundaryGauge: false,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        }
        let configuration = try makeConfiguration(curve: curve, tolerance: tolerance)
        let period = 2.0 * Double.pi
        let lower = min(curve.startFraction, curve.endFraction) * period
        let upper = max(curve.startFraction, curve.endFraction) * period
        var breakpoints = [lower]
        if configuration.componentKind == .boundedMinorAngle,
           Double.pi > lower,
           Double.pi < upper {
            breakpoints.append(Double.pi)
        }
        breakpoints.append(upper)
        breakpoints.sort()

        var heap = WorkHeap()
        for index in 1..<breakpoints.count {
            let segmentLower = breakpoints[index - 1]
            let segmentUpper = breakpoints[index]
            guard segmentUpper > segmentLower else { continue }
            heap.push(try makeWorkItem(
                lower: segmentLower,
                upper: segmentUpper,
                depth: 0,
                curve: curve,
                configuration: configuration,
                uShift: uShift,
                tolerance: tolerance
            ))
        }
        guard heap.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair area integration received an empty trim."
            )
        }

        let internalTargetWidth = (requestedWidth * 0.99).nextDown
        var totalWidth = outwardWidthSum(heap.storage)
        var subdivisionCount = 0
        while totalWidth > internalTargetWidth {
            guard let item = heap.popMaximum() else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Analytic-pair area integration lost its active proof cells."
                )
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Analytic-pair area integration exceeded its subdivision depth."
                )
            }
            guard heap.count + 2 <= maximumCellCount else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Analytic-pair area integration exceeded its certified cell budget."
                )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Analytic-pair \(curve.role.rawValue) pcurve subdivision reached floating-point resolution."
                )
            }
            let children = [
                try makeWorkItem(
                    lower: item.lower,
                    upper: midpoint,
                    depth: item.depth + 1,
                    curve: curve,
                    configuration: configuration,
                    uShift: uShift,
                    tolerance: tolerance
                ),
                try makeWorkItem(
                    lower: midpoint,
                    upper: item.upper,
                    depth: item.depth + 1,
                    curve: curve,
                    configuration: configuration,
                    uShift: uShift,
                    tolerance: tolerance
                ),
            ]
            for child in children { heap.push(child) }
            subdivisionCount += 1
            totalWidth = replacingWidthUpperBound(
                totalWidth,
                removing: item.width,
                addingFirst: children[0].width,
                second: children[1].width
            )
            if subdivisionCount.nonzeroBitCount == 1 {
                totalWidth = outwardWidthSum(heap.storage)
            }
            if totalWidth <= internalTargetWidth {
                totalWidth = outwardWidthSum(heap.storage)
            }
        }

        let result = CertifiedIntervalSummation.sum(
            heap.storage,
            bounds: \.bounds
        )
        guard result.width <= requestedWidth.nextUp else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: result.width,
                tolerance: tolerance,
                message: "Analytic-pair area cells did not compose to the requested enclosure."
            )
        }
        guard curve.startFraction <= curve.endFraction else {
            return SurfaceParameterAreaBounds(
                lower: (-result.upper).nextDown,
                upper: (-result.lower).nextUp
            )
        }
        return result
    }

    func periodicConeAreaBounds(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        try tolerance.validate()
        guard isConeSurface(curve.intersection.surface(for: curve.role)),
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Periodic cone parameter-area integration requires a cone pcurve and a finite positive enclosure width."
            )
        }
        return try genericIntegralBounds(
            for: curve,
            integrand: .parameterArea(uShift: 0.0),
            usesPeriodicBoundaryGauge: true,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
    }

    func parameterEnclosures(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        fromNormalizedFraction lowerFraction: Double = 0.0,
        toNormalizedFraction upperFraction: Double = 1.0,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try coordinateParameterEnclosures(
            for: curve,
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            maximumWidth: maximumWidth,
            requiresUWidth: true,
            tolerance: tolerance
        )
    }

    /// Certifies only the V-coordinate width while retaining an enclosing U
    /// interval. This is required at valid chart locations where U collapses
    /// or is locally indeterminate but a consumer's proof depends solely on V.
    func vParameterEnclosures(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        fromNormalizedFraction lowerFraction: Double = 0.0,
        toNormalizedFraction upperFraction: Double = 1.0,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try coordinateParameterEnclosures(
            for: curve,
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            maximumWidth: maximumWidth,
            requiresUWidth: false,
            tolerance: tolerance
        )
    }

    private func coordinateParameterEnclosures(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        maximumWidth: Double,
        requiresUWidth: Bool,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try tolerance.validate()
        try curve.validate(
            on: curve.intersection.surface(for: curve.role),
            tolerance: tolerance
        )
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction,
              maximumWidth.isFinite,
              maximumWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: upperFraction - lowerFraction,
                tolerance: tolerance,
                message: "Analytic-pair pcurve enclosure requires an ordered normalized range and a finite positive width."
            )
        }
        let boundedLower = min(max(lowerFraction, 0.0), 1.0)
        let boundedUpper = min(max(upperFraction, 0.0), 1.0)
        guard boundedUpper > boundedLower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: boundedUpper - boundedLower,
                tolerance: tolerance,
                message: "Analytic-pair pcurve enclosure range collapsed at its normalized domain boundary."
            )
        }
        guard usesSpecializedPlaneTorusPath(curve, requireTorusRole: false) else {
            return try genericParameterEnclosures(
                for: curve,
                lowerFraction: boundedLower,
                upperFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        }
        struct EnclosureWorkItem {
            let lowerFraction: Double
            let upperFraction: Double
            let depth: Int
        }
        let configuration = try makeConfiguration(
            curve: curve,
            tolerance: tolerance
        )
        var pending = [EnclosureWorkItem(
            lowerFraction: boundedLower,
            upperFraction: boundedUpper,
            depth: 0
        )]
        var result: [SurfaceParameterCurveEnclosure] = []
        var processedCount = 0
        while let item = pending.popLast() {
            processedCount += 1
            guard processedCount <= maximumCellCount else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCount),
                    tolerance: tolerance,
                    message: "Analytic-pair pcurve enclosure exceeded its cell budget."
                )
            }
            let firstGlobal = curve.startFraction
                + (curve.endFraction - curve.startFraction)
                    * item.lowerFraction
            let secondGlobal = curve.startFraction
                + (curve.endFraction - curve.startFraction)
                    * item.upperFraction
            let lower = min(firstGlobal, secondGlobal) * 2.0 * Double.pi
            let upper = max(firstGlobal, secondGlobal) * 2.0 * Double.pi
            let ranges: (u: Interval, v: Interval)?
            do {
                let geometry = try geometryRanges(
                    parameter: Interval(lower: lower, upper: upper),
                    configuration: configuration,
                    tolerance: tolerance
                )
                if isPlaneRole(curve, configuration: configuration) {
                    ranges = planeCoordinateRanges(
                        geometry,
                        configuration: configuration,
                        uShift: 0.0
                    )
                } else {
                    let middleFraction = item.lowerFraction
                        + (item.upperFraction - item.lowerFraction) * 0.5
                    let reference = try curve.parameter(
                        atNormalizedFraction: middleFraction,
                        tolerance: tolerance
                    ).u
                    let u = try torusAngleRange(
                        geometry,
                        configuration: configuration,
                        reference: reference
                    )
                    ranges = (u, geometry.minor)
                }
            } catch LocalProofFailure.intervalSingularity {
                ranges = nil
            } catch LocalProofFailure.periodicSeam {
                ranges = nil
            }
            if let ranges,
               ranges.u.lower.isFinite,
               ranges.u.upper.isFinite,
               ranges.v.lower.isFinite,
               ranges.v.upper.isFinite,
               ranges.v.width <= maximumWidth,
               requiresUWidth == false || ranges.u.width <= maximumWidth {
                result.append(SurfaceParameterCurveEnclosure(
                    lowerFraction: item.lowerFraction,
                    upperFraction: item.upperFraction,
                    u: try ScalarInterval(
                        lower: ranges.u.lower,
                        upper: ranges.u.upper
                    ),
                    v: try ScalarInterval(
                        lower: ranges.v.lower,
                        upper: ranges.v.upper
                    )
                ))
                continue
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: ranges.map {
                        requiresUWidth ? max($0.u.width, $0.v.width) : $0.v.width
                    },
                    tolerance: tolerance,
                    message: "Analytic-pair pcurve enclosure exceeded its proof depth for \(curve.role.rawValue) over [\(item.lowerFraction), \(item.upperFraction)]."
                )
            }
            let middle = item.lowerFraction
                + (item.upperFraction - item.lowerFraction) * 0.5
            guard middle > item.lowerFraction,
                  middle < item.upperFraction else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Analytic-pair pcurve enclosure reached floating-point resolution."
                )
            }
            pending.append(EnclosureWorkItem(
                lowerFraction: middle,
                upperFraction: item.upperFraction,
                depth: item.depth + 1
            ))
            pending.append(EnclosureWorkItem(
                lowerFraction: item.lowerFraction,
                upperFraction: middle,
                depth: item.depth + 1
            ))
        }
        return result.sorted { $0.lowerFraction < $1.lowerFraction }
    }

    private func cylinderBoundaryBounds(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: GenericBoundaryIntegrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        guard isCylinderBoundaryIntegrand(integrand) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cylinder boundary integration requires a cylinder Green primitive."
            )
        }
        // Geometry certifies every cell in one continuous universal-cover
        // chart. The pcurve's declared start may select a translated sheet,
        // so derive that single whole-period translation once from the first
        // certificate. Realigning each cell independently would break a full
        // revolution; anchoring to a principal midpoint would break a span
        // ending at the seam.
        let cylinderSheetShift = try cylinderSheetShift(
            for: curve,
            tolerance: tolerance
        )
        let globalBoundary = try cylinderGlobalBoundary(
            curve: curve,
            integrand: integrand,
            cylinderSheetShift: cylinderSheetShift,
            tolerance: tolerance
        )
        let cellTargetWidth = (
            requestedWidth - globalBoundary.width
        ).nextDown
        guard cellTargetWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: globalBoundary.width,
                tolerance: tolerance,
                message: "Cylinder boundary roundoff exhausted the requested enclosure width."
            )
        }
        var heap = WorkHeap()
        for (lower, upper) in [(0.0, 0.5), (0.5, 1.0)] {
            heap.push(try cylinderBoundaryWorkItem(
                lower: lower,
                upper: upper,
                depth: 0,
                curve: curve,
                integrand: integrand,
                cylinderSheetShift: cylinderSheetShift,
                tolerance: tolerance
            ))
        }
        let internalTargetWidth = (cellTargetWidth * 0.99).nextDown
        var totalWidth = outwardWidthSum(heap.storage)
        var subdivisionCount = 0
        while totalWidth > internalTargetWidth {
            guard let item = heap.popMaximum() else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Cylinder boundary integration lost its active proof cells."
                )
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: item.width,
                    tolerance: tolerance,
                    message: "Cylinder boundary integration exceeded its subdivision depth."
                )
            }
            guard heap.count + 2 <= maximumCellCount else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: Double(heap.count),
                    tolerance: tolerance,
                    message: "Cylinder boundary integration exceeded its certified cell budget."
                )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Cylinder boundary integration reached floating-point subdivision resolution."
                )
            }
            let children = try [
                cylinderBoundaryWorkItem(
                    lower: item.lower,
                    upper: midpoint,
                    depth: item.depth + 1,
                    curve: curve,
                    integrand: integrand,
                    cylinderSheetShift: cylinderSheetShift,
                    tolerance: tolerance
                ),
                cylinderBoundaryWorkItem(
                    lower: midpoint,
                    upper: item.upper,
                    depth: item.depth + 1,
                    curve: curve,
                    integrand: integrand,
                    cylinderSheetShift: cylinderSheetShift,
                    tolerance: tolerance
                ),
            ]
            for child in children { heap.push(child) }
            subdivisionCount += 1
            totalWidth = replacingWidthUpperBound(
                totalWidth,
                removing: item.width,
                addingFirst: children[0].width,
                second: children[1].width
            )
            if subdivisionCount.nonzeroBitCount == 1 {
                totalWidth = outwardWidthSum(heap.storage)
            }
            if totalWidth <= internalTargetWidth {
                totalWidth = outwardWidthSum(heap.storage)
            }
        }
        var result = CertifiedIntervalSummation.sum(
            heap.storage,
            bounds: \.bounds
        )
        result = result.adding(SurfaceParameterAreaBounds(
            lower: globalBoundary.lower,
            upper: globalBoundary.upper
        ))
        guard result.width <= requestedWidth.nextUp else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: result.width,
                tolerance: tolerance,
                message: "Cylinder boundary cells did not compose to the requested enclosure."
            )
        }
        return result
    }

    private func cylinderBoundaryWorkItem(
        lower: Double,
        upper: Double,
        depth: Int,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: GenericBoundaryIntegrand,
        cylinderSheetShift: Double,
        tolerance: ModelingTolerance
    ) throws -> WorkItem {
        guard isCylinderBoundaryIntegrand(integrand) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cylinder boundary work requires a cylinder Green primitive."
            )
        }
        let parameterBounds = try curve.parameterCellBounds(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            tolerance: tolerance
        )
        guard parameterBounds.uLift.width < 2.0 * Double.pi,
              let uFirst = parameterBounds.uFirstDerivativeMagnitude,
              let uSecond = parameterBounds.uSecondDerivativeMagnitude,
              let uThird = parameterBounds.uThirdDerivativeMagnitude,
              let vSecond = parameterBounds.vSecondDerivativeMagnitude else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: parameterBounds.uLift.width,
                tolerance: tolerance,
                message: "Cylinder boundary integration could not establish a continuous parameter lift."
            )
        }
        let uLift = try translatedCylinderULift(
            parameterBounds.uLift,
            by: cylinderSheetShift
        )
        let midpoint = lower + (upper - lower) * 0.5
        let middle = try curve.parameter(
            atNormalizedFraction: midpoint,
            tolerance: tolerance
        )
        let middleU = try liftedPeriodicValue(
            middle.u,
            in: uLift,
            tolerance: tolerance
        )

        let localScale = upper - lower
        let midpointDifferential = try curve.differential(
            atNormalizedFraction: midpoint,
            tolerance: tolerance
        )
        let midpointDerivatives = try cylinderPrimitiveDerivatives(
            at: .scalar(middleU),
            integrand: integrand,
            tolerance: tolerance
        )
        let midpointTransformed = Interval.scalar(middle.v)
            .multiplied(by: midpointDerivatives.first)
            .multiplied(by: .scalar(
                midpointDifferential.firstDerivative.x * localScale
            ))

        let rangedDerivatives = try cylinderPrimitiveDerivatives(
            at: Interval(lower: uLift.lower, upper: uLift.upper),
            integrand: integrand,
            tolerance: tolerance
        )
        let vMagnitude = max(
            abs(parameterBounds.vLift.lower),
            abs(parameterBounds.vLift.upper)
        ).nextUp
        let vFirst = parameterBounds.vFirstDerivativeMagnitude
        let firstMagnitude = rangedDerivatives.first.maximumAbsoluteValue
        let secondMagnitude = rangedDerivatives.second.maximumAbsoluteValue
        let thirdMagnitude = rangedDerivatives.third.maximumAbsoluteValue
        let firstTerm = upperProduct(vSecond, firstMagnitude, uFirst)
        let secondTerm = upperProduct(
            2.0,
            vFirst,
            secondMagnitude,
            uFirst,
            uFirst
        )
        let thirdTerm = upperProduct(2.0, vFirst, firstMagnitude, uSecond)
        let fourthTerm = upperProduct(
            vMagnitude,
            thirdMagnitude,
            uFirst,
            uFirst,
            uFirst
        )
        let fifthTerm = upperProduct(
            3.0,
            vMagnitude,
            secondMagnitude,
            uFirst,
            uSecond
        )
        let sixthTerm = upperProduct(
            vMagnitude,
            firstMagnitude,
            uThird
        )
        let secondDerivativeBound = upperSum(
            firstTerm,
            secondTerm,
            thirdTerm,
            fourthTerm,
            fifthTerm,
            sixthTerm
        )
        let analyticError = (secondDerivativeBound / 24.0).nextUp
        // Directed interval operations already account for their own rounding.
        // This allowance covers the bounded number of scalar operations used
        // to obtain the midpoint curve value and differential.
        let scalarEvaluationOperationCount = 256.0
        let floatingPointError = (
            Double.ulpOfOne * max(
                midpointTransformed.maximumAbsoluteValue,
                analyticError
            ) * scalarEvaluationOperationCount
        ).nextUp
        let totalError = (analyticError + floatingPointError).nextUp
        let transformed = Interval(
            lower: (midpointTransformed.lower - totalError).nextDown,
            upper: (midpointTransformed.upper + totalError).nextUp
        )
        let contribution = Interval(
            lower: (-transformed.upper).nextDown,
            upper: (-transformed.lower).nextUp
        )
        guard contribution.lower.isFinite,
              contribution.upper.isFinite,
              contribution.lower <= contribution.upper else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Cylinder boundary integration produced a non-finite enclosure."
            )
        }
        return WorkItem(
            lower: lower,
            upper: upper,
            depth: depth,
            bounds: SurfaceParameterAreaBounds(
                lower: contribution.lower,
                upper: contribution.upper
            )
        )
    }

    private func cylinderGlobalBoundary(
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: GenericBoundaryIntegrand,
        cylinderSheetShift: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let start = try cylinderBoundaryEndpoint(
            fraction: 0.0,
            enclosingLowerFraction: 0.0,
            enclosingUpperFraction: 0.5,
            curve: curve,
            integrand: integrand,
            cylinderSheetShift: cylinderSheetShift,
            tolerance: tolerance
        )
        let end = try cylinderBoundaryEndpoint(
            fraction: 1.0,
            enclosingLowerFraction: 0.5,
            enclosingUpperFraction: 1.0,
            curve: curve,
            integrand: integrand,
            cylinderSheetShift: cylinderSheetShift,
            tolerance: tolerance
        )
        return end.subtracting(start)
    }

    private func cylinderBoundaryEndpoint(
        fraction: Double,
        enclosingLowerFraction: Double,
        enclosingUpperFraction: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: GenericBoundaryIntegrand,
        cylinderSheetShift: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let parameterBounds = try curve.parameterCellBounds(
            fromNormalizedFraction: enclosingLowerFraction,
            toNormalizedFraction: enclosingUpperFraction,
            tolerance: tolerance
        )
        let uLift = try translatedCylinderULift(
            parameterBounds.uLift,
            by: cylinderSheetShift
        )
        let parameter = try curve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let liftedU = try liftedPeriodicValue(
            parameter.u,
            in: uLift,
            tolerance: tolerance
        )
        let primitive = try cylinderPrimitiveDerivatives(
            at: .scalar(liftedU),
            integrand: integrand,
            tolerance: tolerance
        ).primitive
        return primitive.multiplied(by: .scalar(parameter.v))
    }

    private func cylinderSheetShift(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let initialBounds = try curve.parameterCellBounds(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 0.5,
            tolerance: tolerance
        )
        let period = 2.0 * Double.pi
        guard initialBounds.uLift.width < period else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: initialBounds.uLift.width,
                tolerance: tolerance,
                message: "Cylinder boundary integration could not establish its initial periodic sheet."
            )
        }
        let declaredStart = try curve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        ).u
        let certifiedStart = try liftedPeriodicValue(
            declaredStart,
            in: initialBounds.uLift,
            tolerance: tolerance
        )
        return round((declaredStart - certifiedStart) / period) * period
    }

    private func translatedCylinderULift(
        _ lift: ScalarInterval,
        by shift: Double
    ) throws -> ScalarInterval {
        return try ScalarInterval(
            lower: (lift.lower + shift).nextDown,
            upper: (lift.upper + shift).nextUp
        )
    }

    private func cylinderPrimitiveDerivatives(
        at u: Interval,
        integrand: GenericBoundaryIntegrand,
        tolerance: ModelingTolerance
    ) throws -> (
        primitive: Interval,
        first: Interval,
        second: Interval,
        third: Interval
    ) {
        switch integrand {
        case let .parameterArea(uShift):
            return (
                primitive: u.adding(.scalar(uShift)),
                first: .one,
                second: .zero,
                third: .zero
            )
        case let .volume(.cylinder(radius, offsetU, offsetV)):
            let radius = Interval(lower: radius.lower, upper: radius.upper)
            let offsetU = Interval(lower: offsetU.lower, upper: offsetU.upper)
            let offsetV = Interval(lower: offsetV.lower, upper: offsetV.upper)
            let scale = radius.scaled(by: 1.0 / 3.0)
            let sine = Jet.trigonometricBounds(u, phase: 0.0)
            let cosine = Jet.trigonometricBounds(
                u,
                phase: Double.pi * 0.5
            )
            let primitive = scale.multiplied(by:
                offsetU.multiplied(by: sine)
                    .subtracting(offsetV.multiplied(by: cosine))
                    .adding(radius.multiplied(by: u))
            )
            let first = scale.multiplied(by:
                offsetU.multiplied(by: cosine)
                    .adding(offsetV.multiplied(by: sine))
                    .adding(radius)
            )
            let second = scale.multiplied(by:
                offsetU.multiplied(by: sine).scaled(by: -1.0)
                    .adding(offsetV.multiplied(by: cosine))
            )
            let third = scale.multiplied(by:
                offsetU.multiplied(by: cosine).scaled(by: -1.0)
                    .subtracting(offsetV.multiplied(by: sine))
            )
            return (primitive, first, second, third)
        case .volume:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cylinder boundary integration requires a cylinder Green primitive."
            )
        }
    }

    private func usesCylinderChart(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve
    ) -> Bool {
        switch curve.intersection.surface(for: curve.role) {
        case .cylinder, .analytic(.cylinder):
            true
        case .plane, .analytic, .bSpline, .procedural:
            false
        }
    }

    private func isCylinderBoundaryIntegrand(
        _ integrand: GenericBoundaryIntegrand
    ) -> Bool {
        switch integrand {
        case .parameterArea:
            true
        case .volume(.cylinder):
            true
        case .volume:
            false
        }
    }

    private func liftedPeriodicValue(
        _ value: Double,
        in lift: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let period = 2.0 * Double.pi
        let nearestTurn = round((lift.midpoint - value) / period)
        let roundoff = (
            Double.ulpOfOne * max(abs(value), abs(lift.midpoint), 1.0)
                * 8_192.0
        ).nextUp
        for turn in [nearestTurn, nearestTurn - 1.0, nearestTurn + 1.0] {
            let lifted = value + turn * period
            if lifted >= lift.lower - roundoff,
               lifted <= lift.upper + roundoff {
                return lifted
            }
        }
        throw KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            residual: lift.width,
            tolerance: tolerance,
            message: "Cylinder boundary integration could not lift a periodic parameter value."
        )
    }

    private func upperProduct(_ values: Double...) -> Double {
        values.reduce(1.0) { partial, value in
            (partial * value).nextUp
        }
    }

    private func upperSum(_ values: Double...) -> Double {
        values.reduce(0.0) { partial, value in
            (partial + value).nextUp
        }
    }

    private func genericIntegralBounds(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: GenericBoundaryIntegrand,
        usesPeriodicBoundaryGauge: Bool,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        let parameterBoundsPreparation = try curve.prepareParameterCellBounds(
            tolerance: tolerance
        )
        var heap = WorkHeap()
        let breakpoints = parameterBoundsPreparation.integrationBreakpoints
        for index in 1..<breakpoints.count {
            let lower = breakpoints[index - 1]
            let upper = breakpoints[index]
            guard upper > lower else { continue }
            heap.push(try genericWorkItem(
                lower: lower,
                upper: upper,
                depth: 0,
                curve: curve,
                parameterBoundsPreparation: parameterBoundsPreparation,
                integrand: integrand,
                usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge,
                tolerance: tolerance
            ))
        }
        guard heap.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Generic analytic-pair integration received no certified parameter cells."
            )
        }
        let internalTargetWidth = (requestedWidth * 0.99).nextDown
        var totalWidth = outwardWidthSum(heap.storage)
        var subdivisionCount = 0
        while totalWidth > internalTargetWidth {
            guard let item = heap.popMaximum() else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Generic analytic-pair integration lost its active proof cells."
                )
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: item.width,
                    tolerance: tolerance,
                    message: "Generic analytic-pair integration exceeded its subdivision depth."
                )
            }
            guard heap.count + 2 <= maximumCellCount else {
                let diagnosticBounds = try parameterBoundsPreparation.bounds(
                    fromNormalizedFraction: item.lower,
                    toNormalizedFraction: item.upper,
                    reusingStart: item.parameterStart,
                    end: item.parameterEnd,
                    tolerance: tolerance
                )
                let diagnosticDifferential = try curve.differential(
                    atNormalizedFraction: item.lower
                        + (item.upper - item.lower) * 0.5,
                    tolerance: tolerance
                )
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: item.width,
                    tolerance: tolerance,
                    message: "Generic analytic-pair integration exceeded its certified cell budget for \(surfaceKind(curve.intersection.surface(for: curve.role))) role \(curve.role.rawValue) over normalized interval [\(item.lower), \(item.upper)] at depth \(item.depth); cell width \(item.width), composed width \(totalWidth), requested width \(requestedWidth), active cells \(heap.count), certified derivatives U [\(String(describing: diagnosticBounds.uFirstDerivativeMagnitude)), \(String(describing: diagnosticBounds.uSecondDerivativeMagnitude)), \(String(describing: diagnosticBounds.uThirdDerivativeMagnitude))], V [\(diagnosticBounds.vFirstDerivativeMagnitude), \(String(describing: diagnosticBounds.vSecondDerivativeMagnitude)), \(String(describing: diagnosticBounds.vThirdDerivativeMagnitude))], midpoint derivative [\(diagnosticDifferential.firstDerivative.x), \(diagnosticDifferential.firstDerivative.y)]."
                )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: item.width,
                    tolerance: tolerance,
                    message: "Generic analytic-pair integration reached floating-point subdivision resolution for normalized interval [\(item.lower), \(item.upper)] at depth \(item.depth); cell width \(item.width), composed width \(totalWidth), requested width \(requestedWidth)."
                )
            }
            let children = try [
                genericWorkItem(
                    lower: item.lower,
                    upper: midpoint,
                    depth: item.depth + 1,
                    curve: curve,
                    parameterBoundsPreparation: parameterBoundsPreparation,
                    startParameter: item.parameterStart,
                    endParameter: item.parameterMiddle,
                    integrand: integrand,
                    usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge,
                    tolerance: tolerance
                ),
                genericWorkItem(
                    lower: midpoint,
                    upper: item.upper,
                    depth: item.depth + 1,
                    curve: curve,
                    parameterBoundsPreparation: parameterBoundsPreparation,
                    startParameter: item.parameterMiddle,
                    endParameter: item.parameterEnd,
                    integrand: integrand,
                    usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge,
                    tolerance: tolerance
                ),
            ]
            for child in children { heap.push(child) }
            subdivisionCount += 1
            totalWidth = replacingWidthUpperBound(
                totalWidth,
                removing: item.width,
                addingFirst: children[0].width,
                second: children[1].width
            )
            if subdivisionCount.nonzeroBitCount == 1 {
                totalWidth = outwardWidthSum(heap.storage)
            }
            if totalWidth <= internalTargetWidth {
                totalWidth = outwardWidthSum(heap.storage)
            }
        }

        let result = CertifiedIntervalSummation.sum(
            heap.storage,
            bounds: \.bounds
        )
        guard result.width <= requestedWidth.nextUp else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: result.width,
                tolerance: tolerance,
                message: "Generic analytic-pair cells did not compose to the requested enclosure."
            )
        }
        return result
    }

    private func genericWorkItem(
        lower: Double,
        upper: Double,
        depth: Int,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        parameterBoundsPreparation: CertifiedAnalyticPairParameterCellBoundsPreparation,
        startParameter: SurfaceParameter? = nil,
        endParameter: SurfaceParameter? = nil,
        integrand: GenericBoundaryIntegrand,
        usesPeriodicBoundaryGauge: Bool,
        tolerance: ModelingTolerance
    ) throws -> WorkItem {
        let parameterBounds = try parameterBoundsPreparation.bounds(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            reusingStart: startParameter,
            end: endParameter,
            tolerance: tolerance
        )
        let midpoint = lower + (upper - lower) * 0.5
        let middleParameter = parameterBounds.middle
        let surface = curve.intersection.surface(for: curve.role)
        let integrationU = parameterBounds.usesContinuousLiftForIntegration
            ? parameterBounds.uLift
            : parameterBounds.canonicalU
        let integrationV = parameterBounds.usesContinuousLiftForIntegration
            ? parameterBounds.vLift
            : parameterBounds.canonicalV
        let primitiveBounds = genericOneFormBounds(
            integrand: integrand,
            u: integrationU,
            v: integrationV,
            usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge
        )
        let middleU = try isUPeriodic(surface)
            ? liftedPeriodicValue(
                middleParameter.u,
                in: integrationU,
                tolerance: tolerance
            )
            : middleParameter.u
        let middleV = try isVPeriodic(surface)
            ? liftedPeriodicValue(
                middleParameter.v,
                in: integrationV,
                tolerance: tolerance
            )
            : middleParameter.v
        let middlePrimitive = genericOneFormBounds(
            integrand: integrand,
            u: try ScalarInterval(
                lower: middleU,
                upper: middleU
            ),
            v: try ScalarInterval(
                lower: middleV,
                upper: middleV
            ),
            usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge
        )

        let variationV = Interval(
            lower: (-parameterBounds.totalVariationV).nextDown,
            upper: parameterBounds.totalVariationV.nextUp
        )
        var contribution = primitiveBounds.dv.multiplied(by: variationV)
        if primitiveBounds.du.maximumAbsoluteValue > 0.0 {
            guard let totalVariationU = parameterBounds.totalVariationU else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A periodic analytic-pair one-form requires a certified U variation."
                )
            }
            let variationU = Interval(
                lower: (-totalVariationU).nextDown,
                upper: totalVariationU.nextUp
            )
            contribution = contribution.adding(
                primitiveBounds.du.multiplied(by: variationU)
            )
        }
        if (parameterBounds.usesContinuousLiftForIntegration
                || (parameterBounds.crossesUSeam == false
                    && parameterBounds.crossesVSeam == false)),
           let first = parameterBounds.parameterFirstDerivativeMagnitude,
           let second = parameterBounds.parameterSecondDerivativeMagnitude,
           let third = parameterBounds.parameterThirdDerivativeMagnitude {
            let primitive = bivariateOneFormBounds(
                integrand: integrand,
                u: integrationU,
                v: integrationV,
                usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge
            )
            let secondDerivativeBound: Double
            if let uFirst = parameterBounds.uFirstDerivativeMagnitude,
               let uSecond = parameterBounds.uSecondDerivativeMagnitude,
               let vSecond = parameterBounds.vSecondDerivativeMagnitude,
               let vThird = parameterBounds.vThirdDerivativeMagnitude {
                let vFirst = parameterBounds.vFirstDerivativeMagnitude
                // For f = P(u, v) v', retain the component structure of
                // f'' instead of collapsing the parameter jet into one norm.
                // This is especially important for analytic charts whose U
                // coordinate is affine while V carries all higher derivatives.
                let dvSecondDerivativeBound = upperSum(
                    upperProduct(
                        primitive.dv.uu.maximumAbsoluteValue,
                        uFirst,
                        uFirst,
                        vFirst
                    ),
                    upperProduct(
                        2.0,
                        primitive.dv.uv.maximumAbsoluteValue,
                        uFirst,
                        vFirst,
                        vFirst
                    ),
                    upperProduct(
                        primitive.dv.vv.maximumAbsoluteValue,
                        vFirst,
                        vFirst,
                        vFirst
                    ),
                    upperProduct(
                        primitive.dv.u.maximumAbsoluteValue,
                        uSecond,
                        vFirst
                    ),
                    upperProduct(
                        primitive.dv.v.maximumAbsoluteValue,
                        vSecond,
                        vFirst
                    ),
                    upperProduct(
                        2.0,
                        primitive.dv.u.maximumAbsoluteValue,
                        uFirst,
                        vSecond
                    ),
                    upperProduct(
                        2.0,
                        primitive.dv.v.maximumAbsoluteValue,
                        vFirst,
                        vSecond
                    ),
                    upperProduct(
                        primitive.dv.value.maximumAbsoluteValue,
                        vThird
                    )
                )
                let duSecondDerivativeBound = upperSum(
                    upperProduct(
                        primitive.du.uu.maximumAbsoluteValue,
                        uFirst,
                        uFirst,
                        uFirst
                    ),
                    upperProduct(
                        2.0,
                        primitive.du.uv.maximumAbsoluteValue,
                        vFirst,
                        uFirst,
                        uFirst
                    ),
                    upperProduct(
                        primitive.du.vv.maximumAbsoluteValue,
                        vFirst,
                        vFirst,
                        uFirst
                    ),
                    upperProduct(
                        primitive.du.u.maximumAbsoluteValue,
                        uSecond,
                        uFirst
                    ),
                    upperProduct(
                        primitive.du.v.maximumAbsoluteValue,
                        vSecond,
                        uFirst
                    ),
                    upperProduct(
                        2.0,
                        primitive.du.u.maximumAbsoluteValue,
                        uFirst,
                        uSecond
                    ),
                    upperProduct(
                        2.0,
                        primitive.du.v.maximumAbsoluteValue,
                        vFirst,
                        uSecond
                    ),
                    upperProduct(
                        primitive.du.value.maximumAbsoluteValue,
                        parameterBounds.uThirdDerivativeMagnitude ?? third
                    )
                )
                secondDerivativeBound = upperSum(
                    dvSecondDerivativeBound,
                    duSecondDerivativeBound
                )
            } else {
                guard primitive.du.value.maximumAbsoluteValue == 0.0 else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A periodic analytic-pair one-form requires componentwise parameter derivative certificates."
                    )
                }
                let firstCubed = (first * first * first).nextUp
                let firstSecond = (first * second).nextUp
                let hessianTerm = (
                    primitive.dv.uu.maximumAbsoluteValue
                        + 2.0 * primitive.dv.uv.maximumAbsoluteValue
                        + primitive.dv.vv.maximumAbsoluteValue
                ).nextUp
                let gradientTerm = (
                    primitive.dv.u.maximumAbsoluteValue
                        + primitive.dv.v.maximumAbsoluteValue
                ).nextUp
                secondDerivativeBound = (
                    hessianTerm * firstCubed
                        + 3.0 * gradientTerm * firstSecond
                        + primitive.dv.value.maximumAbsoluteValue * third
                ).nextUp
            }
            let localScale = upper - lower
            let midpointFirstDerivative: Point2D
            if let prepared = parameterBounds.middleFirstDerivative {
                midpointFirstDerivative = prepared
            } else {
                let differential = try curve.differential(
                    atNormalizedFraction: midpoint,
                    tolerance: tolerance
                ).firstDerivative
                midpointFirstDerivative = Point2D(
                    x: differential.x * localScale,
                    y: differential.y * localScale
                )
            }
            let midpointContribution = middlePrimitive.du.multiplied(
                by: .scalar(midpointFirstDerivative.x)
            ).adding(
                middlePrimitive.dv.multiplied(
                    by: .scalar(midpointFirstDerivative.y)
                )
            )
            let analyticError = (secondDerivativeBound / 24.0).nextUp
            let floatingPointError = (
                Double.ulpOfOne * max(
                    midpointContribution.maximumAbsoluteValue,
                    analyticError
                ) * 65_536.0
            ).nextUp
            let totalError = (analyticError + floatingPointError).nextUp
            let midpointEnclosure = Interval(
                lower: (midpointContribution.lower - totalError).nextDown,
                upper: (midpointContribution.upper + totalError).nextUp
            )
            let overlapLower = max(contribution.lower, midpointEnclosure.lower)
            let overlapUpper = min(contribution.upper, midpointEnclosure.upper)
            guard overlapLower <= overlapUpper else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: max(
                        midpointEnclosure.lower - contribution.upper,
                        contribution.lower - midpointEnclosure.upper,
                        0.0
                    ),
                    tolerance: tolerance,
                    message: "Independent analytic-pair integral certificates do not overlap on normalized interval [\(lower), \(upper)]; variation enclosure [\(contribution.lower), \(contribution.upper)], midpoint enclosure [\(midpointEnclosure.lower), \(midpointEnclosure.upper)], one-form DU [\(primitiveBounds.du.lower), \(primitiveBounds.du.upper)], DV [\(primitiveBounds.dv.lower), \(primitiveBounds.dv.upper)], parameter variation U \(String(describing: parameterBounds.totalVariationU)), V \(parameterBounds.totalVariationV), midpoint derivative (\(midpointFirstDerivative.x), \(midpointFirstDerivative.y))."
                )
            }
            contribution = Interval(lower: overlapLower, upper: overlapUpper)
        }
        guard contribution.lower.isFinite,
              contribution.upper.isFinite,
              contribution.lower <= contribution.upper else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Generic analytic-pair integration produced a non-finite enclosure."
            )
        }
        return WorkItem(
            lower: lower,
            upper: upper,
            depth: depth,
            bounds: SurfaceParameterAreaBounds(
                lower: contribution.lower,
                upper: contribution.upper
            ),
            parameterStart: parameterBounds.start,
            parameterMiddle: parameterBounds.middle,
            parameterEnd: parameterBounds.end
        )
    }

    private func genericPrimitiveBounds(
        integrand: GenericBoundaryIntegrand,
        u: ScalarInterval,
        v: ScalarInterval
    ) -> Interval {
        switch integrand {
        case let .parameterArea(uShift):
            return Interval(
                lower: (u.lower + uShift).nextDown,
                upper: (u.upper + uShift).nextUp
            )
        case let .volume(volumeIntegrand):
            let result = volumeIntegrand.greenPrimitive(
                u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                    lower: u.lower,
                    upper: u.upper
                ),
                v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                    lower: v.lower,
                    upper: v.upper
                )
            )
            return Interval(lower: result.lower, upper: result.upper)
        }
    }

    private func genericOneFormBounds(
        integrand: GenericBoundaryIntegrand,
        u: ScalarInterval,
        v: ScalarInterval,
        usesPeriodicBoundaryGauge: Bool
    ) -> OneFormInterval {
        guard usesPeriodicBoundaryGauge else {
            return OneFormInterval(
                du: .zero,
                dv: genericPrimitiveBounds(integrand: integrand, u: u, v: v)
            )
        }
        let vInterval = Interval(lower: v.lower, upper: v.upper)
        switch integrand {
        case .parameterArea:
            return OneFormInterval(
                du: vInterval.scaled(by: -1.0),
                dv: .zero
            )
        case let .volume(volumeIntegrand):
            let oneForm = volumeIntegrand.boundaryOneForm(
                u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                    lower: u.lower,
                    upper: u.upper
                ),
                v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                    lower: v.lower,
                    upper: v.upper
                )
            )
            return OneFormInterval(
                du: Interval(lower: oneForm.du.lower, upper: oneForm.du.upper),
                dv: Interval(lower: oneForm.dv.lower, upper: oneForm.dv.upper)
            )
        }
    }

    private func bivariateOneFormBounds(
        integrand: GenericBoundaryIntegrand,
        u: ScalarInterval,
        v: ScalarInterval,
        usesPeriodicBoundaryGauge: Bool
    ) -> BivariateOneForm {
        guard usesPeriodicBoundaryGauge else {
            return BivariateOneForm(
                du: .constant(.zero),
                dv: bivariatePrimitiveBounds(integrand: integrand, u: u, v: v)
            )
        }
        let uJet = BivariateJet.parameterU(Interval(
            lower: u.lower,
            upper: u.upper
        ))
        let vJet = BivariateJet.parameterV(Interval(
            lower: v.lower,
            upper: v.upper
        ))
        switch integrand {
        case .parameterArea:
            return BivariateOneForm(
                du: vJet.scaled(by: -1.0),
                dv: .constant(.zero)
            )
        case let .volume(.cone(
            sine,
            cosine,
            radialOffsetU,
            radialOffsetV,
            axialOffset
        )):
            let trigonometry = uJet.sineAndCosine()
            let azimuth = trigonometry.sine
                .scaled(by: interval(radialOffsetU))
                .subtracting(
                    trigonometry.cosine.scaled(by: interval(radialOffsetV))
                )
            let dv = azimuth.multiplied(by: vJet)
                .scaled(by: interval(sine / .exact(3.0)))
                .scaled(by: interval(cosine))
            let du = vJet.multiplied(by: vJet)
                .scaled(by: interval(sine))
                .scaled(by: interval(sine))
                .scaled(by: interval(axialOffset))
                .scaled(by: 1.0 / 6.0)
            return BivariateOneForm(du: du, dv: dv)
        case let .volume(.torus(
            majorRadius,
            minorRadius,
            radialOffsetU,
            radialOffsetV,
            axialOffset
        )):
            let uTrigonometry = uJet.sineAndCosine()
            let vTrigonometry = vJet.sineAndCosine()
            let cosineSquaredV = vTrigonometry.cosine.multiplied(
                by: vTrigonometry.cosine
            )
            let azimuth = uTrigonometry.sine
                .scaled(by: interval(radialOffsetU))
                .subtracting(
                    uTrigonometry.cosine.scaled(by: interval(radialOffsetV))
                )
            let radialFactor = vTrigonometry.cosine
                .scaled(by: interval(majorRadius))
                .adding(cosineSquaredV.scaled(by: interval(minorRadius)))
            let intrinsicFactor = vTrigonometry.cosine
                .scaled(by: interval(majorRadius * majorRadius))
                .adding(
                    cosineSquaredV.scaled(by: interval(majorRadius * minorRadius))
                )
                .adding(.constant(interval(minorRadius * majorRadius)))
                .adding(
                    vTrigonometry.cosine
                        .scaled(by: interval(minorRadius * minorRadius))
                )
            let du = vTrigonometry.cosine
                .scaled(by: interval(majorRadius))
                .adding(cosineSquaredV.scaled(by: interval(minorRadius / .exact(2.0))))
                .scaled(by: interval(minorRadius * axialOffset / .exact(3.0)))
            let dv = azimuth.multiplied(by: radialFactor)
                .adding(uJet.multiplied(by: intrinsicFactor))
                .scaled(by: interval(minorRadius / .exact(3.0)))
            return BivariateOneForm(du: du, dv: dv)
        case .volume:
            return BivariateOneForm(
                du: .constant(.zero),
                dv: bivariatePrimitiveBounds(integrand: integrand, u: u, v: v)
            )
        }
    }

    private func isConeSurface(_ surface: Surface3D) -> Bool {
        if case .analytic(.cone) = surface { return true }
        return false
    }

    private func surfaceKind(_ surface: Surface3D) -> String {
        switch surface {
        case .plane, .analytic(.plane):
            "plane"
        case .cylinder, .analytic(.cylinder):
            "cylinder"
        case .analytic(.cone):
            "cone"
        case .analytic(.sphere):
            "sphere"
        case .analytic(.torus):
            "torus"
        case .analytic:
            "analytic"
        case .bSpline:
            "bSpline"
        case .procedural:
            "procedural"
        }
    }

    private func isConeVolumeIntegrand(
        _ integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand
    ) -> Bool {
        if case .cone = integrand { return true }
        return false
    }

    private func isUPeriodic(_ surface: Surface3D) -> Bool {
        switch surface {
        case .cylinder,
             .analytic(.cylinder),
             .analytic(.cone),
             .analytic(.sphere),
             .analytic(.torus):
            return true
        case .plane, .analytic(.plane), .bSpline, .procedural:
            return false
        }
    }

    private func isVPeriodic(_ surface: Surface3D) -> Bool {
        if case .analytic(.torus) = surface { return true }
        return false
    }

    private func bivariatePrimitiveBounds(
        integrand: GenericBoundaryIntegrand,
        u uBounds: ScalarInterval,
        v vBounds: ScalarInterval
    ) -> BivariateJet {
        let u = BivariateJet.parameterU(Interval(
            lower: uBounds.lower,
            upper: uBounds.upper
        ))
        let v = BivariateJet.parameterV(Interval(
            lower: vBounds.lower,
            upper: vBounds.upper
        ))
        switch integrand {
        case let .parameterArea(uShift):
            return u.adding(.constant(.scalar(uShift)))
        case let .volume(volumeIntegrand):
            let uTrigonometry = u.sineAndCosine()
            let vTrigonometry = v.sineAndCosine()
            switch volumeIntegrand {
            case let .plane(volumeScale):
                return u.scaled(by: interval(volumeScale))
            case let .cylinder(radius, offsetU, offsetV):
                let azimuth = uTrigonometry.sine
                    .scaled(by: interval(offsetU))
                    .subtracting(
                        uTrigonometry.cosine.scaled(by: interval(offsetV))
                    )
                return azimuth.adding(u.scaled(by: interval(radius)))
                    .scaled(by: interval(radius / .exact(3.0)))
            case let .cone(
                sine,
                cosine,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let azimuth = uTrigonometry.sine
                    .scaled(by: interval(radialOffsetU))
                    .subtracting(
                        uTrigonometry.cosine.scaled(by: interval(radialOffsetV))
                    )
                let bracket = azimuth.scaled(by: interval(cosine))
                    .subtracting(
                        u.scaled(by: interval(sine * axialOffset))
                    )
                return bracket.multiplied(by: v)
                    .scaled(by: interval(sine / .exact(3.0)))
            case let .sphere(
                radius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let azimuth = uTrigonometry.sine
                    .scaled(by: interval(radialOffsetU))
                    .subtracting(
                        uTrigonometry.cosine.scaled(by: interval(radialOffsetV))
                    )
                let cosineSquared = vTrigonometry.cosine.multiplied(
                    by: vTrigonometry.cosine
                )
                let azimuthTerm = azimuth.multiplied(by: cosineSquared)
                let axialTerm = u.multiplied(by:
                    vTrigonometry.cosine.multiplied(by: vTrigonometry.sine)
                        .scaled(by: interval(axialOffset))
                        .adding(vTrigonometry.cosine.scaled(by: interval(radius)))
                )
                return azimuthTerm.adding(axialTerm)
                    .scaled(by: interval(radius * radius / .exact(3.0)))
            case let .torus(
                majorRadius,
                minorRadius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let azimuth = uTrigonometry.sine
                    .scaled(by: interval(radialOffsetU))
                    .subtracting(
                        uTrigonometry.cosine.scaled(by: interval(radialOffsetV))
                    )
                let cosineSquared = vTrigonometry.cosine.multiplied(
                    by: vTrigonometry.cosine
                )
                let azimuthTerm = azimuth.multiplied(by:
                    vTrigonometry.cosine.scaled(by: interval(majorRadius))
                        .adding(cosineSquared.scaled(by: interval(minorRadius)))
                )
                let axialTerm = u.multiplied(by:
                    vTrigonometry.sine
                        .scaled(by: interval(axialOffset * majorRadius))
                        .adding(
                            vTrigonometry.cosine
                                .multiplied(by: vTrigonometry.sine)
                                .scaled(by: interval(axialOffset * minorRadius))
                        )
                        .adding(
                            vTrigonometry.cosine
                                .scaled(by: interval(majorRadius * majorRadius))
                        )
                        .adding(
                            cosineSquared
                                .scaled(by: interval(majorRadius * minorRadius))
                        )
                        .adding(.constant(interval(minorRadius * majorRadius)))
                        .adding(
                            vTrigonometry.cosine
                                .scaled(by: interval(minorRadius * minorRadius))
                        )
                )
                return azimuthTerm.adding(axialTerm)
                    .scaled(by: interval(minorRadius / .exact(3.0)))
            }
        }
    }

    private func genericParameterEnclosures(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        lowerFraction: Double,
        upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        struct Item {
            let lower: Double
            let upper: Double
            let depth: Int
        }
        var pending = [Item(
            lower: lowerFraction,
            upper: upperFraction,
            depth: 0
        )]
        var result: [SurfaceParameterCurveEnclosure] = []
        var processedCount = 0
        let parameterBoundsPreparation = try curve.prepareParameterCellBounds(
            tolerance: tolerance
        )
        while let item = pending.popLast() {
            processedCount += 1
            guard processedCount <= maximumCellCount else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCount),
                    tolerance: tolerance,
                    message: "Generic analytic-pair enclosure exceeded its certified cell budget."
                )
            }
            let bounds: CertifiedAnalyticPairParameterCellBounds
            do {
                bounds = try parameterBoundsPreparation.bounds(
                    fromNormalizedFraction: item.lower,
                    toNormalizedFraction: item.upper,
                    tolerance: tolerance
                )
            } catch let error as KernelError {
                throw KernelError(
                    phase: error.phase,
                    code: error.code,
                    residual: error.residual,
                    tolerance: tolerance,
                    message: "Generic analytic-pair enclosure failed on normalized interval [\(item.lower), \(item.upper)] for requested maximum width \(maximumWidth): \(error.message)"
                )
            }
            if max(bounds.uLift.width, bounds.vLift.width) <= maximumWidth {
                result.append(SurfaceParameterCurveEnclosure(
                    lowerFraction: item.lower,
                    upperFraction: item.upper,
                    u: bounds.uLift,
                    v: bounds.vLift
                ))
                continue
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: max(bounds.uLift.width, bounds.vLift.width),
                    tolerance: tolerance,
                    message: "Generic analytic-pair enclosure exceeded its proof depth on normalized interval [\(item.lower), \(item.upper)]; U width \(bounds.uLift.width), V width \(bounds.vLift.width), requested maximum width \(maximumWidth)."
                )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Generic analytic-pair enclosure reached floating-point subdivision resolution."
                )
            }
            pending.append(Item(
                lower: midpoint,
                upper: item.upper,
                depth: item.depth + 1
            ))
            pending.append(Item(
                lower: item.lower,
                upper: midpoint,
                depth: item.depth + 1
            ))
        }
        return result.sorted { $0.lowerFraction < $1.lowerFraction }
    }

    private func midpointFluxBounds(
        lower: Double,
        upper: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        configuration: Configuration,
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let intervalGeometry = try geometryJets(
            parameter: Interval(lower: lower, upper: upper),
            configuration: configuration
        )
        let midpoint = lower + (upper - lower) * 0.5
        let midpointGeometry = try geometryJets(
            parameter: .scalar(midpoint),
            configuration: configuration
        )
        let reference = try curve.intersection.internalParameter(
            for: curve.role,
            atNormalizedFraction: wrappedEvaluationFraction(
                midpoint / (2.0 * Double.pi),
                curve: curve
            ),
            tolerance: tolerance
        ).u
        let intervalU = try torusAngleJet(
            intervalGeometry,
            configuration: configuration,
            reference: reference
        )
        let midpointU = try torusAngleJet(
            midpointGeometry,
            configuration: configuration,
            reference: reference
        )
        let intervalFlux = try torusGreenPrimitive(
            integrand: integrand,
            u: intervalU,
            v: intervalGeometry.minor,
            tolerance: tolerance
        ).multiplied(by: intervalGeometry.minor.derivative())
        let midpointFlux = try torusGreenPrimitive(
            integrand: integrand,
            u: midpointU,
            v: midpointGeometry.minor,
            tolerance: tolerance
        ).multiplied(by: midpointGeometry.minor.derivative())
        let span = upper - lower
        let midpointContribution = midpointFlux.coefficients[0].scaled(by: span)
        let secondDerivative = intervalFlux.coefficients[2]
            .scaled(by: 2.0)
            .maximumAbsoluteValue
        let analyticError = (secondDerivative * span * span * span / 24.0).nextUp
        let floatingPointError = Double.ulpOfOne * max(
            midpointContribution.maximumAbsoluteValue,
            analyticError
        ) * 65_536.0
        let totalError = (analyticError + floatingPointError).nextUp
        let midpointEnclosure = Interval(
            lower: (midpointContribution.lower - totalError).nextDown,
            upper: (midpointContribution.upper + totalError).nextUp
        )
        // The corrected midpoint rule pushes the analytic remainder to the
        // third derivative, whose interval inflation near a square-root
        // shoulder is offset by the extra span power; both enclosures
        // certify the same integral, so their overlap does too.
        let correctedContribution = midpointContribution.adding(
            midpointFlux.coefficients[2].scaled(
                by: span * span * span / 12.0
            )
        )
        let thirdDerivative = intervalFlux.coefficients[3]
            .scaled(by: 6.0)
            .maximumAbsoluteValue
        let correctedAnalyticError = (
            thirdDerivative * span * span * span * span / 192.0
        ).nextUp
        let correctedFloatingPointError = Double.ulpOfOne * max(
            correctedContribution.maximumAbsoluteValue,
            correctedAnalyticError
        ) * 65_536.0
        let correctedTotalError = (
            correctedAnalyticError + correctedFloatingPointError
        ).nextUp
        let correctedEnclosure = Interval(
            lower: (correctedContribution.lower - correctedTotalError).nextDown,
            upper: (correctedContribution.upper + correctedTotalError).nextUp
        )
        let overlapLower = max(midpointEnclosure.lower, correctedEnclosure.lower)
        let overlapUpper = min(midpointEnclosure.upper, correctedEnclosure.upper)
        guard overlapLower <= overlapUpper else {
            return midpointEnclosure.upper - midpointEnclosure.lower
                <= correctedEnclosure.upper - correctedEnclosure.lower
                ? midpointEnclosure
                : correctedEnclosure
        }
        return Interval(lower: overlapLower, upper: overlapUpper)
    }

    private func geometricFluxFallbackBounds(
        lower: Double,
        upper: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        configuration: Configuration,
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let ranges = try geometryRanges(
            parameter: Interval(lower: lower, upper: upper),
            configuration: configuration,
            tolerance: tolerance
        )
        // The cell's own radial frame usually pins the major angle to a
        // narrow window; only a frame that degenerates on the cell falls
        // back to the whole period.
        var majorAngleRange = Interval(
            lower: 0.0,
            upper: (2.0 * Double.pi).nextUp
        )
        if let localized = try localizedTorusAngleRange(
            lower: lower,
            upper: upper,
            curve: curve,
            ranges,
            configuration: configuration,
            tolerance: tolerance
        ) {
            majorAngleRange = localized
        }
        let q = integrand.greenPrimitive(
            u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                lower: majorAngleRange.lower,
                upper: majorAngleRange.upper
            ),
            v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                lower: ranges.minor.lower,
                upper: ranges.minor.upper
            )
        )
        // The minor angle is monotone on every cell (the initial
        // breakpoints separate the cosine substitution at π), so the flux
        // over the cell substitutes into an integral over the exact signed
        // minor-angle delta, which vanishes with the substitution slope at
        // a bounded-window endpoint.
        let deltaMinor = minorDeltaEnclosure(
            lower: lower,
            upper: upper,
            configuration: configuration,
            minorRange: ranges.minor
        )
        return Interval(
            lower: q.lower,
            upper: q.upper
        ).multiplied(by: deltaMinor)
    }

    private func torusGreenPrimitive(
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        u: Jet,
        v: Jet,
        tolerance: ModelingTolerance
    ) throws -> Jet {
        guard case let .torus(
            majorRadius,
            minorRadius,
            radialOffsetU,
            radialOffsetV,
            axialOffset
        ) = integrand else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Torus Green primitive requires a torus integrand."
            )
        }
        let uTrigonometry = u.sineAndCosine()
        let vTrigonometry = v.sineAndCosine()
        let azimuth = uTrigonometry.sine.multiplied(by: .constant(interval(radialOffsetU)))
            .subtracting(
                uTrigonometry.cosine.multiplied(by: .constant(interval(radialOffsetV)))
            )
        let azimuthTerm = azimuth.multiplied(by:
            vTrigonometry.cosine.scaled(by: interval(majorRadius))
                .adding(
                    vTrigonometry.cosine.multiplied(by: vTrigonometry.cosine)
                        .scaled(by: interval(minorRadius))
                )
        )
        let axialTerm = u.multiplied(by:
            vTrigonometry.sine.scaled(by: interval(axialOffset * majorRadius))
                .adding(
                    vTrigonometry.cosine.multiplied(by: vTrigonometry.sine)
                        .scaled(by: interval(axialOffset * minorRadius))
                )
                .adding(
                    vTrigonometry.cosine.scaled(by: interval(majorRadius * majorRadius))
                )
                .adding(
                    vTrigonometry.cosine.multiplied(by: vTrigonometry.cosine)
                        .scaled(by: interval(majorRadius * minorRadius))
                )
                .adding(.constant(interval(minorRadius * majorRadius)))
                .adding(
                    vTrigonometry.cosine.scaled(by: interval(minorRadius * minorRadius))
                )
        )
        return azimuthTerm.adding(axialTerm)
            .scaled(by: interval(minorRadius / .exact(3.0)))
    }

    private func interval(
        _ value: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    ) -> Interval {
        Interval(lower: value.lower, upper: value.upper)
    }

    private func makeWorkItem(
        lower: Double,
        upper: Double,
        depth: Int,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        configuration: Configuration,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> WorkItem {
        let envelope = try geometricFallbackBounds(
            lower: lower,
            upper: upper,
            curve: curve,
            configuration: configuration,
            uShift: uShift,
            tolerance: tolerance
        )
        var bounds: SurfaceParameterAreaBounds
        do {
            let jetBounds = try midpointBounds(
                lower: lower,
                upper: upper,
                curve: curve,
                configuration: configuration,
                uShift: uShift,
                tolerance: tolerance
            )
            // Both enclosures certify the same integral, so their overlap
            // does too: the geometric envelope wins on the square-root
            // shoulder, where interval jets cannot see the substitution's
            // cancellation, and the midpoint jets win in the interior.
            let overlapLower = max(jetBounds.lower, envelope.lower)
            let overlapUpper = min(jetBounds.upper, envelope.upper)
            if overlapLower <= overlapUpper {
                bounds = SurfaceParameterAreaBounds(
                    lower: overlapLower,
                    upper: overlapUpper
                )
            } else {
                bounds = jetBounds.width <= envelope.width
                    ? jetBounds
                    : envelope
            }
        } catch LocalProofFailure.intervalSingularity,
                LocalProofFailure.periodicSeam {
            bounds = envelope
        }
        guard bounds.lower.isFinite,
              bounds.upper.isFinite,
              bounds.lower <= bounds.upper else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Analytic-pair area integration produced a non-finite enclosure."
            )
        }
        return WorkItem(lower: lower, upper: upper, depth: depth, bounds: bounds)
    }

    private func midpointBounds(
        lower: Double,
        upper: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        configuration: Configuration,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        let intervalJets = try geometryJets(
            parameter: Interval(lower: lower, upper: upper),
            configuration: configuration
        )
        let midpoint = lower + (upper - lower) * 0.5
        let midpointJets = try geometryJets(
            parameter: .scalar(midpoint),
            configuration: configuration
        )
        let intervalIntegrand: Jet
        let midpointIntegrand: Jet
        if isPlaneRole(curve, configuration: configuration) {
            let intervalCoordinates = planeCoordinateJets(
                intervalJets,
                configuration: configuration,
                uShift: uShift
            )
            let midpointCoordinates = planeCoordinateJets(
                midpointJets,
                configuration: configuration,
                uShift: uShift
            )
            intervalIntegrand = intervalCoordinates.u.multiplied(
                by: intervalCoordinates.v.derivative()
            )
            midpointIntegrand = midpointCoordinates.u.multiplied(
                by: midpointCoordinates.v.derivative()
            )
        } else {
            let reference = try curve.intersection.internalParameter(
                for: curve.role,
                atNormalizedFraction: wrappedEvaluationFraction(
                    midpoint / (2.0 * Double.pi),
                    curve: curve
                ),
                tolerance: tolerance
            ).u
            let intervalU = try torusAngleJet(
                intervalJets,
                configuration: configuration,
                reference: reference
            ).adding(.constant(uShift))
            let midpointU = try torusAngleJet(
                midpointJets,
                configuration: configuration,
                reference: reference
            ).adding(.constant(uShift))
            intervalIntegrand = intervalU.multiplied(by: intervalJets.minor.derivative())
            midpointIntegrand = midpointU.multiplied(by: midpointJets.minor.derivative())
        }

        let span = upper - lower
        let midpointContribution = midpointIntegrand.coefficients[0].scaled(by: span)
        let secondDerivativeBound = intervalIntegrand.coefficients[2]
            .scaled(by: 2.0)
            .maximumAbsoluteValue
        let analyticError = (secondDerivativeBound * span * span * span / 24.0).nextUp
        let floatingPointError = Double.ulpOfOne * max(
            midpointContribution.maximumAbsoluteValue,
            analyticError
        ) * 65_536.0
        let totalError = (analyticError + floatingPointError).nextUp
        let midpointEnclosure = SurfaceParameterAreaBounds(
            lower: (midpointContribution.lower - totalError).nextDown,
            upper: (midpointContribution.upper + totalError).nextUp
        )
        // The corrected midpoint rule pushes the analytic remainder to the
        // third derivative, whose interval inflation near a square-root
        // shoulder is offset by the extra span power; both enclosures
        // certify the same integral, so their overlap does too.
        let correctedContribution = midpointContribution.adding(
            midpointIntegrand.coefficients[2].scaled(
                by: span * span * span / 12.0
            )
        )
        let thirdDerivativeBound = intervalIntegrand.coefficients[3]
            .scaled(by: 6.0)
            .maximumAbsoluteValue
        let correctedAnalyticError = (
            thirdDerivativeBound * span * span * span * span / 192.0
        ).nextUp
        let correctedFloatingPointError = Double.ulpOfOne * max(
            correctedContribution.maximumAbsoluteValue,
            correctedAnalyticError
        ) * 65_536.0
        let correctedTotalError = (
            correctedAnalyticError + correctedFloatingPointError
        ).nextUp
        let correctedEnclosure = SurfaceParameterAreaBounds(
            lower: (correctedContribution.lower - correctedTotalError).nextDown,
            upper: (correctedContribution.upper + correctedTotalError).nextUp
        )
        let overlapLower = max(midpointEnclosure.lower, correctedEnclosure.lower)
        let overlapUpper = min(midpointEnclosure.upper, correctedEnclosure.upper)
        guard overlapLower <= overlapUpper else {
            return midpointEnclosure.width <= correctedEnclosure.width
                ? midpointEnclosure
                : correctedEnclosure
        }
        return SurfaceParameterAreaBounds(
            lower: overlapLower,
            upper: overlapUpper
        )
    }

    private func geometricFallbackBounds(
        lower: Double,
        upper: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        configuration: Configuration,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        let ranges = try geometryRanges(
            parameter: Interval(lower: lower, upper: upper),
            configuration: configuration,
            tolerance: tolerance
        )
        if isPlaneRole(curve, configuration: configuration) {
            let coordinateRanges = planeCoordinateRanges(
                ranges,
                configuration: configuration,
                uShift: uShift
            )
            let start = try curve.intersection.internalParameter(
                for: curve.role,
                atNormalizedFraction: wrappedEvaluationFraction(
                    lower / (2.0 * Double.pi),
                    curve: curve
                ),
                tolerance: tolerance
            )
            let end = try curve.intersection.internalParameter(
                for: curve.role,
                atNormalizedFraction: wrappedEvaluationFraction(
                    upper / (2.0 * Double.pi),
                    curve: curve
                ),
                tolerance: tolerance
            )
            let uRange = coordinateRanges.u
            let vRange = coordinateRanges.v
                .expanded(toInclude: start.v)
                .expanded(toInclude: end.v)
            let endpointVDelta = Interval.scalar(end.v).subtracting(.scalar(start.v))
            let centerU = uRange.lower + (uRange.upper - uRange.lower) * 0.5
            let centerContribution = Interval.scalar(centerU).multiplied(
                by: endpointVDelta
            )
            // The plane-torus section is an algebraic plane curve of degree at
            // most four. This subarc lies in the complete UV rectangle and hence
            // in its half-diagonal disk. Crofton's formula bounds all degree-four
            // curve length in that disk by 4πρ. Total variation in plane-v cannot
            // exceed that local spatial length, including at quartic endpoints.
            let localDiskRadius = (
                0.5 * hypot(uRange.width, vRange.width)
            ).nextUp
            let sectionLengthBound = (4.0 * Double.pi * localDiskRadius).nextUp
            let centeredError = (
                uRange.width * 0.5 * sectionLengthBound
            ).nextUp
            return SurfaceParameterAreaBounds(
                lower: (centerContribution.lower - centeredError).nextDown,
                upper: (centerContribution.upper + centeredError).nextUp
            )
        }

        let deltaMinor = minorDeltaEnclosure(
            lower: lower,
            upper: upper,
            configuration: configuration,
            minorRange: ranges.minor
        )
        // The cell's own radial frame usually pins the major angle to a
        // narrow window; only a frame that degenerates on the cell falls
        // back to the whole period.
        var majorAngleRange = Interval(
            lower: 0.0,
            upper: (2.0 * Double.pi).nextUp
        )
        if let localized = try localizedTorusAngleRange(
            lower: lower,
            upper: upper,
            curve: curve,
            ranges,
            configuration: configuration,
            tolerance: tolerance
        ) {
            majorAngleRange = localized
        }
        let shiftedAngle = Interval(
            lower: (uShift + majorAngleRange.lower).nextDown,
            upper: (uShift + majorAngleRange.upper).nextUp
        )
        let product = shiftedAngle.multiplied(by: deltaMinor)
        return SurfaceParameterAreaBounds(lower: product.lower, upper: product.upper)
    }

    private func geometryJets(
        parameter: Interval,
        configuration: Configuration
    ) throws -> GeometryJets {
        let t = Jet.variable(parameter)
        let minor: Jet
        switch configuration.componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            minor = t
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            minor = t.adding(.constant(configuration.lowerMinorAngle))
        case .boundedMinorAngle:
            let midpoint = configuration.lowerMinorAngle
                + (configuration.upperMinorAngle - configuration.lowerMinorAngle) * 0.5
            let halfSpan = (configuration.upperMinorAngle
                - configuration.lowerMinorAngle) * 0.5
            minor = .constant(midpoint).subtracting(
                t.sineAndCosine().cosine.scaled(by: halfSpan)
            )
        }
        let minorTrigonometry = minor.sineAndCosine()
        let radialScale = Jet.constant(configuration.majorRadius).adding(
            minorTrigonometry.cosine.scaled(by: configuration.minorRadius)
        )
        let axialTerm = Jet.constant(configuration.centerDistance).adding(
            minorTrigonometry.sine.scaled(
                by: configuration.minorRadius * configuration.axialNormal
            )
        )
        let discriminant = radialScale
            .multiplied(by: radialScale)
            .scaled(by: configuration.radialNormalLength * configuration.radialNormalLength)
            .subtracting(axialTerm.multiplied(by: axialTerm))
        let transverseMagnitude = try discriminant.squareRoot()
        let transverseSign: Double
        switch configuration.componentKind {
        case .negativeFullBranch, .negativeInnerTangencyBranch:
            transverseSign = -1.0
        case .positiveFullBranch, .positiveInnerTangencyBranch:
            transverseSign = 1.0
        case .boundedMinorAngle:
            guard parameter.upper <= Double.pi || parameter.lower >= Double.pi else {
                throw LocalProofFailure.intervalSingularity
            }
            transverseSign = parameter.upper <= Double.pi ? 1.0 : -1.0
        }
        let inverseRadialNormal = 1.0 / configuration.radialNormalLength
        return GeometryJets(
            along: axialTerm.scaled(by: -inverseRadialNormal),
            across: transverseMagnitude.scaled(by: transverseSign * inverseRadialNormal),
            height: minorTrigonometry.sine.scaled(by: configuration.minorRadius),
            minor: minor
        )
    }

    private func geometryRanges(
        parameter: Interval,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> GeometryRanges {
        let t = Jet.variable(parameter)
        let minor: Jet
        switch configuration.componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            minor = t
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            minor = t.adding(.constant(configuration.lowerMinorAngle))
        case .boundedMinorAngle:
            let midpoint = configuration.lowerMinorAngle
                + (configuration.upperMinorAngle - configuration.lowerMinorAngle) * 0.5
            let halfSpan = (configuration.upperMinorAngle
                - configuration.lowerMinorAngle) * 0.5
            minor = .constant(midpoint).subtracting(
                t.sineAndCosine().cosine.scaled(by: halfSpan)
            )
        }
        let trigonometry = minor.sineAndCosine()
        let radialScale = Jet.constant(configuration.majorRadius).adding(
            trigonometry.cosine.scaled(by: configuration.minorRadius)
        ).coefficients[0]
        let axialTerm = Jet.constant(configuration.centerDistance).adding(
            trigonometry.sine.scaled(
                by: configuration.minorRadius * configuration.axialNormal
            )
        ).coefficients[0]
        let discriminant = radialScale
            .multiplied(by: radialScale)
            .scaled(by: configuration.radialNormalLength * configuration.radialNormalLength)
            .subtracting(axialTerm.multiplied(by: axialTerm))
        let classificationTolerance = max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne * configuration.characteristicLength
                * configuration.characteristicLength * 2_048.0
        )
        guard discriminant.upper >= -classificationTolerance else {
            throw KernelError(
                phase: .topology,
                code: .intersectionFailure,
                residual: -discriminant.upper,
                tolerance: tolerance,
                message: "A certified plane-torus area cell left its nonnegative discriminant domain."
            )
        }
        let maximumMagnitude = sqrt(max(discriminant.upper, 0.0)).nextUp
        let minimumMagnitude = discriminant.lower > 0.0
            ? sqrt(discriminant.lower).nextDown
            : 0.0
        let transverse: Interval
        switch configuration.componentKind {
        case .negativeFullBranch, .negativeInnerTangencyBranch:
            transverse = Interval(lower: -maximumMagnitude, upper: -minimumMagnitude)
        case .positiveFullBranch, .positiveInnerTangencyBranch:
            transverse = Interval(lower: minimumMagnitude, upper: maximumMagnitude)
        case .boundedMinorAngle:
            if parameter.upper <= Double.pi {
                transverse = Interval(lower: minimumMagnitude, upper: maximumMagnitude)
            } else if parameter.lower >= Double.pi {
                transverse = Interval(lower: -maximumMagnitude, upper: -minimumMagnitude)
            } else {
                transverse = Interval(lower: -maximumMagnitude, upper: maximumMagnitude)
            }
        }
        let inverseRadialNormal = 1.0 / configuration.radialNormalLength
        return GeometryRanges(
            along: axialTerm.scaled(by: -inverseRadialNormal),
            across: transverse.scaled(by: inverseRadialNormal),
            height: trigonometry.sine.coefficients[0].scaled(by: configuration.minorRadius),
            minor: minor.coefficients[0]
        )
    }

    private func planeCoordinateJets(
        _ geometry: GeometryJets,
        configuration: Configuration,
        uShift: Double
    ) -> (u: Jet, v: Jet) {
        let centerOffset = configuration.torusCenter - configuration.planeOrigin
        let u = Jet.constant(centerOffset.dot(configuration.planeBasisU) + uShift)
            .adding(geometry.along.scaled(
                by: configuration.radialNormal.dot(configuration.planeBasisU)
            ))
            .adding(geometry.across.scaled(
                by: configuration.radialPerpendicular.dot(configuration.planeBasisU)
            ))
            .adding(geometry.height.scaled(
                by: configuration.torusAxis.dot(configuration.planeBasisU)
            ))
        let v = Jet.constant(centerOffset.dot(configuration.planeBasisV))
            .adding(geometry.along.scaled(
                by: configuration.radialNormal.dot(configuration.planeBasisV)
            ))
            .adding(geometry.across.scaled(
                by: configuration.radialPerpendicular.dot(configuration.planeBasisV)
            ))
            .adding(geometry.height.scaled(
                by: configuration.torusAxis.dot(configuration.planeBasisV)
            ))
        return (u, v)
    }

    private func planeCoordinateRanges(
        _ geometry: GeometryRanges,
        configuration: Configuration,
        uShift: Double
    ) -> (u: Interval, v: Interval) {
        let centerOffset = configuration.torusCenter - configuration.planeOrigin
        let u = Interval.scalar(centerOffset.dot(configuration.planeBasisU) + uShift)
            .adding(geometry.along.scaled(
                by: configuration.radialNormal.dot(configuration.planeBasisU)
            ))
            .adding(geometry.across.scaled(
                by: configuration.radialPerpendicular.dot(configuration.planeBasisU)
            ))
            .adding(geometry.height.scaled(
                by: configuration.torusAxis.dot(configuration.planeBasisU)
            ))
        let v = Interval.scalar(centerOffset.dot(configuration.planeBasisV))
            .adding(geometry.along.scaled(
                by: configuration.radialNormal.dot(configuration.planeBasisV)
            ))
            .adding(geometry.across.scaled(
                by: configuration.radialPerpendicular.dot(configuration.planeBasisV)
            ))
            .adding(geometry.height.scaled(
                by: configuration.torusAxis.dot(configuration.planeBasisV)
            ))
        return (u, v)
    }

    private func torusAngleJet(
        _ geometry: GeometryJets,
        configuration: Configuration,
        reference: Double
    ) throws -> Jet {
        let x = geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.torusBasisU)
        ).adding(geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.torusBasisU)
        ))
        let y = geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.torusBasisV)
        ).adding(geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.torusBasisV)
        ))
        let angle = try angleBounds(x: x.coefficients[0], y: y.coefficients[0], reference: reference)
        let numerator = x.multiplied(by: y.derivative())
            .subtracting(y.multiplied(by: x.derivative()))
        let denominator = x.multiplied(by: x).adding(y.multiplied(by: y))
        let derivative = try numerator.divided(by: denominator)
        return Jet.fromCoefficients([
            angle,
            derivative.coefficients[0],
            derivative.coefficients[1].scaled(by: 0.5),
            derivative.coefficients[2].scaled(by: 1.0 / 3.0),
        ])
    }

    private func torusAngleRange(
        _ geometry: GeometryRanges,
        configuration: Configuration,
        reference: Double
    ) throws -> Interval {
        let x = geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.torusBasisU)
        ).adding(geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.torusBasisU)
        ))
        let y = geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.torusBasisV)
        ).adding(geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.torusBasisV)
        ))
        return try angleBounds(x: x, y: y, reference: reference)
    }

    private func localizedTorusAngleRange(
        lower: Double,
        upper: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        _ geometry: GeometryRanges,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        let reference = try curve.intersection.internalParameter(
            for: curve.role,
            atNormalizedFraction: wrappedEvaluationFraction(
                (lower + (upper - lower) * 0.5) / (2.0 * Double.pi),
                curve: curve
            ),
            tolerance: tolerance
        ).u
        do {
            return try torusAngleRange(
                geometry,
                configuration: configuration,
                reference: reference
            )
        } catch is LocalProofFailure {
            // A singular radial box or a periodic seam cannot certify a
            // localized angle. The caller retains the complete-period
            // enclosure, which is conservative for both flux contracts.
            return nil
        }
    }

    private func angleBounds(
        x: Interval,
        y: Interval,
        reference: Double
    ) throws -> Interval {
        guard (x.containsZero && y.containsZero) == false else {
            throw LocalProofFailure.intervalSingularity
        }
        let period = 2.0 * Double.pi
        let corners = [
            (x.lower, y.lower),
            (x.lower, y.upper),
            (x.upper, y.lower),
            (x.upper, y.upper),
        ]
        let values = corners.map { corner -> Double in
            var angle = atan2(corner.1, corner.0)
            if angle < 0.0 { angle += period }
            return angle + (round((reference - angle) / period) * period)
        }
        let lower = (values.min() ?? -.infinity).nextDown
        let upper = (values.max() ?? .infinity).nextUp
        let roundoff = Double.ulpOfOne * max(abs(reference), 1.0) * 8_192.0
        // The geometry certificate owns the pcurve's universal-cover sheet.
        // In particular, a nodal plane-torus branch can be continuous around
        // a negative node angle. Requiring a principal [0, 2pi] interval here
        // rejects that valid sheet and prevents refinement from converging.
        guard upper - lower < Double.pi,
              reference >= lower - roundoff,
              reference <= upper + roundoff else {
            throw LocalProofFailure.periodicSeam
        }
        return Interval(lower: lower, upper: upper)
    }



    private func wrappedEvaluationFraction(
        _ fraction: Double,
        curve: CertifiedAnalyticPairSurfaceParameterCurve
    ) -> Double {
        // Seam-lifted spans carry fractions outside [0, 1]; a closed
        // intersection accepts any periodic representative, so evaluation
        // wraps to the principal one.
        guard case .periodic = curve.intersection.curve.parameterDomain else {
            return fraction
        }
        let wrapped = fraction - fraction.rounded(.down)
        return wrapped
    }

    private func minorDeltaEnclosure(
        lower: Double,
        upper: Double,
        configuration: Configuration,
        minorRange: Interval
    ) -> Interval {
        let signedDelta = minorAngle(at: upper, configuration: configuration)
            - minorAngle(at: lower, configuration: configuration)
        let monotone: Bool
        switch configuration.componentKind {
        case .negativeFullBranch, .positiveFullBranch,
             .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            monotone = true
        case .boundedMinorAngle:
            // The cosine substitution is monotone away from its turning
            // points at multiples of pi.
            let period = Double.pi
            let lowerCell = (lower / period).rounded(.down)
            let upperCell = (upper / period).rounded(.up)
            monotone = upperCell - lowerCell <= 1.0
        }
        if monotone {
            return .scalar(signedDelta)
        }
        let variation = ((minorRange.upper - minorRange.lower) * 2.0).nextUp
        return Interval(
            lower: (-variation).nextDown,
            upper: variation.nextUp
        )
    }

    private func minorAngle(
        at parameter: Double,
        configuration: Configuration
    ) -> Double {
        switch configuration.componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return parameter
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            return configuration.lowerMinorAngle + parameter
        case .boundedMinorAngle:
            let midpoint = configuration.lowerMinorAngle
                + (configuration.upperMinorAngle - configuration.lowerMinorAngle) * 0.5
            let halfSpan = (configuration.upperMinorAngle
                - configuration.lowerMinorAngle) * 0.5
            return midpoint - halfSpan * cos(parameter)
        }
    }

    private func isPlaneRole(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        configuration: Configuration
    ) -> Bool {
        guard let planeTorusCurve = curve.intersection.planeTorusCurve else {
            return false
        }
        return curve.intersection.surface(for: curve.role)
            == planeTorusCurve.planeSurface
    }

    private func usesSpecializedPlaneTorusPath(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        requireTorusRole: Bool
    ) -> Bool {
        guard let source = curve.intersection.planeTorusCurve else {
            return false
        }
        guard requireTorusRole else { return true }
        return curve.intersection.surface(for: curve.role) == source.torusSurface
    }

    private func outwardWidthSum(_ items: [WorkItem]) -> Double {
        var result = 0.0
        for item in items {
            result = (result + item.width).nextUp
        }
        return result
    }

    /// Replaces one active cell's width with an already outward-rounded
    /// child sum without understating the new aggregate. Callers combine
    /// this constant-time update with geometrically spaced full sums.
    private func replacingWidthUpperBound(
        _ total: Double,
        removing removed: Double,
        addingUpperBound added: Double
    ) -> Double {
        let remainder = (total - removed).nextUp
        return max((remainder + added).nextUp, 0.0)
    }

    private func replacingWidthUpperBound(
        _ total: Double,
        removing removed: Double,
        addingFirst first: Double,
        second: Double
    ) -> Double {
        var result = (total - removed).nextUp
        result = (result + first).nextUp
        result = (result + second).nextUp
        return max(result, 0.0)
    }

    private func makeConfiguration(
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        guard let source = curve.intersection.planeTorusCurve else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "The specialized analytic-pair path lost its required plane-torus source."
            )
        }
        let planeData = try planeDefinition(source.planeSurface, tolerance: tolerance)
        let torusData = try torusDefinition(source.torusSurface, tolerance: tolerance)
        let axisProjection = planeData.normal.dot(torusData.axis)
        let projectedNormal = planeData.normal - torusData.axis * axisProjection
        let radialNormalLength = projectedNormal.length
        guard radialNormalLength > tolerance.angle else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: radialNormalLength,
                tolerance: tolerance,
                message: "Axial plane-torus sections must use their exact circle pcurves."
            )
        }
        let radialNormal = try projectedNormal.normalized(
            tolerance: tolerance.distance
        )
        let radialPerpendicular = try torusData.axis.cross(radialNormal).normalized(
            tolerance: tolerance.distance
        )
        return Configuration(
            planeOrigin: planeData.origin,
            planeNormal: planeData.normal,
            planeBasisU: planeData.basisU,
            planeBasisV: planeData.basisV,
            torusCenter: torusData.center,
            torusAxis: torusData.axis,
            torusBasisU: torusData.basisU,
            torusBasisV: torusData.basisV,
            majorRadius: torusData.majorRadius,
            minorRadius: torusData.minorRadius,
            radialNormal: radialNormal,
            radialPerpendicular: radialPerpendicular,
            radialNormalLength: radialNormalLength,
            axialNormal: axisProjection,
            centerDistance: (torusData.center - planeData.origin).dot(planeData.normal),
            componentKind: source.componentKind,
            lowerMinorAngle: source.lowerMinorAngle,
            upperMinorAngle: source.upperMinorAngle
        )
    }

    private func planeDefinition(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> (
        origin: Point3D,
        normal: Vector3D,
        basisU: Vector3D,
        basisV: Vector3D
    ) {
        switch surface {
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let basisU = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            return (plane.origin, normal, basisU, normal.cross(basisU))
        case let .analytic(.plane(origin, normalValue)):
            let normal = try normalValue.normalized(tolerance: tolerance.distance)
            let reference = abs(normal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
            let basisU = try normal.cross(reference).normalized(
                tolerance: tolerance.distance
            )
            let basisV = try normal.cross(basisU).normalized(
                tolerance: tolerance.distance
            )
            return (origin, normal, basisU, basisV)
        case .cylinder, .analytic, .bSpline, .procedural:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic-pair area certificate requires an exact plane source."
            )
        }
    }

    private func torusDefinition(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> (
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        basisU: Vector3D,
        basisV: Vector3D
    ) {
        guard case let .analytic(.torus(center, axisValue, majorRadius, minorRadius)) = surface else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic-pair area certificate requires an exact torus source."
            )
        }
        let axis = try axisValue.normalized(tolerance: tolerance.distance)
        let reference = abs(axis.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
        let basisU = try axis.cross(reference).normalized(tolerance: tolerance.distance)
        let basisV = try axis.cross(basisU).normalized(tolerance: tolerance.distance)
        return (center, axis, majorRadius, minorRadius, basisU, basisV)
    }
}
