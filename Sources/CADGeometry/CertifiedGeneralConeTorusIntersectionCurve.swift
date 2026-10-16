import CADCore
import Synchronization
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

public struct CertifiedGeneralConeTorusIntersectionCurve: Hashable, Sendable {
    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct ThirdOrderDifferentialGeometry {
        let position: Point3D
        let firstDerivative: Vector3D
        let secondDerivative: Vector3D
        let thirdDerivative: Vector3D
    }

    public typealias ApexReduction =
        CertifiedConeTorusApexIntersectionCurve

    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double
        let centerDirection: Vector3D
        let radialU: Vector3D
        let radialV: Vector3D

        func direction(at angle: Double) -> Vector3D {
            centerDirection
                + radialU * cos(angle)
                + radialV * sin(angle)
        }

        func directionFirstDerivative(at angle: Double) -> Vector3D {
            radialU * -sin(angle) + radialV * cos(angle)
        }

        func directionSecondDerivative(at angle: Double) -> Vector3D {
            radialU * -cos(angle) + radialV * -sin(angle)
        }

        func directionThirdDerivative(at angle: Double) -> Vector3D {
            radialU * sin(angle) + radialV * -cos(angle)
        }
    }

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct Configuration {
        let cone: Cone
        let torus: Torus
        let lowerSlant: Double
        let upperSlant: Double
        let characteristicLength: Double

        func generatorPoint(angle: Double, slant: Double) -> Point3D {
            cone.apex + cone.direction(at: angle) * slant
        }

        func coefficients(at angle: Double, using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
            let offset = cone.apex - torus.center
            let direction = cone.direction(at: angle)
            let pointSquared = offset.dot(offset)
            let pointDirection = offset.dot(direction)
            let axialPoint = offset.dot(torus.axis)
            let axialDirection = direction.dot(torus.axis)
            let q0 = pointSquared
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            let q1 = 2.0 * pointDirection
            let radial0 = pointSquared - axialPoint * axialPoint
            let radial1 = 2.0 * (
                pointDirection - axialPoint * axialDirection
            )
            let radial2 = 1.0 - axialDirection * axialDirection
            let majorFactor = 4.0 * torus.majorRadius * torus.majorRadius
            return [
                q0 * q0 - majorFactor * radial0,
                2.0 * q0 * q1 - majorFactor * radial1,
                q1 * q1 + 2.0 * q0 - majorFactor * radial2,
                2.0 * q1,
                1.0,
            ]
        }
    }

    private struct Certificate: Hashable, Sendable {
        let branchCount: Int
        let processedCellCount: Int
        let differentialPartitions: [DifferentialPartition]
        let differentialPartitionIndex: DifferentialPartitionIndex
        let traceParameters: [Double]
        let slantsByBranch: [[Double]]

        init(
            branchCount: Int,
            processedCellCount: Int,
            differentialPartitions: [DifferentialPartition],
            traceParameters: [Double],
            slantsByBranch: [[Double]]
        , using execution: inout OriginalQueryExecution) throws {
            let index = try DifferentialPartitionIndex(
                partitions: differentialPartitions, using: &execution
            )
            self.branchCount = branchCount
            self.processedCellCount = processedCellCount
            self.differentialPartitions = index.partitions
            self.differentialPartitionIndex = index
            self.traceParameters = traceParameters
            self.slantsByBranch = slantsByBranch
        }

        static func == (lhs: Certificate, rhs: Certificate) -> Bool {
            lhs.branchCount == rhs.branchCount
                && lhs.processedCellCount == rhs.processedCellCount
                && lhs.differentialPartitions == rhs.differentialPartitions
                && lhs.traceParameters == rhs.traceParameters
                && lhs.slantsByBranch == rhs.slantsByBranch
        }

        // Hashing is on the hot path of every lift evaluation (validation
        // memoization keys), and quality-refined partition arrays hold
        // thousands of elements; hashing cheap discriminants keeps the
        // Hashable contract (equal values agree on every hashed field)
        // while equality still compares the full payload.
        func hash(into hasher: inout Hasher) {
            hasher.combine(branchCount)
            hasher.combine(processedCellCount)
            hasher.combine(differentialPartitions.count)
            hasher.combine(traceParameters.count)
            hasher.combine(traceParameters.first ?? 0.0)
            hasher.combine(traceParameters.last ?? 0.0)
            hasher.combine(slantsByBranch.first?.first ?? 0.0)
            hasher.combine(slantsByBranch.last?.last ?? 0.0)
        }

        package func chargeStructuralComparisonWork<A: ExactScalarAdmission & ~Copyable>(
            using execution: inout A
        ) throws {
            // DifferentialPartitionIndex is a derived query index and is
            // intentionally excluded from Certificate equality/hash payload.
            try execution.consumeWork(2)
            try execution.consumeWork(differentialPartitions.count)
            for _ in differentialPartitions {
                try CurrentTaskCancellationChecker().checkCancellation()
                try execution.consumeWork(10)
            }
            try execution.consumeWork(traceParameters.count)
            try execution.consumeWork(slantsByBranch.count)
            for row in slantsByBranch {
                try CurrentTaskCancellationChecker().checkCancellation()
                try execution.consumeWork(row.count)
            }
        }

        func referenceSlant(
            branchIndex: Int,
            at angle: Double
        , using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            if angle <= traceParameters[0] {
                return slantsByBranch[branchIndex][0]
            }
            if angle >= traceParameters[traceParameters.count - 1] {
                return slantsByBranch[branchIndex][
                    traceParameters.count - 1
                ]
            }
            var lower = 0
            var upper = traceParameters.count - 1
            while upper - lower > 1 {
                try execution.consumeWork(1)
                let middle = (lower + upper) / 2
                if traceParameters[middle] <= angle {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            let span = traceParameters[upper] - traceParameters[lower]
            let fraction = span > 0.0
                ? (angle - traceParameters[lower]) / span
                : 0.0
            return slantsByBranch[branchIndex][lower]
                + (
                    slantsByBranch[branchIndex][upper]
                        - slantsByBranch[branchIndex][lower]
                ) * fraction
        }
    }

    private struct DifferentialPartition: Hashable, Sendable {
        let lowerNormalizedAngle: Double
        let upperNormalizedAngle: Double
        let lowerSlant: Double
        let upperSlant: Double
        let slantFirstDerivativeMagnitudeUpperBound: Double
        let slantSecondDerivativeMagnitudeUpperBound: Double
        let slantThirdDerivativeMagnitudeUpperBound: Double
        let firstDerivativeMagnitudeUpperBound: Double
        let secondDerivativeMagnitudeUpperBound: Double
        let thirdDerivativeMagnitudeUpperBound: Double
    }

    /// Exact range-maximum acceleration for the immutable differential
    /// certificate. A node summary is accepted only when every partition in
    /// that node overlaps the query; partially overlapping nodes descend to
    /// their children and retain the original partition predicate at leaves.
    private struct DifferentialPartitionIndex: Sendable {
        private struct Node: Sendable {
            let minimumLower: Double
            let maximumLower: Double
            let minimumUpper: Double
            let maximumUpper: Double
            let minimumSlantLower: Double
            let maximumSlantLower: Double
            let minimumSlantUpper: Double
            let maximumSlantUpper: Double
            let maximumSlantFirstDerivative: Double
            let maximumSlantSecondDerivative: Double
            let maximumSlantThirdDerivative: Double
            let maximumFirstDerivative: Double
            let maximumSecondDerivative: Double
            let maximumThirdDerivative: Double
            let partitionIndex: Int?
            let leftIndex: Int?
            let rightIndex: Int?
        }

        let partitions: [DifferentialPartition]
        private let nodes: [Node]
        private let rootIndex: Int?

        init(partitions: [DifferentialPartition], using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            let sorted = try CertifiedAnalyticCurveEvaluation.sorted(partitions, using: &execution) { lhs, rhs in
                if lhs.lowerNormalizedAngle != rhs.lowerNormalizedAngle {
                    return lhs.lowerNormalizedAngle < rhs.lowerNormalizedAngle
                }
                if lhs.upperNormalizedAngle != rhs.upperNormalizedAngle {
                    return lhs.upperNormalizedAngle < rhs.upperNormalizedAngle
                }
                if lhs.lowerSlant != rhs.lowerSlant {
                    return lhs.lowerSlant < rhs.lowerSlant
                }
                if lhs.upperSlant != rhs.upperSlant {
                    return lhs.upperSlant < rhs.upperSlant
                }
                if lhs.firstDerivativeMagnitudeUpperBound
                    != rhs.firstDerivativeMagnitudeUpperBound {
                    return lhs.firstDerivativeMagnitudeUpperBound
                        < rhs.firstDerivativeMagnitudeUpperBound
                }
                if lhs.secondDerivativeMagnitudeUpperBound
                    != rhs.secondDerivativeMagnitudeUpperBound {
                    return lhs.secondDerivativeMagnitudeUpperBound
                        < rhs.secondDerivativeMagnitudeUpperBound
                }
                return lhs.thirdDerivativeMagnitudeUpperBound
                    < rhs.thirdDerivativeMagnitudeUpperBound
            }
            self.partitions = sorted
            var summaries: [Node] = []
            let doubledCount = try exactScalarCount(sorted.count, 2, multiply: true)
            try CertifiedAnalyticCurveEvaluation.reserveCapacity(max(0, doubledCount - 1), in: &summaries, using: &execution)
            func build(lower: Int, upper: Int, using execution: inout OriginalQueryExecution) throws -> Int {
                try execution.consumeWork(1)
                if upper - lower == 1 {
                    let partition = sorted[lower]
                    let index = summaries.count
                    summaries.append(Node(
                        minimumLower: partition.lowerNormalizedAngle,
                        maximumLower: partition.lowerNormalizedAngle,
                        minimumUpper: partition.upperNormalizedAngle,
                        maximumUpper: partition.upperNormalizedAngle,
                        minimumSlantLower: partition.lowerSlant,
                        maximumSlantLower: partition.lowerSlant,
                        minimumSlantUpper: partition.upperSlant,
                        maximumSlantUpper: partition.upperSlant,
                        maximumSlantFirstDerivative:
                            partition.slantFirstDerivativeMagnitudeUpperBound,
                        maximumSlantSecondDerivative:
                            partition.slantSecondDerivativeMagnitudeUpperBound,
                        maximumSlantThirdDerivative:
                            partition.slantThirdDerivativeMagnitudeUpperBound,
                        maximumFirstDerivative:
                            partition.firstDerivativeMagnitudeUpperBound,
                        maximumSecondDerivative:
                            partition.secondDerivativeMagnitudeUpperBound,
                        maximumThirdDerivative:
                            partition.thirdDerivativeMagnitudeUpperBound,
                        partitionIndex: lower,
                        leftIndex: nil,
                        rightIndex: nil
                    ))
                    return index
                }
                let middle = lower + (upper - lower) / 2
                let leftIndex = try build(lower: lower, upper: middle, using: &execution)
                let rightIndex = try build(lower: middle, upper: upper, using: &execution)
                let left = summaries[leftIndex]
                let right = summaries[rightIndex]
                let index = summaries.count
                summaries.append(Node(
                    minimumLower: min(
                        left.minimumLower,
                        right.minimumLower
                    ),
                    maximumLower: max(
                        left.maximumLower,
                        right.maximumLower
                    ),
                    minimumUpper: min(
                        left.minimumUpper,
                        right.minimumUpper
                    ),
                    maximumUpper: max(
                        left.maximumUpper,
                        right.maximumUpper
                    ),
                    minimumSlantLower: min(
                        left.minimumSlantLower,
                        right.minimumSlantLower
                    ),
                    maximumSlantLower: max(
                        left.maximumSlantLower,
                        right.maximumSlantLower
                    ),
                    minimumSlantUpper: min(
                        left.minimumSlantUpper,
                        right.minimumSlantUpper
                    ),
                    maximumSlantUpper: max(
                        left.maximumSlantUpper,
                        right.maximumSlantUpper
                    ),
                    maximumSlantFirstDerivative: max(
                        left.maximumSlantFirstDerivative,
                        right.maximumSlantFirstDerivative
                    ),
                    maximumSlantSecondDerivative: max(
                        left.maximumSlantSecondDerivative,
                        right.maximumSlantSecondDerivative
                    ),
                    maximumSlantThirdDerivative: max(
                        left.maximumSlantThirdDerivative,
                        right.maximumSlantThirdDerivative
                    ),
                    maximumFirstDerivative: max(
                        left.maximumFirstDerivative,
                        right.maximumFirstDerivative
                    ),
                    maximumSecondDerivative: max(
                        left.maximumSecondDerivative,
                        right.maximumSecondDerivative
                    ),
                    maximumThirdDerivative: max(
                        left.maximumThirdDerivative,
                        right.maximumThirdDerivative
                    ),
                    partitionIndex: nil,
                    leftIndex: leftIndex,
                    rightIndex: rightIndex
                ))
                return index
            }
            let root = sorted.isEmpty
                ? nil
                : try build(lower: 0, upper: sorted.count, using: &execution)
            self.nodes = summaries
            self.rootIndex = root
        }

        func bounds(
            overlappingLower lower: Double,
            upper: Double,
            slantLower: Double,
            slantUpper: Double
        , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds? {
            try execution.consumeWork(1)
            var found = false
            var first = -Double.infinity
            var second = -Double.infinity
            var third = -Double.infinity
            func visit(_ index: Int, using execution: inout OriginalQueryExecution) throws {
                try execution.consumeWork(1)
                let node = nodes[index]
                if node.minimumLower > upper
                    || node.maximumUpper < lower
                    || node.minimumSlantLower > slantUpper
                    || node.maximumSlantUpper < slantLower {
                    return
                }
                if node.maximumLower <= upper,
                   node.minimumUpper >= lower,
                   node.maximumSlantLower <= slantUpper,
                   node.minimumSlantUpper >= slantLower {
                    found = true
                    first = max(first, node.maximumFirstDerivative)
                    second = max(second, node.maximumSecondDerivative)
                    third = max(third, node.maximumThirdDerivative)
                    return
                }
                if let partitionIndex = node.partitionIndex {
                    let partition = partitions[partitionIndex]
                    guard partition.upperNormalizedAngle >= lower,
                          partition.lowerNormalizedAngle <= upper,
                          partition.upperSlant >= slantLower,
                          partition.lowerSlant <= slantUpper else {
                        return
                    }
                    found = true
                    first = max(
                        first,
                        partition.firstDerivativeMagnitudeUpperBound
                    )
                    second = max(
                        second,
                        partition.secondDerivativeMagnitudeUpperBound
                    )
                    third = max(
                        third,
                        partition.thirdDerivativeMagnitudeUpperBound
                    )
                    return
                }
                if let leftIndex = node.leftIndex { try visit(leftIndex, using: &execution) }
                if let rightIndex = node.rightIndex { try visit(rightIndex, using: &execution) }
            }
            if let rootIndex { try visit(rootIndex, using: &execution) }
            guard found else { return nil }
            return SpatialDifferentialMagnitudeBounds(
                first: first,
                second: second,
                third: third
            )
        }

        func maximumSlantFirstDerivative(
            overlappingLower lower: Double,
            upper: Double
        , using execution: inout OriginalQueryExecution) throws -> Double? {
            try execution.consumeWork(1)
            var found = false
            var maximum = -Double.infinity
            func visit(_ index: Int, using execution: inout OriginalQueryExecution) throws {
                try execution.consumeWork(1)
                let node = nodes[index]
                if node.minimumLower > upper
                    || node.maximumUpper < lower {
                    return
                }
                if node.maximumLower <= upper,
                   node.minimumUpper >= lower {
                    found = true
                    maximum = max(
                        maximum,
                        node.maximumSlantFirstDerivative
                    )
                    return
                }
                if let partitionIndex = node.partitionIndex {
                    let partition = partitions[partitionIndex]
                    guard partition.upperNormalizedAngle >= lower,
                          partition.lowerNormalizedAngle <= upper else {
                        return
                    }
                    found = true
                    maximum = max(
                        maximum,
                        partition.slantFirstDerivativeMagnitudeUpperBound
                    )
                    return
                }
                if let leftIndex = node.leftIndex { try visit(leftIndex, using: &execution) }
                if let rightIndex = node.rightIndex { try visit(rightIndex, using: &execution) }
            }
            if let rootIndex { try visit(rootIndex, using: &execution) }
            return found ? maximum : nil
        }

        func slantDifferentialBounds(
            overlappingLower lower: Double,
            upper: Double,
            slantLower: Double,
            slantUpper: Double
        , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds? {
            try execution.consumeWork(1)
            var found = false
            var first = -Double.infinity
            var second = -Double.infinity
            var third = -Double.infinity
            func visit(_ index: Int, using execution: inout OriginalQueryExecution) throws {
                try execution.consumeWork(1)
                let node = nodes[index]
                if node.minimumLower > upper
                    || node.maximumUpper < lower
                    || node.minimumSlantLower > slantUpper
                    || node.maximumSlantUpper < slantLower {
                    return
                }
                if node.maximumLower <= upper,
                   node.minimumUpper >= lower,
                   node.maximumSlantLower <= slantUpper,
                   node.minimumSlantUpper >= slantLower {
                    found = true
                    first = max(first, node.maximumSlantFirstDerivative)
                    second = max(second, node.maximumSlantSecondDerivative)
                    third = max(third, node.maximumSlantThirdDerivative)
                    return
                }
                if let partitionIndex = node.partitionIndex {
                    let partition = partitions[partitionIndex]
                    guard partition.upperNormalizedAngle >= lower,
                          partition.lowerNormalizedAngle <= upper,
                          partition.upperSlant >= slantLower,
                          partition.lowerSlant <= slantUpper else {
                        return
                    }
                    found = true
                    first = max(
                        first,
                        partition.slantFirstDerivativeMagnitudeUpperBound
                    )
                    second = max(
                        second,
                        partition.slantSecondDerivativeMagnitudeUpperBound
                    )
                    third = max(
                        third,
                        partition.slantThirdDerivativeMagnitudeUpperBound
                    )
                    return
                }
                if let leftIndex = node.leftIndex { try visit(leftIndex, using: &execution) }
                if let rightIndex = node.rightIndex { try visit(rightIndex, using: &execution) }
            }
            if let rootIndex { try visit(rootIndex, using: &execution) }
            guard found else { return nil }
            return SpatialDifferentialMagnitudeBounds(
                first: first,
                second: second,
                third: third
            )
        }

        func overlappingPartitions(
            lower: Double,
            upper: Double,
            slantLower: Double,
            slantUpper: Double
        , using execution: inout OriginalQueryExecution) throws -> [DifferentialPartition] {
            try execution.consumeWork(1)
            var result: [DifferentialPartition] = []
            var resultCapacity = result.count
            func visit(_ index: Int, using execution: inout OriginalQueryExecution) throws {
                try execution.consumeWork(1)
                let node = nodes[index]
                if node.minimumLower > upper
                    || node.maximumUpper < lower
                    || node.minimumSlantLower > slantUpper
                    || node.maximumSlantUpper < slantLower {
                    return
                }
                if let partitionIndex = node.partitionIndex {
                    let partition = partitions[partitionIndex]
                    guard partition.upperNormalizedAngle >= lower,
                          partition.lowerNormalizedAngle <= upper,
                          partition.upperSlant >= slantLower,
                          partition.lowerSlant <= slantUpper else {
                        return
                    }
                    try CertifiedAnalyticCurveEvaluation.append(partition, to: &result, using: &execution, capacity: &resultCapacity)
                    return
                }
                if let leftIndex = node.leftIndex { try visit(leftIndex, using: &execution) }
                if let rightIndex = node.rightIndex { try visit(rightIndex, using: &execution) }
            }
            if let rootIndex { try visit(rootIndex, using: &execution) }
            return result
        }
    }

    private struct Cell {
        let angle: Interval
        let slant: Interval
        let depth: Int
    }

    private struct Interval: Hashable, Sendable {
        let lower: Double
        let upper: Double

        init(_ lower: Double, _ upper: Double) {
            self.lower = min(lower, upper).nextDown
            self.upper = max(lower, upper).nextUp
        }

        static func constant(_ value: Double) -> Interval {
            Interval(value, value)
        }

        var width: Double { upper - lower }
        var midpoint: Double { lower + width * 0.5 }
        var containsZero: Bool { lower <= 0.0 && upper >= 0.0 }
        var minimumAbsoluteValue: Double {
            containsZero ? 0.0 : min(abs(lower), abs(upper)).nextDown
        }
        var maximumAbsoluteValue: Double {
            max(abs(lower), abs(upper)).nextUp
        }

        func adding(_ other: Interval) -> Interval {
            Interval(lower + other.lower, upper + other.upper)
        }

        func subtracting(_ other: Interval) -> Interval {
            Interval(lower - other.upper, upper - other.lower)
        }

        func multiplied(by other: Interval) -> Interval {
            let first = lower * other.lower
            let second = lower * other.upper
            let third = upper * other.lower
            let fourth = upper * other.upper
            return Interval(min(first, second, third, fourth), max(first, second, third, fourth))
        }

        func scaled(by scalar: Double) -> Interval {
            scalar >= 0.0
                ? Interval(lower * scalar, upper * scalar)
                : Interval(upper * scalar, lower * scalar)
        }

        func squared() -> Interval {
            if containsZero {
                return Interval(0.0, max(lower * lower, upper * upper))
            }
            return Interval(
                min(lower * lower, upper * upper),
                max(lower * lower, upper * upper)
            )
        }

        func divided(by other: Interval) -> Interval? {
            guard other.containsZero == false else { return nil }
            return multiplied(by: Interval(
                1.0 / other.upper,
                1.0 / other.lower
            ))
        }

        func intersection(with other: Interval) -> Interval? {
            let intersectionLower = max(lower, other.lower)
            let intersectionUpper = min(upper, other.upper)
            guard intersectionLower <= intersectionUpper else { return nil }
            return Interval(intersectionLower, intersectionUpper)
        }

        func hull(_ other: Interval) -> Interval {
            Interval(min(lower, other.lower), max(upper, other.upper))
        }
    }

    public let coneSurface: Surface3D
    public let torusSurface: Surface3D
    public let branchIndex: Int
    public let branchCount: Int
    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double
    public let apexReduction: ApexReduction?
    private let certificate: Certificate

    package func chargeStructuralComparisonWork<A: ExactScalarAdmission & ~Copyable>(
        using execution: inout A
    ) throws {
        try certificate.chargeStructuralComparisonWork(using: &execution)
    }

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int = 24,
        maximumCellCount: Int = 65_536,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(coneSurface: coneSurface, torusSurface: torusSurface, branchIndex: branchIndex, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumCellCount: maximumCellCount, tolerance: tolerance, using: &execution)
    }

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int = 24,
        maximumCellCount: Int = 65_536,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        guard let certificate = try Self.makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        , using: &execution) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A general cone-torus curve cannot select a branch from an empty certified intersection."
            )
        }
        try self.init(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            branchIndex: branchIndex,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance,
            configuration: configuration,
            certificate: certificate
        , using: &execution)
    }

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        branchCount: Int,
        apexReduction: ApexReduction,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(coneSurface: coneSurface, torusSurface: torusSurface, branchIndex: branchIndex, branchCount: branchCount, apexReduction: apexReduction, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumCellCount: maximumCellCount, tolerance: tolerance, using: &execution)
    }

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        branchCount: Int,
        apexReduction: ApexReduction,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        self.coneSurface = coneSurface
        self.torusSurface = torusSurface
        self.branchIndex = branchIndex
        self.branchCount = branchCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        certificationTolerance = tolerance
        maximumResidualUpperBound = tolerance.distance
        self.apexReduction = apexReduction
        certificate = (try Certificate(
            branchCount: branchCount,
            processedCellCount: branchCount,
            differentialPartitions: [],
            traceParameters: [],
            slantsByBranch: []
        , using: &execution))
        try validate(tolerance: tolerance, using: &execution)
    }

    private init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance,
        configuration: Configuration,
        certificate: Certificate
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(coneSurface: coneSurface, torusSurface: torusSurface, branchIndex: branchIndex, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumCellCount: maximumCellCount, tolerance: tolerance, configuration: configuration, certificate: certificate, using: &execution)
    }

    private init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance,
        configuration: Configuration,
        certificate: Certificate
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        self.coneSurface = coneSurface
        self.torusSurface = torusSurface
        self.branchIndex = branchIndex
        branchCount = certificate.branchCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        certificationTolerance = tolerance
        maximumResidualUpperBound = try Self.residualUpperBound(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        apexReduction = nil
        self.certificate = certificate
        try validate(tolerance: tolerance, using: &execution)
    }

    static func certifiedCurves(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedGeneralConeTorusIntersectionCurve] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifiedCurves(coneSurface: coneSurface, torusSurface: torusSurface, options: options, tolerance: tolerance, using: &execution)
    }

    static func certifiedCurves(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [CertifiedGeneralConeTorusIntersectionCurve] {
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        let maximumSubdivisionDepth = min(
            options.maximumSubdivisionDepth + 12,
            24
        )
        let maximumCellCount = min(
            max(options.maximumSeedCount * 64, 16_384),
            65_536
        )
        let configuration = try makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        guard let certificate = try makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        , using: &execution) else {
            return []
        }
        return try CertifiedAnalyticCurveEvaluation.map(try (0..<certificate.branchCount), using: &execution) {branchIndex, execution in
            try CertifiedGeneralConeTorusIntersectionCurve(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                branchIndex: branchIndex,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                tolerance: tolerance,
                configuration: configuration,
                certificate: certificate
            , using: &execution)
        }
    }

    struct CertificationIdentity: Hashable, Sendable {
        private struct ConeKey: Hashable, Sendable {
            let apex: Point3D
            let axis: Vector3D
            let halfAngle: Double
        }

        private struct TorusKey: Hashable, Sendable {
            let center: Point3D
            let axis: Vector3D
            let majorRadius: Double
            let minorRadius: Double
        }

        private struct ApexReductionKey: Hashable, Sendable {
            let componentKind: ApexReduction.ComponentKind
            let lowerAngle: Double
            let upperAngle: Double
            let certificationTolerance: ModelingTolerance
            let maximumResidualUpperBound: Double
        }

        private let cone: ConeKey
        private let torus: TorusKey
        private let branchIndex: Int
        private let branchCount: Int
        private let maximumSubdivisionDepth: Int
        private let maximumCellCount: Int
        private let certificationTolerance: ModelingTolerance
        private let maximumResidualUpperBound: Double
        private let apexReduction: ApexReductionKey?
        init?(curve: CertifiedGeneralConeTorusIntersectionCurve) {
            guard case let .cone(cone) = CanonicalAnalyticSurface(
                curve.coneSurface
            ),
                  case let .torus(torus) = CanonicalAnalyticSurface(
                      curve.torusSurface
                  ) else {
                return nil
            }
            self.cone = ConeKey(
                apex: cone.apex,
                axis: cone.axis,
                halfAngle: cone.halfAngle
            )
            self.torus = TorusKey(
                center: torus.center,
                axis: torus.axis,
                majorRadius: torus.majorRadius,
                minorRadius: torus.minorRadius
            )
            branchIndex = curve.branchIndex
            branchCount = curve.branchCount
            maximumSubdivisionDepth = curve.maximumSubdivisionDepth
            maximumCellCount = curve.maximumCellCount
            certificationTolerance = curve.certificationTolerance
            maximumResidualUpperBound = curve.maximumResidualUpperBound
            apexReduction = curve.apexReduction.map {
                ApexReductionKey(
                    componentKind: $0.componentKind,
                    lowerAngle: $0.lowerAngle,
                    upperAngle: $0.upperAngle,
                    certificationTolerance: $0.certificationTolerance,
                    maximumResidualUpperBound: $0.maximumResidualUpperBound
                )
            }
        }
    }

    private struct ValidationCacheKey: Hashable, Sendable {
        let curve: CertificationIdentity
        let tolerance: ModelingTolerance

        init?(
            curve: CertifiedGeneralConeTorusIntersectionCurve,
            tolerance: ModelingTolerance
        ) {
            guard let identity = CertificationIdentity(curve: curve) else {
                return nil
            }
            self.curve = identity
            self.tolerance = tolerance
        }
    }

    var certificationIdentity: CertificationIdentity? {
        CertificationIdentity(curve: self)
    }

    // Consumers query differential bounds per subdivision window, and each
    // query revalidates the same immutable curve with certified root
    // isolation; successful validations are memoized per process.
    private enum ValidationCache {
        static let storage = Mutex<Set<ValidationCacheKey>>([])
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let key = ValidationCacheKey(curve: self, tolerance: tolerance)
        if let key,
           ValidationCache.storage.withLock({ $0.contains(key) }) {
            return
        }
        try validateUncached(tolerance: tolerance, using: &execution)
        guard let key else { return }
        try execution.retainStorage(count: 1, stride: MemoryLayout<ValidationCacheKey>.stride)
        ValidationCache.storage.withLock { cache in
            if cache.count >= 256 {
                cache.removeAll(keepingCapacity: true)
            }
            cache.insert(key)
        }
    }



    private func validateUncached(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general cone-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        if let apexReduction {
            try (try Self.validate(
                apexReduction: apexReduction,
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                tolerance: tolerance
            , using: &execution))
        } else {
            _ = try Self.makeConfiguration(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                tolerance: tolerance
            , using: &execution)
        }
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 24,
              maximumCellCount > 0,
              maximumCellCount <= 65_536,
              branchCount > 0,
              branchIndex >= 0,
              branchIndex < branchCount,
              certificate.branchCount == branchCount,
              certificate.processedCellCount > 0,
              certificate.processedCellCount <= maximumCellCount,
              maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound > 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A general cone-torus branch has an invalid stored completeness certificate."
            )
        }
        if apexReduction == nil {
            guard certificate.traceParameters.count >= 2,
                  certificate.slantsByBranch.count == branchCount,
                  certificate.slantsByBranch.allSatisfy({
                      $0.count == certificate.traceParameters.count
                          && $0.allSatisfy({ $0.isFinite })
                  }),
                  certificate.traceParameters.first == 0.0,
                  certificate.traceParameters.last == 2.0 * Double.pi,
                  zip(
                      certificate.traceParameters,
                      certificate.traceParameters.dropFirst()
                  ).allSatisfy({ $0 < $1 }),
                  certificate.differentialPartitions.isEmpty == false,
                  certificate.differentialPartitions.allSatisfy({
                      $0.lowerNormalizedAngle.isFinite
                          && $0.upperNormalizedAngle.isFinite
                          && $0.lowerNormalizedAngle >= 0.0
                          && $0.upperNormalizedAngle <= 1.0
                          && $0.lowerNormalizedAngle
                              <= $0.upperNormalizedAngle
                          && $0.lowerSlant.isFinite
                          && $0.upperSlant.isFinite
                          && $0.lowerSlant <= $0.upperSlant
                          && $0.slantFirstDerivativeMagnitudeUpperBound.isFinite
                          && $0.slantFirstDerivativeMagnitudeUpperBound > 0.0
                          && $0.slantSecondDerivativeMagnitudeUpperBound.isFinite
                          && $0.slantSecondDerivativeMagnitudeUpperBound > 0.0
                          && $0.slantThirdDerivativeMagnitudeUpperBound.isFinite
                          && $0.slantThirdDerivativeMagnitudeUpperBound > 0.0
                          && $0.firstDerivativeMagnitudeUpperBound.isFinite
                          && $0.secondDerivativeMagnitudeUpperBound.isFinite
                          && $0.firstDerivativeMagnitudeUpperBound > 0.0
                          && $0.secondDerivativeMagnitudeUpperBound > 0.0
                  }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A regular cone-torus branch has invalid stored spatial differential bounds."
                )
            }
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution).position
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        let geometry = try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            includingThirdDerivative: false,
            tolerance: tolerance
        , using: &execution)
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative,
            secondDerivative: geometry.secondDerivative
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        return try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            includingThirdDerivative: true,
            tolerance: tolerance
        , using: &execution).thirdDerivative
    }



    private func derivativesThroughThirdOrder(
        atNormalizedFraction fraction: Double,
        includingThirdDerivative: Bool,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ThirdOrderDifferentialGeometry {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        if let apexReduction {
            guard includingThirdDerivative else {
                let geometry = try apexReduction.differential(
                    atNormalizedFraction: min(max(fraction, 0.0), 1.0),
                    tolerance: tolerance
                , using: &execution)
                return ThirdOrderDifferentialGeometry(
                    position: geometry.position,
                    firstDerivative: geometry.firstDerivative,
                    secondDerivative: geometry.secondDerivative,
                    thirdDerivative: .zero
                )
            }
            let geometry = try (try apexReduction.derivativesThroughThirdOrder(
                atNormalizedFraction: min(max(fraction, 0.0), 1.0),
                tolerance: tolerance
            , using: &execution))
            return ThirdOrderDifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                thirdDerivative: geometry.thirdDerivative
            )
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let angle = clamped == 1.0 ? 0.0 : 2.0 * Double.pi * clamped
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let referenceSlant = (try certificate.referenceSlant(
            branchIndex: branchIndex,
            at: angle
        , using: &execution))
        let slant = try Self.refinedRoot(
            angle: angle,
            initialSlant: referenceSlant,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard abs(slant) > tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: abs(slant),
                tolerance: tolerance,
                message: "A certified cone-torus branch reaches the cone apex."
            )
        }
        let direction = configuration.cone.direction(at: angle)
        let directionFirst = configuration.cone.directionFirstDerivative(at: angle)
        let directionSecond = configuration.cone.directionSecondDerivative(at: angle)
        let position = configuration.cone.apex + direction * slant
        let angleTangent = directionFirst * slant
        let angleSecond = directionSecond * slant
        let offset = position - configuration.torus.center
        let gradient = try Self.torusGradient(
            offset: offset,
            torus: configuration.torus
        , using: &execution)
        let slantDenominator = gradient.dot(direction)
        let derivativeThreshold = try Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard slantDenominator.isFinite,
              abs(slantDenominator) > derivativeThreshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(slantDenominator),
                tolerance: tolerance,
                message: "A certified cone-torus branch reached a generator-tangent root."
            )
        }
        let angleImplicit = gradient.dot(angleTangent)
        let slantAngleDerivative = -angleImplicit / slantDenominator
        let angleAngleImplicit = try Self.torusHessianBilinear(
            offset: offset,
            first: angleTangent,
            second: angleTangent,
            torus: configuration.torus
        , using: &execution) + gradient.dot(angleSecond)
        let angleSlantImplicit = try Self.torusHessianBilinear(
            offset: offset,
            first: angleTangent,
            second: direction,
            torus: configuration.torus
        , using: &execution) + gradient.dot(directionFirst)
        let slantSlantImplicit = try Self.torusHessianBilinear(
            offset: offset,
            first: direction,
            second: direction,
            torus: configuration.torus
        , using: &execution)
        let slantAngleSecondDerivative = -(
            angleAngleImplicit
                + 2.0 * angleSlantImplicit * slantAngleDerivative
                + slantSlantImplicit
                    * slantAngleDerivative * slantAngleDerivative
        ) / slantDenominator
        let angularScale = 2.0 * Double.pi
        let firstDerivative = (
            angleTangent + direction * slantAngleDerivative
        ) * angularScale
        let secondDerivative = (
            angleSecond
                + directionFirst * (2.0 * slantAngleDerivative)
                + direction * slantAngleSecondDerivative
        ) * (angularScale * angularScale)
        let thirdDerivative: Vector3D
        if includingThirdDerivative {
            let directionThird = configuration.cone
                .directionThirdDerivative(at: angle)
            let firstByAngle = angleTangent
                + direction * slantAngleDerivative
            let secondByAngle = angleSecond
                + directionFirst * (2.0 * slantAngleDerivative)
                + direction * slantAngleSecondDerivative
            let knownThirdByAngle = directionThird * slant
                + directionSecond * (3.0 * slantAngleDerivative)
                + directionFirst * (3.0 * slantAngleSecondDerivative)
            let implicitThird = try Self.torusThirdDerivativeTrilinear(
                offset: offset,
                first: firstByAngle,
                second: firstByAngle,
                third: firstByAngle
            , using: &execution)
            let thirdRightHandSide = implicitThird
                + 3.0 * (try Self.torusHessianBilinear(
                    offset: offset,
                    first: firstByAngle,
                    second: secondByAngle,
                    torus: configuration.torus
                , using: &execution))
                + gradient.dot(knownThirdByAngle)
            let slantAngleThirdDerivative = -thirdRightHandSide
                / slantDenominator
            thirdDerivative = (
                knownThirdByAngle
                    + direction * slantAngleThirdDerivative
            ) * (angularScale * angularScale * angularScale)
        } else {
            thirdDerivative = .zero
        }
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cone-torus component has a singular differential."
            )
        }
        let coneOffset = position - configuration.cone.apex
        let coneAxialDistance = coneOffset.dot(configuration.cone.axis)
        let coneRadial = coneOffset
            - configuration.cone.axis * coneAxialDistance
        let coneResidual = abs(
            coneRadial.length * cos(configuration.cone.halfAngle)
                - abs(coneAxialDistance)
                    * sin(configuration.cone.halfAngle)
        )
        let torusAxialDistance = offset.dot(configuration.torus.axis)
        let torusRadial = offset
            - configuration.torus.axis * torusAxialDistance
        let torusResidual = abs(
            hypot(
                torusRadial.length - configuration.torus.majorRadius,
                torusAxialDistance
            ) - configuration.torus.minorRadius
        )
        let residual = max(coneResidual, torusResidual)
        guard residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified cone-torus root exceeded its geometric residual bound."
            )
        }
        guard thirdDerivative.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A certified cone-torus third differential exceeded finite arithmetic."
            )
        }
        return ThirdOrderDifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            thirdDerivative: thirdDerivative
        )
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        guard surface == coneSurface || surface == torusSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general cone-torus pcurve was requested on an unrelated surface."
            )
        }
        if let apexReduction {
            return try apexReduction.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }

    public func boundingBox(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        if let apexReduction {
            return try apexReduction.boundingBox(
                tolerance: tolerance
            , using: &execution)
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let radius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.torus.center.x - radius,
                y: configuration.torus.center.y - radius,
                z: configuration.torus.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.torus.center.x + radius,
                y: configuration.torus.center.y + radius,
                z: configuration.torus.center.z + radius
            )
        )
    }

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        return try spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 1.0,
            tolerance: tolerance
        , using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        if let apexReduction {
            return try (try apexReduction.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            , using: &execution))
        }
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= 0.0,
              upperFraction <= 1.0,
              lowerFraction <= upperFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-torus spatial differential bounds require an ordered normalized interval."
            )
        }
        let index = certificate.differentialPartitionIndex
        guard let maximumSlantFirstDerivative = (try index
            .maximumSlantFirstDerivative(
                overlappingLower: lowerFraction,
                upper: upperFraction
            , using: &execution)) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-torus spatial differential certification has no slant derivative covering the requested interval."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let middleFraction = lowerFraction
            + (upperFraction - lowerFraction) * 0.5
        let middleAngle = middleFraction * 2.0 * Double.pi
        let middleRoot = try Self.certifiedRefinedRootInterval(
            angle: middleAngle,
            initialSlant: (try certificate.referenceSlant(
                branchIndex: branchIndex,
                at: middleAngle
            , using: &execution)),
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let halfWidth = max(
            middleFraction - lowerFraction,
            upperFraction - middleFraction
        )
        let variationRadius = (
            maximumSlantFirstDerivative * halfWidth
        ).nextUp
        guard variationRadius.isFinite,
              let bounds = (try index.bounds(
            overlappingLower: lowerFraction,
            upper: upperFraction,
            slantLower: (middleRoot.lower - variationRadius).nextDown,
            slantUpper: (middleRoot.upper + variationRadius).nextUp
        , using: &execution)) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-torus spatial differential certificate has no branch-local partition covering the requested interval."
            )
        }
        return bounds
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, branchPointAtMiddle: middlePoint, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let slantEnclosure = try branchSlantEnclosure(
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            branchPointAtMiddle: middlePoint,
            tolerance: tolerance
        , using: &execution)
        let index = certificate.differentialPartitionIndex
        guard let bounds = (try index.bounds(
            overlappingLower: lowerFraction,
            upper: upperFraction,
            slantLower: slantEnclosure.lower,
            slantUpper: slantEnclosure.upper
        , using: &execution)) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-torus spatial differential certificate has no partition covering the reconstructed branch point."
            )
        }
        return bounds
    }

    struct ParameterDifferentialMagnitudeBounds: Sendable {
        let uFirst: Double
        let uSecond: Double
        let uThird: Double
        let vFirst: Double
        let vSecond: Double
        let vThird: Double
    }

    func coneParameterDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        tolerance: ModelingTolerance
    ) throws -> ParameterDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try coneParameterDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, branchPointAtMiddle: middlePoint, tolerance: tolerance, using: &execution)
    }

    func coneParameterDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let slantEnclosure = try branchSlantEnclosure(
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            branchPointAtMiddle: middlePoint,
            tolerance: tolerance
        , using: &execution)
        guard let slant = try certificate.differentialPartitionIndex
            .slantDifferentialBounds(
                overlappingLower: lowerFraction,
                upper: upperFraction,
                slantLower: slantEnclosure.lower,
                slantUpper: slantEnclosure.upper
            , using: &execution) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-torus cone-parameter certification has no partition covering the reconstructed branch point."
            )
        }
        return ParameterDifferentialMagnitudeBounds(
            uFirst: (2.0 * Double.pi).nextUp,
            uSecond: 0.0,
            uThird: 0.0,
            vFirst: slant.first,
            vSecond: slant.second,
            vThird: slant.third ?? .infinity
        )
    }

    func torusParameterDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        uBounds: ScalarInterval,
        vBounds: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> ParameterDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try torusParameterDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, branchPointAtMiddle: middlePoint, uBounds: uBounds, vBounds: vBounds, tolerance: tolerance, using: &execution)
    }

    func torusParameterDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        uBounds: ScalarInterval,
        vBounds: ScalarInterval,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let slant = try branchSlantEnclosure(
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            branchPointAtMiddle: middlePoint,
            tolerance: tolerance
        , using: &execution)
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let period = 2.0 * Double.pi
        let partitions = try certificate.differentialPartitionIndex
            .overlappingPartitions(
                lower: lowerFraction,
                upper: upperFraction,
                slantLower: slant.lower,
                slantUpper: slant.upper
            , using: &execution)
        guard partitions.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-torus torus-parameter certification has no branch-local differential partition."
            )
        }
        var firstByAngle: [Interval]?
        var secondByAngle: [Interval]?
        var thirdByAngle: [Interval]?
        for partition in partitions {
            try execution.consumeWork(1)
            let clippedAngle = Interval(
                max(lowerFraction, partition.lowerNormalizedAngle) * period,
                min(upperFraction, partition.upperNormalizedAngle) * period
            )
            let clippedSlant = Interval(
                max(slant.lower, partition.lowerSlant),
                min(slant.upper, partition.upperSlant)
            )
            let implicit = try Self.implicitDifferentialIntervals(
                angle: clippedAngle,
                slant: clippedSlant,
                configuration: configuration
            , using: &execution)
            guard implicit.slantDerivative.containsZero == false,
                  let slantFirst = implicit.angleDerivative
                    .scaled(by: -1.0)
                    .divided(by: implicit.slantDerivative) else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A branch-local cone-torus certificate lost its non-tangent first derivative invariant."
                )
            }
            let slantSecondNumerator = implicit.angleAngleDerivative
                .adding(
                    implicit.angleSlantDerivative
                        .multiplied(by: slantFirst)
                        .scaled(by: 2.0)
                )
                .adding(
                    implicit.slantSlantDerivative
                        .multiplied(by: slantFirst)
                        .multiplied(by: slantFirst)
                )
            guard let slantSecond = slantSecondNumerator
                .scaled(by: -1.0)
                .divided(by: implicit.slantDerivative) else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A branch-local cone-torus certificate lost its non-tangent second derivative invariant."
                )
            }
            let localFirst = try CertifiedAnalyticCurveEvaluation.map(implicit.direction.indices, using: &execution) {index, execution in
                implicit.directionFirst[index]
                    .multiplied(by: clippedSlant)
                    .adding(
                        implicit.direction[index].multiplied(by: slantFirst)
                    )
            }
            let localSecond = try CertifiedAnalyticCurveEvaluation.map(implicit.direction.indices, using: &execution) {index, execution in
                implicit.directionSecond[index]
                    .multiplied(by: clippedSlant)
                    .adding(
                        implicit.directionFirst[index]
                            .multiplied(by: slantFirst)
                            .scaled(by: 2.0)
                    )
                    .adding(
                        implicit.direction[index].multiplied(by: slantSecond)
                    )
            }
            let knownThird = try CertifiedAnalyticCurveEvaluation.map(implicit.direction.indices, using: &execution) {index, execution in
                implicit.directionFirst[index]
                    .scaled(by: -1.0)
                    .multiplied(by: clippedSlant)
                    .adding(
                        implicit.directionSecond[index]
                            .multiplied(by: slantFirst)
                            .scaled(by: 3.0)
                    )
                    .adding(
                        implicit.directionFirst[index]
                            .multiplied(by: slantSecond)
                            .scaled(by: 3.0)
                    )
            }
            let thirdRightHandSide = try Self
                .torusThirdDerivativeTrilinearInterval(
                    offset: implicit.offset,
                    first: localFirst,
                    second: localFirst,
                    third: localFirst
                , using: &execution)
                .adding(
                    try Self.torusHessianBilinearInterval(
                        offset: implicit.offset,
                        q: implicit.q,
                        first: localFirst,
                        second: localSecond,
                        torus: configuration.torus
                    , using: &execution).scaled(by: 3.0)
                )
                .adding(try Self.dotInterval(implicit.gradient, knownThird, using: &execution))
            guard let slantThird = thirdRightHandSide
                .scaled(by: -1.0)
                .divided(by: implicit.slantDerivative) else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A branch-local cone-torus certificate lost its non-tangent third derivative invariant."
                )
            }
            let localThird = try CertifiedAnalyticCurveEvaluation.map(implicit.direction.indices, using: &execution) {index, execution in
                knownThird[index].adding(
                    implicit.direction[index].multiplied(by: slantThird)
                )
            }
            if let existingFirst = firstByAngle,
               let existingSecond = secondByAngle,
               let existingThird = thirdByAngle {
                firstByAngle = try CertifiedAnalyticCurveEvaluation.map(existingFirst.indices, using: &execution) {element, execution in
                    existingFirst[element].hull(localFirst[element])
                }
                secondByAngle = try CertifiedAnalyticCurveEvaluation.map(existingSecond.indices, using: &execution) {element, execution in
                    existingSecond[element].hull(localSecond[element])
                }
                thirdByAngle = try CertifiedAnalyticCurveEvaluation.map(existingThird.indices, using: &execution) {element, execution in
                    existingThird[element].hull(localThird[element])
                }
            } else {
                firstByAngle = localFirst
                secondByAngle = localSecond
                thirdByAngle = localThird
            }
        }
        guard let firstByAngle,
              let secondByAngle,
              let thirdByAngle else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Cone-torus torus-parameter certification failed to compose its branch-local differential intervals."
            )
        }
        let firstScale = period.nextUp
        let secondScale = (firstScale * firstScale).nextUp
        let thirdScale = (secondScale * firstScale).nextUp
        let spatialFirst = try CertifiedAnalyticCurveEvaluation.map(firstByAngle, using: &execution) {element, execution in element.scaled(by: firstScale) }
        let spatialSecond = try CertifiedAnalyticCurveEvaluation.map(secondByAngle, using: &execution) {element, execution in element.scaled(by: secondScale) }
        let spatialThird = try CertifiedAnalyticCurveEvaluation.map(thirdByAngle, using: &execution) {element, execution in element.scaled(by: thirdScale) }

        let torusBasis = try analyticOrthonormalBasis(
            configuration.torus.axis,
            tolerance: tolerance
        )
        let u = Interval(uBounds.lower, uBounds.upper)
        let v = Interval(vBounds.lower, vBounds.upper)
        let cosineU = try Self.cosineInterval(u, using: &execution)
        let sineU = try Self.sineInterval(u, using: &execution)
        let cosineV = try Self.cosineInterval(v, using: &execution)
        let sineV = try Self.sineInterval(v, using: &execution)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        let torusAxis = [
            configuration.torus.axis.x,
            configuration.torus.axis.y,
            configuration.torus.axis.z,
        ]
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let radial = [
            cosineU.scaled(by: torusBasis.u.x)
                .adding(sineU.scaled(by: torusBasis.v.x)),
            cosineU.scaled(by: torusBasis.u.y)
                .adding(sineU.scaled(by: torusBasis.v.y)),
            cosineU.scaled(by: torusBasis.u.z)
                .adding(sineU.scaled(by: torusBasis.v.z)),
        ]
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let azimuth = [
            sineU.scaled(by: -torusBasis.u.x)
                .adding(cosineU.scaled(by: torusBasis.v.x)),
            sineU.scaled(by: -torusBasis.u.y)
                .adding(cosineU.scaled(by: torusBasis.v.y)),
            sineU.scaled(by: -torusBasis.u.z)
                .adding(cosineU.scaled(by: torusBasis.v.z)),
        ]
        let meridian = try CertifiedAnalyticCurveEvaluation.map(radial.indices, using: &execution) {index, execution in
            radial[index].multiplied(by: sineV).scaled(by: -1.0)
                .adding(
                    cosineV.scaled(by: torusAxis[index])
                )
        }
        let azimuthScale = Interval.constant(configuration.torus.majorRadius)
            .adding(cosineV.scaled(by: configuration.torus.minorRadius))
        guard let uFirst = try Self.dotInterval(azimuth, spatialFirst, using: &execution)
            .divided(by: azimuthScale) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Cone-torus torus azimuth scale became singular."
            )
        }
        let vFirst = try Self.dotInterval(meridian, spatialFirst, using: &execution)
            .scaled(by: 1.0 / configuration.torus.minorRadius)
        let uSecondNumerator = try Self.dotInterval(azimuth, spatialSecond, using: &execution)
            .adding(
                sineV.multiplied(by: uFirst).multiplied(by: vFirst)
                    .scaled(by: 2.0 * configuration.torus.minorRadius)
            )
        guard let uSecond = uSecondNumerator.divided(by: azimuthScale) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Cone-torus torus azimuth second differentiation became singular."
            )
        }
        let vSecond = try Self.dotInterval(meridian, spatialSecond, using: &execution)
            .subtracting(
                azimuthScale.multiplied(by: sineV)
                    .multiplied(by: uFirst).multiplied(by: uFirst)
            )
            .scaled(by: 1.0 / configuration.torus.minorRadius)
        let uThirdNumerator = try Self.dotInterval(azimuth, spatialThird, using: &execution)
            .adding(
                sineV.multiplied(by:
                    uSecond.multiplied(by: vFirst)
                        .adding(uFirst.multiplied(by: vSecond))
                ).scaled(by: 3.0 * configuration.torus.minorRadius)
            )
            .adding(
                azimuthScale.multiplied(by: uFirst)
                    .multiplied(by: uFirst).multiplied(by: uFirst)
            )
            .adding(
                cosineV.multiplied(by: uFirst)
                    .multiplied(by: vFirst).multiplied(by: vFirst)
                    .scaled(by: 3.0 * configuration.torus.minorRadius)
            )
        guard let uThird = uThirdNumerator.divided(by: azimuthScale) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Cone-torus torus azimuth third differentiation became singular."
            )
        }
        let vThird = try Self.dotInterval(meridian, spatialThird, using: &execution)
            .subtracting(
                azimuthScale.multiplied(by: sineV)
                    .multiplied(by: uFirst).multiplied(by: uSecond)
                    .scaled(by: 3.0)
            )
            .adding(
                sineV.multiplied(by: sineV)
                    .multiplied(by: uFirst).multiplied(by: uFirst)
                    .multiplied(by: vFirst)
                    .scaled(by: 3.0 * configuration.torus.minorRadius)
            )
            .adding(
                vFirst.multiplied(by: vFirst).multiplied(by: vFirst)
                    .scaled(by: configuration.torus.minorRadius)
            )
            .scaled(by: 1.0 / configuration.torus.minorRadius)
        return ParameterDifferentialMagnitudeBounds(
            uFirst: uFirst.maximumAbsoluteValue,
            uSecond: uSecond.maximumAbsoluteValue,
            uThird: uThird.maximumAbsoluteValue,
            vFirst: vFirst.maximumAbsoluteValue,
            vSecond: vSecond.maximumAbsoluteValue,
            vThird: vThird.maximumAbsoluteValue
        )
    }



    private func branchSlantEnclosure(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        branchPointAtMiddle middlePoint: Point3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard apexReduction == nil,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= 0.0,
              upperFraction <= 1.0,
              lowerFraction <= upperFraction,
              middlePoint.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-torus branch-point differential bounds require a regular branch, an ordered interval, and a finite middle point."
            )
        }
        let index = certificate.differentialPartitionIndex
        guard let maximumSlantFirstDerivative = (try index
            .maximumSlantFirstDerivative(
                overlappingLower: lowerFraction,
                upper: upperFraction
            , using: &execution)) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-torus branch-point differential certification has no slant derivative covering the requested interval."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let middleFraction = lowerFraction
            + (upperFraction - lowerFraction) * 0.5
        let middleAngle = middleFraction * 2.0 * Double.pi
        let direction = configuration.cone.direction(at: middleAngle)
        let middleSlant = (middlePoint - configuration.cone.apex).dot(direction)
        let reconstructionUncertainty = (
            try Self.rootTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) * 16.0
                + Double.ulpOfOne * max(abs(middleSlant), 1.0) * 4_096.0
        ).nextUp
        let halfWidth = max(
            middleFraction - lowerFraction,
            upperFraction - middleFraction
        )
        let variationRadius = (
            maximumSlantFirstDerivative * halfWidth
        ).nextUp
        guard variationRadius.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: variationRadius,
                tolerance: tolerance,
                message: "Cone-torus branch slant enclosure exceeded finite arithmetic."
            )
        }
        return Interval(
            middleSlant - reconstructionUncertainty - variationRadius,
            middleSlant + reconstructionUncertainty + variationRadius
        )
    }

    /// Returns the source-parameter boundaries where the stored differential
    /// certificate changes. Consumers that integrate the curve should seed
    /// their adaptive work at these boundaries so a narrow near-tangent
    /// partition does not smear its derivative maximum across adjacent cells.
    func differentialPartitionBreakpoints(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double
    ) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialPartitionBreakpoints(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, using: &execution)
    }

    func differentialPartitionBreakpoints(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let lower = min(lowerFraction, upperFraction)
        let upper = max(lowerFraction, upperFraction)
        guard apexReduction == nil, upper > lower else {
            return try CertifiedAnalyticCurveEvaluation.values(lower, upper, using: &execution)
        }
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var values = [lower, upper]
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(certificate.differentialPartitions.count * 2 + 2, in: &values, using: &execution)
        for partition in certificate.differentialPartitions {
            try execution.consumeWork(1)
            if partition.lowerNormalizedAngle > lower,
               partition.lowerNormalizedAngle < upper {
                values.append(partition.lowerNormalizedAngle)
            }
            if partition.upperNormalizedAngle > lower,
               partition.upperNormalizedAngle < upper {
                values.append(partition.upperNormalizedAngle)
            }
        }
        try values.sort { first, second in
            try execution.consumeWork(1)
            return first < second
        }
        var result: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(values.count, in: &result, using: &execution)
        for value in values {
            try execution.consumeWork(1)
            guard result.last != value else { continue }
            result.append(value)
        }
        return result
    }



    private static func makeConfiguration(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.consumeWork(1)
        try coneSurface.validate(tolerance: tolerance, using: &execution)
        try torusSurface.validate(tolerance: tolerance, using: &execution)
        guard case let .cone(sourceCone) = CanonicalAnalyticSurface(coneSurface),
              case let .torus(sourceTorus) = CanonicalAnalyticSurface(
                torusSurface
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified general cone-torus curve requires one exact cone and one exact torus."
            )
        }
        var coneAxis = try sourceCone.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(coneAxis) { coneAxis = -coneAxis }
        var torusAxis = try sourceTorus.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(torusAxis) { torusAxis = -torusAxis }
        let axesAreParallel = AnalyticAxisRelation.areParallel(
            coneAxis,
            torusAxis,
            tolerance: tolerance
        )
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: sourceTorus.center,
            axis: torusAxis,
            to: sourceCone.apex
        )
        guard axesAreParallel == false || radialOffset.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general cone-torus curve requires non-coaxial source surfaces."
            )
        }
        let basis = try analyticOrthonormalBasis(coneAxis, tolerance: tolerance)
        let sine = sin(sourceCone.halfAngle)
        let cone = Cone(
            apex: sourceCone.apex,
            axis: coneAxis,
            halfAngle: sourceCone.halfAngle,
            centerDirection: coneAxis * cos(sourceCone.halfAngle),
            radialU: basis.u * sine,
            radialV: basis.v * sine
        )
        let torus = Torus(
            center: sourceTorus.center,
            axis: torusAxis,
            majorRadius: sourceTorus.majorRadius,
            minorRadius: sourceTorus.minorRadius
        )
        try rejectApexContact(cone: cone, torus: torus, tolerance: tolerance, using: &execution)
        let outerRadius = sourceTorus.majorRadius + sourceTorus.minorRadius
        let slantBound = (sourceTorus.center - sourceCone.apex).length
            + outerRadius
            + tolerance.distance * 16.0
        return Configuration(
            cone: cone,
            torus: torus,
            lowerSlant: -slantBound,
            upperSlant: slantBound,
            characteristicLength: max(
                outerRadius,
                (sourceTorus.center - sourceCone.apex).length,
                1.0
            )
        )
    }



    private static func validate(
        apexReduction: ApexReduction,
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try (try apexReduction.validate(tolerance: tolerance, using: &execution))
        guard apexReduction.coneSurface == coneSurface,
              apexReduction.torusSurface == torusSurface,
              case let .cone(cone) = CanonicalAnalyticSurface(coneSurface),
              case .torus = CanonicalAnalyticSurface(torusSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus rational reduction changed its analytic source surfaces."
            )
        }
        let apexProjection = try torusSurface.parameterProjection(
            of: cone.apex,
            tolerance: tolerance
        , using: &execution)
        guard apexProjection.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: apexProjection.residual,
                tolerance: tolerance,
                message: "A cone-torus apex reduction requires the cone apex on the torus."
            )
        }
    }



    private static func makeCertificate(
        configuration: Configuration,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Certificate? {
        try execution.consumeWork(1)
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 24,
              maximumCellCount > 0,
              maximumCellCount <= 65_536 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "General cone-torus certification limits are outside the supported resource envelope."
            )
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
        var cells = [Cell(
            angle: Interval(0.0, 2.0 * Double.pi),
            slant: Interval(configuration.lowerSlant, configuration.upperSlant),
            depth: 0
        )]
        var cellsCapacity = cells.count
        var processedCellCount = 0
        var differentialPartitions: [DifferentialPartition] = []
        var differentialPartitionsCapacity = differentialPartitions.count
        let generatorAngularMagnitude = sin(
            configuration.cone.halfAngle
        ).nextUp
        let angularScale = (2.0 * Double.pi).nextUp
        while let cell = cells.popLast() {
            try execution.admitGeometricDepth(cell.depth)
            try execution.consumeCells()
            try execution.consumeWork(1)
            processedCellCount += 1
            guard processedCellCount <= maximumCellCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCellCount),
                    tolerance: tolerance,
                    message: "Cone-torus generator tangency certification exceeded its cell limit."
                )
            }
            let values = try implicitDifferentialIntervals(
                angle: cell.angle,
                slant: cell.slant,
                configuration: configuration
            , using: &execution)
            if values.implicit.containsZero == false {
                continue
            }
            let normalizedAngleWidth = cell.angle.width / (2.0 * Double.pi)
            let normalizedSlantWidth = cell.slant.width
                / (configuration.upperSlant - configuration.lowerSlant)
            let maximumNormalizedAngleWidth = 1.0 / 128.0
            let maximumNormalizedSlantWidth = 1.0 / 64.0
            if values.slantDerivative.containsZero == false,
               normalizedAngleWidth <= maximumNormalizedAngleWidth,
               normalizedSlantWidth <= maximumNormalizedSlantWidth {
                guard let slantFirstInterval = values.angleDerivative
                    .scaled(by: -1.0)
                    .divided(by: values.slantDerivative) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A non-tangent cone-torus certificate lost its first implicit derivative denominator."
                    )
                }
                let slantSecondNumerator = values.angleAngleDerivative
                    .adding(
                        values.angleSlantDerivative
                            .multiplied(by: slantFirstInterval)
                            .scaled(by: 2.0)
                    )
                    .adding(
                        values.slantSlantDerivative
                            .multiplied(by: slantFirstInterval)
                            .multiplied(by: slantFirstInterval)
                    )
                guard let slantSecondInterval = slantSecondNumerator
                    .scaled(by: -1.0)
                    .divided(by: values.slantDerivative) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A non-tangent cone-torus certificate lost its second implicit derivative denominator."
                    )
                }
                let slantFirstDerivative = slantFirstInterval
                    .maximumAbsoluteValue
                let slantSecondDerivative = slantSecondInterval
                    .maximumAbsoluteValue
                let firstByAngle = try CertifiedAnalyticCurveEvaluation.map(values.direction.indices, using: &execution) {index, execution in
                    values.directionFirst[index]
                        .multiplied(by: cell.slant)
                        .adding(
                            values.direction[index].multiplied(
                                by: slantFirstInterval
                            )
                        )
                }
                let secondByAngle = try CertifiedAnalyticCurveEvaluation.map(values.direction.indices, using: &execution) {index, execution in
                    values.directionSecond[index]
                        .multiplied(by: cell.slant)
                        .adding(
                            values.directionFirst[index]
                                .multiplied(by: slantFirstInterval)
                                .scaled(by: 2.0)
                        )
                        .adding(
                            values.direction[index].multiplied(
                                by: slantSecondInterval
                            )
                        )
                }
                let knownThirdByAngle = try CertifiedAnalyticCurveEvaluation.map(values.direction.indices, using: &execution) {index, execution in
                    values.directionFirst[index]
                        .scaled(by: -1.0)
                        .multiplied(by: cell.slant)
                        .adding(
                            values.directionSecond[index]
                                .multiplied(by: slantFirstInterval)
                                .scaled(by: 3.0)
                        )
                        .adding(
                            values.directionFirst[index]
                                .multiplied(by: slantSecondInterval)
                                .scaled(by: 3.0)
                        )
                }
                let thirdRightHandSide = try torusThirdDerivativeTrilinearInterval(
                    offset: values.offset,
                    first: firstByAngle,
                    second: firstByAngle,
                    third: firstByAngle
                , using: &execution).adding(
                    try torusHessianBilinearInterval(
                        offset: values.offset,
                        q: values.q,
                        first: firstByAngle,
                        second: secondByAngle,
                        torus: configuration.torus
                    , using: &execution).scaled(by: 3.0)
                ).adding(try dotInterval(values.gradient, knownThirdByAngle, using: &execution))
                guard let slantThirdInterval = thirdRightHandSide
                    .scaled(by: -1.0)
                    .divided(by: values.slantDerivative) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A non-tangent cone-torus certificate lost its third implicit derivative denominator."
                    )
                }
                let slantThirdDerivative = slantThirdInterval
                    .maximumAbsoluteValue
                let maximumAbsoluteSlant = max(
                    abs(cell.slant.lower),
                    abs(cell.slant.upper)
                ).nextUp
                let firstDerivativeMagnitudeUpperBound = ((
                    generatorAngularMagnitude * maximumAbsoluteSlant
                        + slantFirstDerivative
                ).nextUp * angularScale).nextUp
                let secondDerivativeMagnitudeUpperBound = ((
                    generatorAngularMagnitude * maximumAbsoluteSlant
                        + 2.0 * generatorAngularMagnitude
                            * slantFirstDerivative
                        + slantSecondDerivative
                ).nextUp * angularScale * angularScale).nextUp
                let thirdDerivativeMagnitudeUpperBound = ((
                    generatorAngularMagnitude * maximumAbsoluteSlant
                        + 3.0 * generatorAngularMagnitude
                            * slantFirstDerivative
                        + 3.0 * generatorAngularMagnitude
                            * slantSecondDerivative
                        + slantThirdDerivative
                ).nextUp * angularScale * angularScale * angularScale).nextUp
                // Near a generator tangency the interval denominator smears
                // an enormous derivative bound across the whole partition;
                // refining until the bound is usable (or the width floors)
                // confines the smear geometrically, so consumers subdivide
                // a narrow sliver instead of the full partition.
                let boundQualityLimit = 1.0e6
                let minimumNormalizedRefinementWidth = 1.0e-6
                let canRefine = cell.depth < maximumSubdivisionDepth
                    && (normalizedAngleWidth > minimumNormalizedRefinementWidth
                        || normalizedSlantWidth > minimumNormalizedRefinementWidth)
                if firstDerivativeMagnitudeUpperBound.isFinite,
                   secondDerivativeMagnitudeUpperBound.isFinite,
                   thirdDerivativeMagnitudeUpperBound.isFinite,
                   secondDerivativeMagnitudeUpperBound <= boundQualityLimit
                    || canRefine == false {
                    try CertifiedAnalyticCurveEvaluation.append(DifferentialPartition(
                        lowerNormalizedAngle: max(
                            0.0,
                            cell.angle.lower / (2.0 * Double.pi)
                        ),
                        upperNormalizedAngle: min(
                            1.0,
                            cell.angle.upper / (2.0 * Double.pi)
                        ),
                        lowerSlant: cell.slant.lower,
                        upperSlant: cell.slant.upper,
                        slantFirstDerivativeMagnitudeUpperBound: (
                            slantFirstDerivative * angularScale
                        ).nextUp,
                        slantSecondDerivativeMagnitudeUpperBound: (
                            slantSecondDerivative
                                * angularScale * angularScale
                        ).nextUp,
                        slantThirdDerivativeMagnitudeUpperBound: (
                            slantThirdDerivative
                                * angularScale * angularScale * angularScale
                        ).nextUp,
                        firstDerivativeMagnitudeUpperBound:
                            firstDerivativeMagnitudeUpperBound,
                        secondDerivativeMagnitudeUpperBound:
                            secondDerivativeMagnitudeUpperBound,
                        thirdDerivativeMagnitudeUpperBound:
                            thirdDerivativeMagnitudeUpperBound
                    ), to: &differentialPartitions, using: &execution, capacity: &differentialPartitionsCapacity)
                    continue
                }
            }
            guard cell.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(cell.angle.width, cell.slant.width),
                    tolerance: tolerance,
                    message: "General cone-torus subdivision exhausted its budget before certifying root simplicity."
                )
            }
            if normalizedAngleWidth >= normalizedSlantWidth {
                let middle = cell.angle.midpoint
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    angle: Interval(middle, cell.angle.upper),
                    slant: cell.slant,
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    angle: Interval(cell.angle.lower, middle),
                    slant: cell.slant,
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
            } else {
                let middle = cell.slant.midpoint
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    angle: cell.angle,
                    slant: Interval(middle, cell.slant.upper),
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    angle: cell.angle,
                    slant: Interval(cell.slant.lower, middle),
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
            }
        }
        let initialRoots = try certifiedRoots(
            angle: 0.0,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        if differentialPartitions.isEmpty, initialRoots.isEmpty {
            return nil
        }
        guard differentialPartitions.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "General cone-torus certification produced no differential partitions."
            )
        }
        guard initialRoots.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "General cone-torus certification found root-containing cells without a complete periodic branch."
            )
        }
        let trace = try makeRootTrace(
            initialSlants: CertifiedAnalyticCurveEvaluation.map(initialRoots, using: &execution) { root, _ in root.value },
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        return (try Certificate(
            branchCount: initialRoots.count,
            processedCellCount: processedCellCount,
            differentialPartitions: differentialPartitions,
            traceParameters: trace.parameters,
            slantsByBranch: trace.slantsByBranch
        , using: &execution))
    }



    private static func makeRootTrace(
        initialSlants: [Double],
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> (
        parameters: [Double],
        slantsByBranch: [[Double]]
    ) {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let initialSegmentCount = 32
        let maximumDepth = 16
        let maximumSegmentCount = 4_096
        try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
        var parameters = [0.0]
        var parametersCapacity = parameters.count
        var slantsByBranch = try CertifiedAnalyticCurveEvaluation.map(initialSlants, using: &execution) { element, execution in
            try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
            return [element]
        }
        var slantCapacities = try CertifiedAnalyticCurveEvaluation.map(initialSlants, using: &execution) { _, execution in 1 }
        var acceptedSegmentCount = 0

        func appendInterval(
            lowerAngle: Double,
            lowerSlants: [Double],
            upperAngle: Double,
            depth: Int
        , using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.admitGeometricDepth(depth)
            try execution.consumeCells()
            let refined = try CertifiedAnalyticCurveEvaluation.map(lowerSlants, using: &execution) {element, execution in
                try refinedRoot(
                    angle: upperAngle,
                    initialSlant: element,
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
            }
            let sorted = try CertifiedAnalyticCurveEvaluation.sorted(refined, using: &execution)
            var minimumSeparation = Double.infinity
            for index in sorted.indices.dropFirst() {
                try execution.consumeWork(1)
                minimumSeparation = min(minimumSeparation, sorted[index] - sorted[index - 1])
            }
            var maximumMovement = 0.0
            for (lower, upper) in zip(lowerSlants, refined) {
                try execution.consumeWork(1)
                maximumMovement = max(maximumMovement, abs(upper - lower))
            }
            let movementLimit = min(
                configuration.characteristicLength * 0.125,
                minimumSeparation * 0.25
            )
            let preservesOrder = try zip(refined, sorted).allSatisfy {
                abs($0 - $1) <= (try rootTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)) * 8.0
            }
            if preservesOrder,
               minimumSeparation > (try rootTolerance(
                   configuration: configuration,
                   tolerance: tolerance
               , using: &execution)) * 16.0,
               maximumMovement < movementLimit {
                acceptedSegmentCount += 1
                guard acceptedSegmentCount <= maximumSegmentCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        residual: Double(acceptedSegmentCount),
                        tolerance: tolerance,
                        message: "General cone-torus root continuation exceeded its segment budget."
                    )
                }
                try CertifiedAnalyticCurveEvaluation.append(upperAngle, to: &parameters, using: &execution, capacity: &parametersCapacity)
                for branchIndex in slantsByBranch.indices {
                    try execution.consumeWork(1)
                    try CertifiedAnalyticCurveEvaluation.append(
                        refined[branchIndex]
                    , to: &slantsByBranch[branchIndex], using: &execution, capacity: &slantCapacities[branchIndex])
                }
                return refined
            }
            guard depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: maximumMovement,
                    tolerance: tolerance,
                    message: "General cone-torus root continuation remained ambiguous after adaptive subdivision."
                )
            }
            let middle = lowerAngle
                + (upperAngle - lowerAngle) * 0.5
            let middleSlants = try appendInterval(
                lowerAngle: lowerAngle,
                lowerSlants: lowerSlants,
                upperAngle: middle,
                depth: depth + 1
            , using: &execution)
            return try appendInterval(
                lowerAngle: middle,
                lowerSlants: middleSlants,
                upperAngle: upperAngle,
                depth: depth + 1
            , using: &execution)
        }

        var lowerAngle = 0.0
        var lowerSlants = initialSlants
        for index in 1...initialSegmentCount {
            try execution.consumeWork(1)
            let upperAngle = period * Double(index)
                / Double(initialSegmentCount)
            lowerSlants = try appendInterval(
                lowerAngle: lowerAngle,
                lowerSlants: lowerSlants,
                upperAngle: upperAngle,
                depth: 0
            , using: &execution)
            lowerAngle = upperAngle
        }
        let closureTolerance = try rootTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution) * 16.0
        guard zip(lowerSlants, initialSlants).allSatisfy({
            abs($0 - $1) <= closureTolerance
        }) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: try zip(lowerSlants, initialSlants).reduce(0.0) { result, pair in
                    try execution.consumeWork(1)
                    return max(result, abs(pair.0 - pair.1))
                },
                tolerance: tolerance,
                message: "General cone-torus root continuation did not close over one angular period."
            )
        }
        return (parameters, slantsByBranch)
    }



    private static func implicitDifferentialIntervals(
        angle: Interval,
        slant: Interval,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> (
        implicit: Interval,
        angleDerivative: Interval,
        slantDerivative: Interval,
        angleAngleDerivative: Interval,
        angleSlantDerivative: Interval,
        slantSlantDerivative: Interval,
        offset: [Interval],
        q: Interval,
        gradient: [Interval],
        direction: [Interval],
        directionFirst: [Interval],
        directionSecond: [Interval]
    ) {
        try execution.consumeWork(1)
        let cosine = try cosineInterval(angle, using: &execution)
        let sine = try sineInterval(angle, using: &execution)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let direction = [
            try directionInterval(
                center: configuration.cone.centerDirection.x,
                radialU: configuration.cone.radialU.x,
                radialV: configuration.cone.radialV.x,
                cosine: cosine,
                sine: sine
            , using: &execution),
            try directionInterval(
                center: configuration.cone.centerDirection.y,
                radialU: configuration.cone.radialU.y,
                radialV: configuration.cone.radialV.y,
                cosine: cosine,
                sine: sine
            , using: &execution),
            try directionInterval(
                center: configuration.cone.centerDirection.z,
                radialU: configuration.cone.radialU.z,
                radialV: configuration.cone.radialV.z,
                cosine: cosine,
                sine: sine
            , using: &execution),
        ]
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let directionFirst = [
            sine.scaled(by: -configuration.cone.radialU.x)
                .adding(cosine.scaled(by: configuration.cone.radialV.x)),
            sine.scaled(by: -configuration.cone.radialU.y)
                .adding(cosine.scaled(by: configuration.cone.radialV.y)),
            sine.scaled(by: -configuration.cone.radialU.z)
                .adding(cosine.scaled(by: configuration.cone.radialV.z)),
        ]
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let directionSecond = [
            cosine.scaled(by: -configuration.cone.radialU.x)
                .adding(sine.scaled(by: -configuration.cone.radialV.x)),
            cosine.scaled(by: -configuration.cone.radialU.y)
                .adding(sine.scaled(by: -configuration.cone.radialV.y)),
            cosine.scaled(by: -configuration.cone.radialU.z)
                .adding(sine.scaled(by: -configuration.cone.radialV.z)),
        ]
        let centerOffset = configuration.cone.apex - configuration.torus.center
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        let base = [centerOffset.x, centerOffset.y, centerOffset.z]
        let coordinates = try CertifiedAnalyticCurveEvaluation.map(direction.indices, using: &execution) {index, execution in
            Interval.constant(base[index]).adding(
                direction[index].multiplied(by: slant)
            )
        }
        let angleTangent = try CertifiedAnalyticCurveEvaluation.map(directionFirst, using: &execution) {element, execution in
            element.multiplied(by: slant)
        }
        let angleSecond = try CertifiedAnalyticCurveEvaluation.map(directionSecond, using: &execution) {element, execution in
            element.multiplied(by: slant)
        }
        let squaredLength = coordinates.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = try dotInterval(coordinates, configuration.torus.axis, using: &execution)
        let radiusDifference = configuration.torus.majorRadius
            * configuration.torus.majorRadius
            - configuration.torus.minorRadius
                * configuration.torus.minorRadius
        let q = squaredLength.adding(.constant(radiusDifference))
        let radialSquared = squaredLength.subtracting(axialDistance.squared())
        let majorFactor = 4.0 * configuration.torus.majorRadius
            * configuration.torus.majorRadius
        let implicit = q.squared().subtracting(
            radialSquared.scaled(by: majorFactor)
        )
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let radial = [
            coordinates[0].subtracting(
                axialDistance.scaled(by: configuration.torus.axis.x)
            ),
            coordinates[1].subtracting(
                axialDistance.scaled(by: configuration.torus.axis.y)
            ),
            coordinates[2].subtracting(
                axialDistance.scaled(by: configuration.torus.axis.z)
            ),
        ]
        try execution.retainStorage(count: 3, stride: MemoryLayout<Interval>.stride)
        let gradient = [
            q.multiplied(by: coordinates[0]).scaled(by: 4.0).subtracting(
                radial[0].scaled(by: 2.0 * majorFactor)
            ),
            q.multiplied(by: coordinates[1]).scaled(by: 4.0).subtracting(
                radial[1].scaled(by: 2.0 * majorFactor)
            ),
            q.multiplied(by: coordinates[2]).scaled(by: 4.0).subtracting(
                radial[2].scaled(by: 2.0 * majorFactor)
            ),
        ]
        let angleDerivative = try dotInterval(gradient, angleTangent, using: &execution)
        let slantDerivative = try dotInterval(gradient, direction, using: &execution)
        let angleAngleDerivative = try torusHessianBilinearInterval(
            offset: coordinates,
            q: q,
            first: angleTangent,
            second: angleTangent,
            torus: configuration.torus
        , using: &execution).adding(try dotInterval(gradient, angleSecond, using: &execution))
        let angleSlantDerivative = try torusHessianBilinearInterval(
            offset: coordinates,
            q: q,
            first: angleTangent,
            second: direction,
            torus: configuration.torus
        , using: &execution).adding(try dotInterval(gradient, directionFirst, using: &execution))
        let slantSlantDerivative = try torusHessianBilinearInterval(
            offset: coordinates,
            q: q,
            first: direction,
            second: direction,
            torus: configuration.torus
        , using: &execution)
        return (
            implicit,
            angleDerivative,
            slantDerivative,
            angleAngleDerivative,
            angleSlantDerivative,
            slantSlantDerivative,
            coordinates,
            q,
            gradient,
            direction,
            directionFirst,
            directionSecond
        )
    }



    private static func directionInterval(
        center: Double,
        radialU: Double,
        radialV: Double,
        cosine: Interval,
        sine: Interval
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        return Interval.constant(center)
            .adding(cosine.scaled(by: radialU))
            .adding(sine.scaled(by: radialV))
    }



    private static func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        return values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
    }



    private static func dotInterval(
        _ first: [Interval],
        _ second: [Interval]
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        return first.indices.reduce(Interval.constant(0.0)) { result, index in
            result.adding(first[index].multiplied(by: second[index]))
        }
    }



    private static func torusHessianBilinearInterval(
        offset: [Interval],
        q: Interval,
        first: [Interval],
        second: [Interval],
        torus: Torus
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        let firstSecond = try dotInterval(first, second, using: &execution)
        let firstAxis = try dotInterval(first, torus.axis, using: &execution)
        let secondAxis = try dotInterval(second, torus.axis, using: &execution)
        return try dotInterval(offset, first, using: &execution)
            .multiplied(by: try dotInterval(offset, second, using: &execution))
            .scaled(by: 8.0)
            .adding(
                q.multiplied(by: firstSecond).scaled(by: 4.0)
            )
            .subtracting(
                firstSecond.subtracting(
                    firstAxis.multiplied(by: secondAxis)
                ).scaled(by: 8.0 * torus.majorRadius * torus.majorRadius)
            )
    }



    private static func torusThirdDerivativeTrilinearInterval(
        offset: [Interval],
        first: [Interval],
        second: [Interval],
        third: [Interval]
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        return try dotInterval(offset, first, using: &execution)
            .multiplied(by: try dotInterval(second, third, using: &execution))
            .adding(
                try dotInterval(offset, second, using: &execution)
                    .multiplied(by: try dotInterval(first, third, using: &execution))
            )
            .adding(
                try dotInterval(offset, third, using: &execution)
                    .multiplied(by: try dotInterval(first, second, using: &execution))
            )
            .scaled(by: 8.0)
    }



    private static func certifiedRoots(
        angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [CertifiedSimplePolynomialRootSolver.Root] {
        try execution.consumeWork(1)
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: try rootTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution),
            coefficientTolerance: Double.ulpOfOne * 128.0,
            maximumRefinementIterations: 256,
            tolerance: tolerance
        )
        let coefficients = (try configuration.coefficients(at: angle, using: &execution))
        let roots = try CertifiedAnalyticCurveEvaluation.filter(solver.roots(coefficients: coefficients, using: &execution), using: &execution) {root, execution in
            root.upper >= configuration.lowerSlant
                && root.lower <= configuration.upperSlant
        }
        for root in roots {
            try execution.consumeWork(1)
            let derivative = try polynomialDerivative(coefficients, at: root.value, using: &execution)
            guard abs(derivative) > (try derivativeThreshold(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "Certified cone-torus root isolation encountered a generator-tangent root."
                )
            }
            guard abs(root.value) > tolerance.distance * 8.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: abs(root.value),
                    tolerance: tolerance,
                    message: "Certified cone-torus root isolation reached the cone apex."
                )
            }
        }
        return roots
    }



    private static func refinedRoot(
        angle: Double,
        initialSlant: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let coefficients = (try configuration.coefficients(at: angle, using: &execution))
        let derivativeLowerBound = try derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let stepTolerance = try rootTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        var slant = initialSlant
        var converged = false
        for _ in 0..<24 {
            try execution.consumeWork(1)
            let value = try polynomialValue(coefficients, at: slant, using: &execution)
            let derivative = try polynomialDerivative(
                coefficients,
                at: slant
            , using: &execution)
            guard value.isFinite,
                  derivative.isFinite,
                  abs(derivative) > derivativeLowerBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "General cone-torus branch refinement reached a generator-tangent root."
                )
            }
            let step = value / derivative
            slant -= step
            if abs(step) <= stepTolerance {
                converged = true
                break
            }
        }
        guard converged,
              slant >= configuration.lowerSlant,
              slant <= configuration.upperSlant,
              abs(slant) > tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: abs(
                    try polynomialValue(coefficients, at: slant, using: &execution)
                ),
                tolerance: tolerance,
                message: "General cone-torus branch refinement left its certified simple-root domain."
            )
        }
        return slant
    }

    /// Certifies the already selected branch locally. Global polynomial root
    /// isolation belongs to curve construction; repeating it for every
    /// downstream integration cell would discard both the branch identity and
    /// the continuation trace stored in the certificate.


    private static func certifiedRefinedRootInterval(
        angle: Double,
        initialSlant: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        let approximation = try refinedRoot(
            angle: angle,
            initialSlant: initialSlant,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        var radius = max(
            try rootTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) * 16.0,
            Double.ulpOfOne * max(abs(approximation), 1.0) * 4_096.0
        ).nextUp
        let angleInterval = Interval.constant(angle)
        let pointValue = try implicitDifferentialIntervals(
            angle: angleInterval,
            slant: .constant(approximation),
            configuration: configuration
        , using: &execution).implicit
        for _ in 0..<24 {
            try execution.consumeWork(1)
            let candidate = Interval(
                approximation - radius,
                approximation + radius
            )
            let derivative = try implicitDifferentialIntervals(
                angle: angleInterval,
                slant: candidate,
                configuration: configuration
            , using: &execution).slantDerivative
            if let correction = pointValue.divided(by: derivative) {
                let newton = Interval.constant(approximation)
                    .subtracting(correction)
                if newton.lower > candidate.lower,
                   newton.upper < candidate.upper,
                   let certified = candidate.intersection(with: newton) {
                    return certified
                }
            }
            radius = (radius * 4.0).nextUp
            guard radius.isFinite,
                  radius <= configuration.upperSlant
                    - configuration.lowerSlant else {
                break
            }
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: radius,
            tolerance: tolerance,
            message: "General cone-torus branch refinement could not certify its local root interval."
        )
    }



    private static func torusGradient(
        offset: Vector3D,
        torus: Torus
    ,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        let q = offset.dot(offset)
            + torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        let radial = offset - torus.axis * offset.dot(torus.axis)
        return offset * (4.0 * q)
            - radial * (8.0 * torus.majorRadius * torus.majorRadius)
    }



    private static func torusHessianBilinear(
        offset: Vector3D,
        first: Vector3D,
        second: Vector3D,
        torus: Torus
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let q = offset.dot(offset)
            + torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        return 8.0 * offset.dot(first) * offset.dot(second)
            + 4.0 * q * first.dot(second)
            - 8.0 * torus.majorRadius * torus.majorRadius * (
                first.dot(second)
                    - first.dot(torus.axis) * second.dot(torus.axis)
            )
    }



    private static func torusThirdDerivativeTrilinear(
        offset: Vector3D,
        first: Vector3D,
        second: Vector3D,
        third: Vector3D
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return 8.0 * (
            offset.dot(first) * second.dot(third)
                + offset.dot(second) * first.dot(third)
                + offset.dot(third) * first.dot(second)
        )
    }



    private static func polynomialDerivative(
        _ coefficients: [Double],
        at value: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard coefficients.count > 1 else { return 0.0 }
        var result = 0.0
        for index in (1..<coefficients.count).reversed() {
            try execution.consumeWork(1)
            result = result * value + coefficients[index] * Double(index)
        }
        return result
    }



    private static func polynomialValue(
        _ coefficients: [Double],
        at value: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var result = 0.0
        for coefficient in coefficients.reversed() {
            try execution.consumeWork(1)
            result = result * value + coefficient
        }
        return result
    }



    private static func derivativeThreshold(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
            tolerance.angle * pow(configuration.characteristicLength, 3.0),
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 3.0) * 256.0
        )
    }



    private static func rootTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
            tolerance.distance * 1.0e-6,
            Double.ulpOfOne * configuration.characteristicLength * 256.0
        )
    }



    private static func residualUpperBound(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let result = try rootTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution) + Double.ulpOfOne * configuration.characteristicLength * 1_048_576.0
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "General cone-torus root isolation cannot satisfy the requested geometric tolerance."
            )
        }
        return result
    }



    private static func rejectApexContact(
        cone: Cone,
        torus: Torus,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let offset = cone.apex - torus.center
        let axial = offset.dot(torus.axis)
        let radialSquared = max(0.0, offset.dot(offset) - axial * axial)
        let meridianDistance = hypot(
            sqrt(radialSquared) - torus.majorRadius,
            axial
        )
        let residual = abs(meridianDistance - torus.minorRadius)
        guard residual > tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: residual,
                tolerance: tolerance,
                message: "General cone-torus intersection reaches the cone apex."
            )
        }
    }



    private static func cosineInterval(_ angle: Interval,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        return try trigonometricInterval(angle, phase: 0.0, using: &execution)
    }



    private static func sineInterval(_ angle: Interval,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        return try trigonometricInterval(angle, phase: Double.pi * 0.5, using: &execution)
    }



    private static func trigonometricInterval(
        _ angle: Interval,
        phase: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        guard angle.width < 2.0 * Double.pi else {
            return Interval(-1.0, 1.0)
        }
        let first = cos(angle.lower - phase)
        let second = cos(angle.upper - phase)
        var lower = min(first, second)
        var upper = max(first, second)
        if try containsPeriodicValue(
            angle,
            value: phase,
            period: 2.0 * Double.pi
        , using: &execution) {
            upper = 1.0
        }
        if try containsPeriodicValue(
            angle,
            value: phase + Double.pi,
            period: 2.0 * Double.pi
        , using: &execution) {
            lower = -1.0
        }
        return Interval(lower, upper)
    }



    private static func containsPeriodicValue(
        _ interval: Interval,
        value: Double,
        period: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        let firstIndex = ceil((interval.lower - value) / period)
        return value + firstIndex * period <= interval.upper
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case coneSurface
        case torusSurface
        case branchIndex
        case branchCount
        case maximumSubdivisionDepth
        case maximumCellCount
        case certificationTolerance
        case maximumResidualUpperBound
        case apexReduction
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .coneSurface,
                .torusSurface,
                .branchIndex,
                .branchCount,
                .maximumSubdivisionDepth,
                .maximumCellCount,
                .certificationTolerance,
                .maximumResidualUpperBound,
                .apexReduction,
            ],
            in: decoder
        )
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        let coneSurface = try container.decode(
            Surface3D.self,
            forKey: .coneSurface
        )
        let torusSurface = try container.decode(
            Surface3D.self,
            forKey: .torusSurface
        )
        let branchIndex = try container.decode(Int.self, forKey: .branchIndex)
        let maximumSubdivisionDepth = try container.decode(
            Int.self,
            forKey: .maximumSubdivisionDepth
        )
        let maximumCellCount = try container.decode(
            Int.self,
            forKey: .maximumCellCount
        )
        let storedBranchCount = try container.decode(
            Int.self,
            forKey: .branchCount
        )
        if let reduction = try container.decodeIfPresent(
            ApexReduction.self,
            forKey: .apexReduction
        ) {
            try self.init(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                branchIndex: branchIndex,
                branchCount: storedBranchCount,
                apexReduction: reduction,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                tolerance: tolerance
            , using: &execution)
        } else {
            try self.init(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                branchIndex: branchIndex,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                tolerance: tolerance
            , using: &execution)
        }
        guard storedBranchCount == branchCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .branchCount,
                in: container,
                debugDescription: "The general cone-torus branch count does not match its regenerated completeness certificate."
            )
        }
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        guard storedBound == maximumResidualUpperBound else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumResidualUpperBound,
                in: container,
                debugDescription: "The general cone-torus residual certificate does not match the reconstructed source surfaces."
            )
        }
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(branchIndex, forKey: .branchIndex)
        try container.encode(branchCount, forKey: .branchCount)
        try container.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try container.encode(maximumCellCount, forKey: .maximumCellCount)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
        try container.encodeIfPresent(apexReduction, forKey: .apexReduction)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedGeneralConeTorusIntersectionCurve: Codable {}
#endif
