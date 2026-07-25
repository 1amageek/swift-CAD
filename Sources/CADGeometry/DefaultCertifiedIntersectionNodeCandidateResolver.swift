import CADCore

struct DefaultCertifiedIntersectionNodeCandidateResolver:
    CertifiedIntersectionNodeCandidateResolving
{
    func candidates(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate] {
        var candidates: [CertifiedIntersectionCandidate] = []
        // Certified cross-component graph nodes are encoded at normalized
        // component endpoints. The final verifier owns range and residual checks.
        for fraction in [0.0, 1.0] {
            let point = try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            guard candidates.allSatisfy({
                ($0.point - point).length > tolerance.distance
            }), let residual = try targetResidual(
                at: point,
                targetSurface: targetSurface,
                tolerance: tolerance
            ) else {
                continue
            }
            candidates.append(CertifiedIntersectionCandidate(
                point: point,
                residual: residual,
                iterations: 0
            ))
        }
        return candidates
    }

    private func targetResidual(
        at point: Point3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        do {
            let projection = try targetSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return projection.residual <= tolerance.distance
                ? projection.residual
                : nil
        } catch let error as KernelError
            where error.code == .intersectionFailure
                && (error.residual ?? 0.0) > tolerance.distance {
            return nil
        }
    }
}
