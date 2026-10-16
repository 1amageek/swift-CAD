import CADCore
import CADGeometry

/// Separates established validation findings from unfinished proof/admission failures.
package enum OriginalTopologyValidationFinding {
    package static func classify(_ error: any Error, tolerance: ModelingTolerance) throws -> KernelError {
        if let failure = error as? KernelError {
            switch failure.code.category {
            case .invalidInput, .missingReference, .invalidTopology: return failure
            default: throw error
            }
        }
        if error is TopologyError || error is GeometryError {
            return KernelError.wrapping(error, phase: .topology, tolerance: tolerance)
        }
        if let failure = error as? GeometryConversionError, case .invalidInput = failure {
            return KernelError.wrapping(error, phase: .topology, tolerance: tolerance)
        }
        throw error
    }
}
