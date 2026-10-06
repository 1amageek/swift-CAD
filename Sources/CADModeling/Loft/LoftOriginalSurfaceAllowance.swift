import CADCore
import CADGeometry

/// Forwards every lower source operation to the body invocation's original allowance.
package struct LoftOriginalSurfaceAllowance: RationalAlgebraAdmitting {
    package let maximumDepth: Int
    package let maximumAlgebraicDepth: Int
    package let consume: (Int) throws -> Void
    package let retain: (Int) throws -> Void
    package let tolerance: ModelingTolerance

    package init(maximumDepth: Int, consume: @escaping (Int) throws -> Void,
        retain: @escaping (Int) throws -> Void, tolerance: ModelingTolerance,
        maximumAlgebraicDepth: Int = 32) throws {
        guard maximumDepth >= 0, (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Loft original proof requires independent legal subdivision and algebra depths.")
        }
        self.maximumDepth = maximumDepth; self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.consume = consume; self.retain = retain; self.tolerance = tolerance
    }

    package mutating func consumeExactWork(_ count: Int) throws {
        try Task.checkCancellation(); try consume(count)
    }
    package mutating func retainExactStorage(_ count: Int) throws {
        try Task.checkCancellation(); try retain(count)
    }
    package mutating func visitCoefficientCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumAlgebraicDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original Loft coefficient proof exceeds its intrinsic algebra depth.")
        }
        try Task.checkCancellation(); try consume(1)
    }

    package mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumAlgebraicDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original Loft exact algebra exceeds its intrinsic ordered-field depth allowance.")
        }
        try Task.checkCancellation(); try consume(1)
    }
}
