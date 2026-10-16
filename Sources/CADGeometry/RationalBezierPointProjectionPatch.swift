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

struct RationalBezierPointProjectionPatch: Sendable {
    private struct OutwardInterval: Sendable {
        let lower: Double
        let upper: Double

        init(_ value: Double) {
            lower = value.nextDown
            upper = value.nextUp
        }

        private init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func + (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func * (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            let first = lhs.lower * rhs.lower
            let second = lhs.lower * rhs.upper
            let third = lhs.upper * rhs.lower
            let fourth = lhs.upper * rhs.upper
            var lower = first, upper = first
            if second < lower { lower = second }; if upper < second { upper = second }
            if third < lower { lower = third }; if upper < third { upper = third }
            if fourth < lower { lower = fourth }; if upper < fourth { upper = fourth }
            return OutwardInterval(lower: lower.nextDown, upper: upper.nextUp)
        }

        static func / (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            guard rhs.lower > 0.0 else {
                return OutwardInterval(lower: -.infinity, upper: .infinity)
            }
            return lhs * OutwardInterval(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
        }
    }

    private struct HomogeneousPoint: Sendable {
        let x: OutwardInterval
        let y: OutwardInterval
        let z: OutwardInterval
        let weight: OutwardInterval

        init(point: Point3D, weight: Double) {
            let weightInterval = OutwardInterval(weight)
            x = OutwardInterval(point.x) * weightInterval
            y = OutwardInterval(point.y) * weightInterval
            z = OutwardInterval(point.z) * weightInterval
            self.weight = weightInterval
        }

        private init(
            x: OutwardInterval,
            y: OutwardInterval,
            z: OutwardInterval,
            weight: OutwardInterval
        ) {
            self.x = x
            self.y = y
            self.z = z
            self.weight = weight
        }

        func midpoint(with other: HomogeneousPoint) -> HomogeneousPoint {
            let half = OutwardInterval(0.5)
            return HomogeneousPoint(
                x: (x + other.x) * half,
                y: (y + other.y) * half,
                z: (z + other.z) * half,
                weight: (weight + other.weight) * half
            )
        }

        func cartesianBounds(tolerance: ModelingTolerance) throws -> (
            x: OutwardInterval,
            y: OutwardInterval,
            z: OutwardInterval
        ) {
            guard weight.lower.isFinite,
                  weight.upper.isFinite,
                  weight.lower > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: weight.lower,
                    tolerance: tolerance,
                    message: "Rational Bezier projection could not bound a positive homogeneous weight."
                )
            }
            return (x / weight, y / weight, z / weight)
        }
    }

    private let controlNet: [[HomogeneousPoint]]
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double

    init<A: ExactScalarAdmission & ~Copyable>(patch: RationalBezierSurfacePatch3D,
        using execution: inout A) throws {
        try execution.consumeWork(1)
        controlNet = try OriginalCoefficientAllocation.map(elements: patch.controlPoints.indices, using: &execution) { vIndex, execution in
            try OriginalCoefficientAllocation.map(elements: patch.controlPoints[vIndex].indices, using: &execution) { uIndex, _ in
                HomogeneousPoint(point: patch.controlPoints[vIndex][uIndex], weight: patch.weights[vIndex][uIndex])
            }
        }
        uLower = patch.uLower; uUpper = patch.uUpper
        vLower = patch.vLower; vUpper = patch.vUpper
    }

    private init(
        controlNet: [[HomogeneousPoint]],
        uLower: Double,
        uUpper: Double,
        vLower: Double,
        vUpper: Double
    ) {
        self.controlNet = controlNet
        self.uLower = uLower
        self.uUpper = uUpper
        self.vLower = vLower
        self.vUpper = vUpper
    }

