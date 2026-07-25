import CADCore
import Foundation

struct DefaultCertifiedReducedSectionComponentClassifier:
    CertifiedReducedSectionComponentClassifying
{
    private let parameterResolver:
        any CertifiedIntersectionParameterResolving
    private let intersectionBoundResolver:
        any CertifiedReducedSectionIntersectionBoundResolving

    init(
        parameterResolver:
            any CertifiedIntersectionParameterResolving =
                DefaultCertifiedIntersectionParameterResolver(),
        intersectionBoundResolver:
            any CertifiedReducedSectionIntersectionBoundResolving =
                DefaultCertifiedReducedSectionIntersectionBoundResolver()
    ) {
        self.parameterResolver = parameterResolver
        self.intersectionBoundResolver = intersectionBoundResolver
    }

    func classification(
        of section: SurfaceSurfaceIntersectionCurve,
        relativeTo curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedReducedSectionComponentClassification {
        // Bézout bounds isolated intersections between the certified
        // complete-intersection curve and the target surface by the product
        // of their algebraic degrees. One additional distinct witness proves
        // that the reduced section and queried curve share a component.
        let isolatedIntersectionUpperBound = try intersectionBoundResolver
            .isolatedIntersectionUpperBound(
                curve: curve,
                targetSurface: targetSurface,
                tolerance: tolerance
            )
        let witnessCount = isolatedIntersectionUpperBound + 1
        let sectionCurve = section.curve
        var witnesses: [Point3D] = []
        witnesses.reserveCapacity(witnessCount)
        var matchingWitnessCount = 0

        for index in 0..<witnessCount {
            let fraction = (Double(index) + 0.5) / Double(witnessCount)
            let parameter = try sectionParameter(
                atNormalizedFraction: fraction,
                domain: sectionCurve.parameterDomain,
                tolerance: tolerance
            )
            let point = try sectionCurve.point(
                at: parameter,
                tolerance: tolerance
            )
            guard witnesses.allSatisfy({
                ($0 - point).length > tolerance.distance
            }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A reduced section did not provide enough distinct algebraic component witnesses."
                )
            }
            witnesses.append(point)
            let parameters = try parameterResolver.normalizedParameters(
                of: point,
                on: curve,
                restrictedTo: nil,
                tolerance: tolerance
            )
            if parameters.isEmpty == false {
                matchingWitnessCount += 1
            }
        }

        if matchingWitnessCount == witnessCount {
            return .identical
        }
        return .distinct
    }

    private func sectionParameter(
        atNormalizedFraction fraction: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try domain.validate(tolerance: tolerance)
        switch domain {
        case .unbounded:
            return tan(Double.pi * (fraction - 0.5))
        case let .closed(lower, upper):
            return lower + (upper - lower) * fraction
        case let .periodic(period):
            return period * fraction
        }
    }

}
