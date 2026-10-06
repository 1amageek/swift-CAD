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
import CADCore

extension Curve3D {
    /// Returns the original third parameter derivative through the common native source dispatcher.
    public func thirdParameterDerivative(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Vector3D {
        try parameterDerivativesThroughThirdOrder(at: parameter,
            tolerance: tolerance).thirdDerivative
    }

}