    func boundingBox<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance,
        using execution: inout A) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        var minimumX = Double.infinity
        var minimumY = Double.infinity
        var minimumZ = Double.infinity
        var maximumX = -Double.infinity
        var maximumY = -Double.infinity
        var maximumZ = -Double.infinity
        for row in controlNet { for control in row {
            try execution.consumeWork(1)
            let bounds = try control.cartesianBounds(tolerance: tolerance)
            minimumX = min(minimumX, bounds.x.lower)
            minimumY = min(minimumY, bounds.y.lower)
            minimumZ = min(minimumZ, bounds.z.lower)
            maximumX = max(maximumX, bounds.x.upper)
            maximumY = max(maximumY, bounds.y.upper)
            maximumZ = max(maximumZ, bounds.z.upper)
        }
        }
        return try BoundingBox3D(
            minimum: Point3D(x: minimumX, y: minimumY, z: minimumZ),
            maximum: Point3D(x: maximumX, y: maximumY, z: maximumZ)
        )
    }

    func subdivided<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [RationalBezierPointProjectionPatch] {
        try execution.consumeWork(1)
        let quadrants = try subdivided(controlNet: controlNet, using: &execution)
        let uMiddle = uLower + (uUpper - uLower) * 0.5
        let vMiddle = vLower + (vUpper - vLower) * 0.5
        return try OriginalCoefficientAllocation.map(elements: 0..<4, using: &execution) { index, _ in
            RationalBezierPointProjectionPatch(controlNet: quadrants[index],
                uLower: index.isMultiple(of: 2) ? uLower : uMiddle,
                uUpper: index.isMultiple(of: 2) ? uMiddle : uUpper,
                vLower: index < 2 ? vLower : vMiddle,
                vUpper: index < 2 ? vMiddle : vUpper)
        }
    }

    private func subdivided<A: ExactScalarAdmission & ~Copyable>(controlNet: [[HomogeneousPoint]],
        using execution: inout A) throws -> [[[HomogeneousPoint]]] {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: controlNet.count, of: [HomogeneousPoint].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controlNet.count, of: [HomogeneousPoint].self, using: &execution)
        var uLowerRows: [[HomogeneousPoint]] = []; uLowerRows.reserveCapacity(controlNet.count)
        var uUpperRows: [[HomogeneousPoint]] = []; uUpperRows.reserveCapacity(controlNet.count)
        for row in controlNet {
            try execution.consumeWork(1)
            let halves = try split(row, using: &execution)
            uLowerRows.append(halves.lower); uUpperRows.append(halves.upper)
        }
        let lowerUHalves = try splitColumns(uLowerRows, using: &execution)
        let upperUHalves = try splitColumns(uUpperRows, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 4, of: [[HomogeneousPoint]].self, using: &execution)
        return [lowerUHalves.lower, upperUHalves.lower, lowerUHalves.upper, upperUHalves.upper]
    }

    private func splitColumns<A: ExactScalarAdmission & ~Copyable>(_ values: [[HomogeneousPoint]],
        using execution: inout A) throws -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
        try execution.consumeWork(1)
        guard let firstRow = values.first else { return ([], []) }
        try OriginalCoefficientAllocation.reserve(count: firstRow.count, of: [HomogeneousPoint].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: firstRow.count, of: [HomogeneousPoint].self, using: &execution)
        var lowerColumns: [[HomogeneousPoint]] = []; lowerColumns.reserveCapacity(firstRow.count)
        var upperColumns: [[HomogeneousPoint]] = []; upperColumns.reserveCapacity(firstRow.count)
        for columnIndex in firstRow.indices {
            try execution.consumeWork(1)
            let column = try OriginalCoefficientAllocation.map(elements: values, using: &execution) { row, _ in row[columnIndex] }
            let halves = try split(column, using: &execution)
            lowerColumns.append(halves.lower); upperColumns.append(halves.upper)
        }
        let lower = try OriginalCoefficientAllocation.map(elements: values.indices, using: &execution) { rowIndex, execution in
            try OriginalCoefficientAllocation.map(elements: lowerColumns, using: &execution) { column, _ in column[rowIndex] }
        }
        let upper = try OriginalCoefficientAllocation.map(elements: values.indices, using: &execution) { rowIndex, execution in
            try OriginalCoefficientAllocation.map(elements: upperColumns, using: &execution) { column, _ in column[rowIndex] }
        }
        return (lower, upper)
    }

    private func split<A: ExactScalarAdmission & ~Copyable>(_ values: [HomogeneousPoint],
        using execution: inout A) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        try execution.consumeWork(1)
        guard values.count > 1 else { return (values, values) }
        try OriginalCoefficientAllocation.reserve(count: values.count, of: [HomogeneousPoint].self, using: &execution)
        var levels: [[HomogeneousPoint]] = []; levels.reserveCapacity(values.count); levels.append(values)
        while let previous = levels.last, previous.count > 1 {
            try execution.consumeWork(1)
            levels.append(try OriginalCoefficientAllocation.map(elements: 0..<(previous.count - 1), using: &execution) { index, _ in
                previous[index].midpoint(with: previous[index + 1])
            })
        }
        let lower = try OriginalCoefficientAllocation.map(elements: levels, using: &execution) { level, _ in level[0] }
        let upper = try OriginalCoefficientAllocation.map(elements: levels.reversed(), using: &execution) { level, _ in level[level.count - 1] }
        return (lower, upper)
    }
}
