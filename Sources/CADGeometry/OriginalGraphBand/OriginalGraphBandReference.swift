import CADCore

/// A reference law with original endpoint ownership, separate from all retained source tails.
enum OriginalGraphBandReference: Sendable {
    case original(OriginalGraphBandRationalPiece)
    case connector(u: ScalarInterval, entryV: OutwardScalarInterval,
                   exitV: OutwardScalarInterval, originalV: OutwardScalarInterval)

    var uncertaintyVUpperBound: Double {
        switch self {
        case .original: return 0
        case let .connector(_, _, _, originalV): return originalV.width
        }
    }

    func graphJet(over u: ScalarInterval, tolerance: ModelingTolerance,
                  proofUsage: inout OriginalTessellationProofUsage)
      throws -> OriginalGraphBandRationalPiece.GraphJet {
        switch self {
        case let .original(piece):
            return try piece.graphJet(over: u, tolerance: tolerance, proofUsage: &proofUsage)
        case let .connector(domain, entryV, exitV, originalV):
            try proofUsage.consume(depth: 0, tolerance: tolerance)
            guard u.lower >= domain.lower, u.upper <= domain.upper, domain.upper > domain.lower else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "An affine reference connector requires its retained exact entry and exit stations.")
            }
            let width = OutwardScalarInterval.exact(domain.upper) - .exact(domain.lower)
            guard let fraction = (OutwardScalarInterval(lower: u.lower, upper: u.upper)
                - .exact(domain.lower)).divided(by: width),
                  let first = (exitV - entryV).divided(by: width), first.isFinite else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Original connector ownership exceeded finite affine arithmetic.")
            }
            let value = (.exact(1) - fraction) * entryV + fraction * exitV
            guard let boundedValue = value.intersection(with: originalV) else {
                throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                                  message: "Original connector endpoint and convex-box enclosures are inconsistent.")
            }
            return OriginalGraphBandRationalPiece.GraphJet(
                v: boundedValue, first: first, second: .exact(0),
                normalizedParameters: try ScalarInterval(lower: max(0, fraction.lower),
                                                         upper: min(1, fraction.upper)))
        }
    }

    func originalValueCover(reference: OutwardScalarInterval) -> OutwardScalarInterval {
        switch self {
        case .original: return reference
        case let .connector(_, _, _, originalV): return reference.union(originalV)
        }
    }
}
