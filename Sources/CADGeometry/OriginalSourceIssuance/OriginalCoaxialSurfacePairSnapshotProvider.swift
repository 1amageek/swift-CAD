import CADCore

/// Issues exact common radial origins with separate source/axial roles.
public struct OriginalCoaxialSurfacePairSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalPhysicalAngleScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalPhysicalAngleScalarDomain, tolerance: ModelingTolerance) { self.field = field; self.tolerance = tolerance }
    public static func coneAndCylinder(_ input: OriginalCoaxialSurfacePairInput) -> (cone: Surface3D, cylinder: Surface3D, coneFirst: Bool)? {
        if case .analytic(.cone(_, let axis, _)) = input.first,
            case .analytic(.cylinder(_, let secondAxis, _)) = input.second, axis == .unitZ, secondAxis == .unitZ {
            return (input.first, input.second, true)
        }
        if case .analytic(.cone(_, let axis, _)) = input.second,
            case .analytic(.cylinder(_, let secondAxis, _)) = input.first, axis == .unitZ, secondAxis == .unitZ {
            return (input.second, input.first, false)
        }
        return nil
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalCoaxialSurfacePairInput,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCoaxialSurfacePairSnapshot> {
        let input = copy input
        do {
            return try a.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let pair = Self.coneAndCylinder(input), case .analytic(.cone(let apex, _, let angle)) = pair.cone,
                    case .analytic(.cylinder(let origin, _, let radius)) = pair.cylinder else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                guard apex.x == origin.x, apex.y == origin.y else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                guard angle == field.originalRadians else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let primitive = DefaultOriginalSourceBindingIssuer(provider: OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance: tolerance))
                let first = try primitive.bind(input.first, limits: .init(remainingSourceDepth: 0), using: &a)
                let second = try primitive.bind(input.second, limits: .init(remainingSourceDepth: 0), using: &a)
                let issuer = DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot, OriginalPhysicalAngleScalarDomain>()
                let firstLaw = try issuer.issue(source: first, field: field, limits: limits, using: &a)
                let secondLaw = try issuer.issue(source: second, field: field, limits: limits, using: &a)
                let coefficients = try OriginalCoaxialConeCylinderCoefficients.prepare(radius: radius, field: field, using: &a)
                let x = try field.binary64(exactly: apex.x, using: &a), y = try field.binary64(exactly: apex.y, using: &a)
                let cz = try field.binary64(exactly: apex.z, using: &a), dz = try field.binary64(exactly: origin.z, using: &a)
                let depth = try a.depth
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCoaxialSurfacePairSnapshot.self))
                let snapshot = OriginalCoaxialSurfacePairSnapshot(original: input, first: first, second: second,
                    firstLaw: firstLaw, secondLaw: secondLaw, coneIsFirst: pair.coneFirst, field: field, radius: coefficients.radius,
                    positiveSlant: coefficients.positiveSlant, positiveRelativeHeight: coefficients.positiveHeight,
                    labelPeriod: coefficients.labelPeriod, centerX: x, centerY: y, coneOriginZ: cz, cylinderOriginZ: dz, proofDepth: depth)
                try a.checkpoint(); return .init(original: snapshot, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
}
