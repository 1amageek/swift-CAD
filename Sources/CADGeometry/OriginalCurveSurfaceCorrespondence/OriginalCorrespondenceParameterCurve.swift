import CADCore

struct OriginalCorrespondenceParameterCurve {
    private let native: OriginalCorrespondenceNativeCurve?
    private let nativeLower: Double
    private let nativeUpper: Double
    private let uOrigin: OriginalCorrespondenceScalarJet
    private let vOrigin: OriginalCorrespondenceScalarJet
    private let uDirection: OriginalCorrespondenceScalarJet
    private let vDirection: OriginalCorrespondenceScalarJet
    private let start: Double
    private let end: Double

    init(source: SurfaceParameterCurve, support: OriginalCorrespondenceSupport,
         budget: inout OriginalCorrespondenceBudget) throws {
        var controls: [Point2D] = []
        switch source {
        case let .bSpline(value):
            guard (1...4).contains(value.degree) else { throw budget.unsupported() }
            // This exact numeric embedding retains the original 2D coefficients and knots.
            let spatial = BSplineCurve3D(degree: value.degree, knots: value.knots,
                controlPoints: value.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }, weights: value.weights)
            let prepared = try OriginalCorrespondenceNativeCurve(source: spatial, maximumDegree: 4, budget: &budget)
            native = prepared; nativeLower = prepared.lower; nativeUpper = prepared.upper
            uOrigin = .constant(0); vOrigin = .constant(0)
            uDirection = .constant(0); vDirection = .constant(0); start = 0; end = 1
            controls = value.controlPoints
        case let .affine(origin, direction, lower, upper):
            guard [origin.x, origin.y, direction.x, direction.y, lower, upper].allSatisfy(\.isFinite),
                  lower != upper, direction.x != 0 || direction.y != 0 else {
                throw OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance, "Invalid original affine chart.")
            }
            native = nil; nativeLower = 0; nativeUpper = 1
            uOrigin = .constant(origin.x); vOrigin = .constant(origin.y)
            uDirection = .constant(direction.x); vDirection = .constant(direction.y); start = lower; end = upper
        case let .constantU(u, lower, upper):
            guard [u, lower, upper].allSatisfy(\.isFinite), lower != upper else {
                throw OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance, "Invalid original constant-U chart.")
            }
            native = nil; nativeLower = 0; nativeUpper = 1
            uOrigin = .constant(u); vOrigin = .constant(0)
            uDirection = .constant(0); vDirection = .constant(1); start = lower; end = upper
        case let .constantV(v, lower, upper):
            guard [v, lower, upper].allSatisfy(\.isFinite), lower != upper else {
                throw OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance, "Invalid original constant-V chart.")
            }
            native = nil; nativeLower = 0; nativeUpper = 1
            uOrigin = .constant(0); vOrigin = .constant(v)
            uDirection = .constant(1); vDirection = .constant(0); start = lower; end = upper
        default: throw budget.unsupported()
        }
        if native != nil {
            // Positive rational weights prove the entire image lies in the original control hull.
            for point in controls {
                if let domain = support.uDomain, !domain.contains(point.x) { throw outside(budget) }
                if let domain = support.vDomain, !domain.contains(point.y) { throw outside(budget) }
            }
        } else {
            let a = uOrigin + uDirection * .constant(start)
            let b = uOrigin + uDirection * .constant(end)
            let c = vOrigin + vDirection * .constant(start)
            let d = vOrigin + vDirection * .constant(end)
            for (value, domain) in [(a.value.union(b.value), support.uDomain),
                                    (c.value.union(d.value), support.vDomain)] {
                if let domain, value.lower < domain.lower || value.upper > domain.upper { throw outside(budget) }
            }
        }
    }

    func enclose(fraction: OriginalCorrespondenceScalarJet, budget: inout OriginalCorrespondenceBudget) throws
        -> (u: OriginalCorrespondenceScalarJet, v: OriginalCorrespondenceScalarJet) {
        if let native {
            let time = OriginalCorrespondenceScalarJet.constant(nativeLower)
                + (.constant(nativeUpper) - .constant(nativeLower)) * fraction
            let jets = try native.enclose(parameter: time, budget: &budget)
            return (jets[0], jets[1])
        }
        try budget.charge()
        let time = OriginalCorrespondenceScalarJet.constant(start) + (.constant(end) - .constant(start)) * fraction
        return (uOrigin + uDirection * time, vOrigin + vDirection * time)
    }

    private func outside(_ budget: OriginalCorrespondenceBudget) -> KernelError {
        OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance,
            "The entire original pcurve control/affine hull must belong to its support domain without clipping.")
    }
}
