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
            let products = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return Interval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
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

        private static func trigonometricBounds(
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

    private let maximumSubdivisionDepth: Int
    private let maximumCellCount: Int

    init(
        maximumSubdivisionDepth: Int = 64,
        // Square-root singularities at bounded-window discriminant roots
        // refine along logarithmic endpoint ladders, but their interior
        // shoulder still multiplies the equalized cell population well past
        // the historical budget.
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
        guard case .torus = integrand else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair flux integration requires the exact torus role."
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
            do {
                return try midpointFluxBounds(
                    lower: cellLower,
                    upper: cellUpper,
                    curve: curve,
                    configuration: configuration,
                    integrand: integrand,
                    tolerance: tolerance
                )
            } catch LocalProofFailure.intervalSingularity,
                    LocalProofFailure.periodicSeam {
                return try geometricFluxFallbackBounds(
                    lower: cellLower,
                    upper: cellUpper,
                    curve: curve,
                    configuration: configuration,
                    integrand: integrand,
                    tolerance: tolerance
                )
            }
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
                childWidthSum += child.width
                heap.push(child)
            }
            subdivisionCount += 1
            if subdivisionCount.isMultiple(of: 128) {
                // Incremental width tracking drifts across many updates,
                // so the loop periodically recomputes the exact sum.
                totalWidth = outwardWidthSum(heap.storage)
            } else {
                totalWidth = (
                    totalWidth - item.width + childWidthSum
                ).nextUp
            }
        }
        var result = Interval.zero
        for item in heap.storage {
            result = result.adding(Interval(
                lower: item.bounds.lower,
                upper: item.bounds.upper
            ))
        }
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
            if subdivisionCount.isMultiple(of: 128) {
                totalWidth = outwardWidthSum(heap.storage)
            } else {
                totalWidth = max(
                    0.0,
                    (totalWidth - item.width + children[0].width + children[1].width).nextUp
                )
            }
            if totalWidth <= internalTargetWidth {
                totalWidth = outwardWidthSum(heap.storage)
            }
        }

        var result = SurfaceParameterAreaBounds.zero
        for item in heap.storage {
            result = result.adding(item.bounds)
        }
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

    func parameterEnclosures(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try tolerance.validate()
        try curve.validate(
            on: curve.intersection.surface(for: curve.role),
            tolerance: tolerance
        )
        guard maximumWidth.isFinite, maximumWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: maximumWidth,
                tolerance: tolerance,
                message: "Analytic-pair pcurve enclosure requires a finite positive width."
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
            lowerFraction: 0.0,
            upperFraction: 1.0,
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
               max(ranges.u.width, ranges.v.width) <= maximumWidth {
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
                    residual: ranges.map { max($0.u.width, $0.v.width) },
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
            atNormalizedFraction: midpoint / (2.0 * Double.pi),
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
            analyticError,
            1.0
        ) * 65_536.0
        let totalError = (analyticError + floatingPointError).nextUp
        return Interval(
            lower: (midpointContribution.lower - totalError).nextDown,
            upper: (midpointContribution.upper + totalError).nextUp
        )
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
        if let reference = try? curve.intersection.internalParameter(
            for: curve.role,
            atNormalizedFraction: (
                lower + (upper - lower) * 0.5
            ) / (2.0 * Double.pi),
            tolerance: tolerance
        ).u, let localized = try? torusAngleRange(
            ranges,
            configuration: configuration,
            reference: reference
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
        let deltaMinor = Interval.scalar(
            minorAngle(at: upper, configuration: configuration)
                - minorAngle(at: lower, configuration: configuration)
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
        let bounds: SurfaceParameterAreaBounds
        do {
            bounds = try midpointBounds(
                lower: lower,
                upper: upper,
                curve: curve,
                configuration: configuration,
                uShift: uShift,
                tolerance: tolerance
            )
        } catch LocalProofFailure.intervalSingularity {
            bounds = try geometricFallbackBounds(
                lower: lower,
                upper: upper,
                curve: curve,
                configuration: configuration,
                uShift: uShift,
                tolerance: tolerance
            )
        } catch LocalProofFailure.periodicSeam {
            bounds = try geometricFallbackBounds(
                lower: lower,
                upper: upper,
                curve: curve,
                configuration: configuration,
                uShift: uShift,
                tolerance: tolerance
            )
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
                atNormalizedFraction: midpoint / (2.0 * Double.pi),
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
            analyticError,
            1.0
        ) * 65_536.0
        let totalError = (analyticError + floatingPointError).nextUp
        return SurfaceParameterAreaBounds(
            lower: (midpointContribution.lower - totalError).nextDown,
            upper: (midpointContribution.upper + totalError).nextUp
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
                atNormalizedFraction: lower / (2.0 * Double.pi),
                tolerance: tolerance
            )
            let end = try curve.intersection.internalParameter(
                for: curve.role,
                atNormalizedFraction: upper / (2.0 * Double.pi),
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

        let deltaMinor = Interval.scalar(
            minorAngle(at: upper, configuration: configuration)
                - minorAngle(at: lower, configuration: configuration)
        )
        // The cell's own radial frame usually pins the major angle to a
        // narrow window; only a frame that degenerates on the cell falls
        // back to the whole period.
        var majorAngleRange = Interval(
            lower: 0.0,
            upper: (2.0 * Double.pi).nextUp
        )
        if let reference = try? curve.intersection.internalParameter(
            for: curve.role,
            atNormalizedFraction: (
                lower + (upper - lower) * 0.5
            ) / (2.0 * Double.pi),
            tolerance: tolerance
        ).u, let localized = try? torusAngleRange(
            ranges,
            configuration: configuration,
            reference: reference
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
        guard lower >= -roundoff,
              upper <= period + roundoff,
              upper - lower < Double.pi else {
            throw LocalProofFailure.periodicSeam
        }
        return Interval(
            lower: max(lower, 0.0).nextDown,
            upper: min(upper, period).nextUp
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

    private func outwardWidthSum(_ items: [WorkItem]) -> Double {
        var result = 0.0
        for item in items {
            result = (result + item.width).nextUp
        }
        return result
    }

    private func makeConfiguration(
        curve: CertifiedAnalyticPairSurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        guard let source = curve.intersection.planeTorusCurve else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Certified analytic-pair area integration currently requires a plane-torus component."
            )
        }
        if source.componentKind == .negativeInnerTangencyBranch
            || source.componentKind == .positiveInnerTangencyBranch {
            // Nodal plane-torus edges are complete Geometry results, but this
            // Topology path currently proves area only for regular source
            // pcurves. Callers reach this guard through area, flux, or parameter
            // enclosure integration and must not receive a successful bound
            // until a double-root variation certificate is implemented.
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Nodal plane-torus pcurves require a dedicated double-root area certificate."
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
        case .cylinder, .analytic, .bSpline:
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
