import CADCore
import CADGeometry

/// Exact original pole algebra shares the tessellation invocation's admission.
struct TessellationExactProofAdmission: RationalAlgebraAdmitting {
    /// ExactNaturalMagnitude retains UInt32 limb words on every target.
    static let storageByteStride = MemoryLayout<UInt32>.stride
    let budget: TessellationProofBudget
    /// Intrinsic ordered-field/root depth, independent of mesh subdivision.
    static let maximumAlgebraicDepth = 32

    mutating func visitExactCell(depth: Int) throws {
        guard (0...Self.maximumAlgebraicDepth).contains(depth) else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original exact mesh algebra exceeded its intrinsic ordered-field depth ceiling.")
        }
        try budget.charge()
    }

    mutating func consumeExactWork(_ count: Int) throws { try budget.charge(count) }
    mutating func retainExactStorage(_ count: Int) throws { try budget.charge(count) }
}
