import Foundation
import CADCore

extension Curve3D {
    /// Returns the original third parameter derivative through the common native source dispatcher.
    public func thirdParameterDerivative(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Vector3D {
        try parameterDerivativesThroughThirdOrder(at: parameter,
            tolerance: tolerance).thirdDerivative
    }

}
