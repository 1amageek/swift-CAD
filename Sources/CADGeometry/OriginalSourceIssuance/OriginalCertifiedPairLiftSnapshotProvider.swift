import CADCore

/// Reuses the exact original pair; the selected role is never inferred from XYZ.
public struct OriginalCertifiedPairLiftSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalPhysicalAngleScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalPhysicalAngleScalarDomain, tolerance: ModelingTolerance) {
        self.field = field; self.tolerance = tolerance
    }
    public static func supports(_ input: Curve3D) -> Bool {
        guard case .surfaceLift(let lift) = input,
            case .certifiedAnalyticPair(let pcurve) = lift.parameterCurve,
            case .coneCylinder(let curve) = pcurve.intersection.definition else { return false }
        return OriginalCertifiedCoaxialConeCylinderSnapshotProvider.supports(.certifiedIntersection(.coneCylinder(curve)))
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCertifiedPairLiftSnapshot> {
        let input = copy input
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard Self.supports(input), case .surfaceLift(let lift) = input,
                    case .certifiedAnalyticPair(let pcurve) = lift.parameterCurve,
                    case .coneCylinder(let curve) = pcurve.intersection.definition else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                guard limits.remainingSourceDepth >= 3 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard lift.surface == pcurve.intersection.surface(for: pcurve.role),
                    (pcurve.intersection.firstSurface == curve.coneSurface && pcurve.intersection.secondSurface == curve.cylinderSurface)
                    || (pcurve.intersection.secondSurface == curve.coneSurface && pcurve.intersection.firstSurface == curve.cylinderSurface) else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                try lift.validate(tolerance: tolerance)
                // FIXME(INCOMPLETE_IMPLEMENTATION): This public source capability
                // owns closed fraction windows within the original child support.
                // General wrapped windows need complete cycle/preimage receipts.
                guard pcurve.startFraction >= 0, pcurve.startFraction <= 1,
                    pcurve.endFraction >= 0, pcurve.endFraction <= 1 else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                let child = try DefaultOriginalSourceBindingIssuer(provider:
                    OriginalCertifiedCoaxialConeCylinderSnapshotProvider(field: field, tolerance: tolerance))
                    .bind(.certifiedIntersection(.coneCylinder(curve)), limits: .init(remainingSourceDepth: 1), using: &a)
                let start = try field.binary64(exactly: pcurve.startFraction, using: &a)
                let end = try field.binary64(exactly: pcurve.endFraction, using: &a)
                let extent = try field.subtracting(end, start, using: &a)
                guard try field.sign(of: extent, using: &a) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
                let depth = try a.depth
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCertifiedPairLiftSnapshot.self))
                let snapshot = OriginalCertifiedPairLiftSnapshot(original: lift, parameterCurve: pcurve,
                    child: child, start: start, end: end, extent: extent,
                    isConeRole: lift.surface == curve.coneSurface, proofDepth: depth)
                try a.checkpoint(); return .init(original: snapshot, sourceDepth: 3)
            }
        } catch { throw .init(preserving: error) }
    }
}
