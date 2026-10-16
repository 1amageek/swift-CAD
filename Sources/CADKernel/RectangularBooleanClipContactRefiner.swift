import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Refines a tolerance-band boundary contact to the exact face-local trim
/// coordinate carried by a surface-surface intersection pcurve.
struct RectangularBooleanClipContactRefiner {
    struct Contact: Sendable {
        let parameter: Double
        let point: Point3D
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Boolean UV splitting uses this numerical
    // contact proposal; residual/bisection stopping does not certify an original
    // root. Retained source root authority is required before exact completion.
    func refine(
        parameter: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        boundaryFaceID: FaceID,
        boundaryEdgeID: EdgeID,
        pair: BooleanFacePairCandidate,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Contact? {
        try execution.consumeWork(1)
        if case .unbounded = intersection.curve.parameterDomain {
            return nil
        }
        return try refineBounded(
            parameter: parameter,
            intersection: intersection,
            boundaryFaceID: boundaryFaceID,
            boundaryEdgeID: boundaryEdgeID,
            pair: pair,
            model: model,
            tolerance: tolerance
        , using: &execution)
    }

    private func refineBounded(
        parameter: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        boundaryFaceID: FaceID,
        boundaryEdgeID: EdgeID,
        pair: BooleanFacePairCandidate,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Contact? {
        try execution.consumeWork(1)
        guard let boundary = try boundary(
            faceID: boundaryFaceID,
            edgeID: boundaryEdgeID,
            model: model,
            tolerance: tolerance
        , using: &execution) else {
            return nil
        }
        let role: SurfaceIntersectionSurfaceRole
        if boundaryFaceID == pair.targetFaceID {
            role = .first
        } else if boundaryFaceID == pair.toolFaceID {
            role = .second
        } else {
            return nil
        }
        return try refinedContact(
            parameter: parameter,
            intersection: intersection,
            role: role,
            boundary: boundary,
            tolerance: tolerance
        , using: &execution)
    }

    func refineNearestBoundary(
        parameter: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        pair: BooleanFacePairCandidate,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Contact? {
        try execution.consumeWork(1)
        if case .unbounded = intersection.curve.parameterDomain {
            return nil
        }
        var candidates: [(role: SurfaceIntersectionSurfaceRole, boundary: Boundary)] = []
        for (faceID, role) in [
            (pair.targetFaceID, SurfaceIntersectionSurfaceRole.first),
            (pair.toolFaceID, SurfaceIntersectionSurfaceRole.second),
        ] {
            guard let face = model.faces[faceID],
                  let domain = try ExactRectangularPcurveDomainResolver().resolve(
                      face: face,
                      model: model,
                      tolerance: tolerance
                  , using: &execution) else {
                continue
            }
            try execution.retainKernelValues(count: 4,
                stride: MemoryLayout<(SurfaceIntersectionSurfaceRole, Boundary)>.stride)
            candidates.append(contentsOf: [
                (role, .u(domain.uLower)),
                (role, .u(domain.uUpper)),
                (role, .v(domain.vLower)),
                (role, .v(domain.vUpper)),
            ])
        }
        let originalFraction = try normalizedFraction(
            parameter,
            domain: intersection.curve.parameterDomain,
            tolerance: tolerance
        )
        try execution.retainKernelValues(count: candidates.count,
            stride: MemoryLayout<(Contact, Double)>.stride)
        let evaluated = try candidates.compactMap { candidate -> (
            contact: Contact,
            fractionDistance: Double
        )? in
            guard let contact = try refinedContact(
                parameter: parameter,
                intersection: intersection,
                role: candidate.role,
                boundary: candidate.boundary,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            let fraction = try normalizedFraction(
                contact.parameter,
                domain: intersection.curve.parameterDomain,
                tolerance: tolerance
            )
            return (
                contact,
                fractionDistance(
                    originalFraction,
                    fraction,
                    domain: intersection.curve.parameterDomain
                )
            )
        }
        return evaluated.min {
            if $0.fractionDistance == $1.fractionDistance {
                return $0.contact.parameter < $1.contact.parameter
            }
            return $0.fractionDistance < $1.fractionDistance
        }?.contact
    }

    private func boundary(
        faceID: FaceID,
        edgeID: EdgeID,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Boundary? {
        try execution.consumeWork(1)
        guard let face = model.faces[faceID],
              try ExactRectangularPcurveDomainResolver().resolve(
                  face: face,
                  model: model,
                  tolerance: tolerance
              , using: &execution) != nil else {
            return nil
        }
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else { return nil }
            for coedge in loop.coedges where coedge.edgeID == edgeID {
                try execution.consumeWork(1)
                guard let pcurve = coedge.surfaceParameterCurve else { return nil }
                let start = try pcurve.startParameter(tolerance: tolerance, using: &execution)
                let end = try pcurve.endParameter(tolerance: tolerance, using: &execution)
                let scale = max(
                    abs(start.u), abs(start.v), abs(end.u), abs(end.v), 1.0
                )
                let resolution = max(
                    tolerance.relative * scale,
                    Double.ulpOfOne * scale * 256.0
                )
                if abs(start.u - end.u) <= resolution {
                    return .u(0.5 * (start.u + end.u))
                }
                if abs(start.v - end.v) <= resolution {
                    return .v(0.5 * (start.v + end.v))
                }
                return nil
            }
        }
        return nil
    }

    private func refinedContact(
        parameter: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        boundary: Boundary,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Contact? {
        try execution.consumeWork(1)
        let domain = intersection.curve.parameterDomain
        let initialFraction = try normalizedFraction(
            parameter,
            domain: domain,
            tolerance: tolerance
        )
        let initialResidual = try residual(
            fraction: initialFraction,
            intersection: intersection,
            role: role,
            boundary: boundary,
            tolerance: tolerance
        , using: &execution)
        let boundaryValue = boundary.value
        let scale = max(abs(boundaryValue), 1.0)
        let acceptance = max(
            tolerance.distance,
            tolerance.angle,
            tolerance.relative * scale
        ) * 8.0
        guard abs(initialResidual) <= acceptance else { return nil }

        // A trim contact can be tangent to a rectangular boundary. In that
        // case the boundary-coordinate residual is quadratic in the spatial
        // endpoint error, so the model's linear relative tolerance is too
        // coarse as a root stopping criterion. Refine the coordinate root to
        // floating-point resolution; the model tolerance remains the
        // acceptance band that decides whether this is the intended root.
        let numericalResolution = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne * scale * 16.0
        )
        var fraction = initialFraction
        for _ in 0..<24 {
            try execution.consumeWork(1)
            let differential = try parameterCurve(
                intersection: intersection,
                role: role
            ).differentialGeometry(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            let value = boundary.coordinate(differential.parameter) - boundaryValue
            if abs(value) <= numericalResolution {
                return try contact(
                    fraction: fraction,
                    intersection: intersection,
                    tolerance: tolerance
                , using: &execution)
            }
            let derivative = boundary.coordinate(differential.firstDerivative)
            guard abs(derivative) > numericalResolution else { break }
            let step = min(max(value / derivative, -1.0 / 128.0), 1.0 / 128.0)
            let next = canonicalFraction(fraction - step, domain: domain)
            guard fractionDistance(next, fraction, domain: domain) > Double.ulpOfOne else {
                break
            }
            fraction = next
        }

        var halfWidth = 1.0 / 16_777_216.0
        for _ in 0..<16 {
            try execution.consumeWork(1)
            let lower = canonicalFraction(initialFraction - halfWidth, domain: domain)
            let upper = canonicalFraction(initialFraction + halfWidth, domain: domain)
            if lower <= upper {
                let lowerResidual = try residual(
                    fraction: lower,
                    intersection: intersection,
                    role: role,
                    boundary: boundary,
                    tolerance: tolerance
                , using: &execution)
                let upperResidual = try residual(
                    fraction: upper,
                    intersection: intersection,
                    role: role,
                    boundary: boundary,
                    tolerance: tolerance
                , using: &execution)
                if lowerResidual == 0.0 {
                    return try contact(
                        fraction: lower,
                        intersection: intersection,
                        tolerance: tolerance
                    , using: &execution)
                }
                if upperResidual == 0.0 {
                    return try contact(
                        fraction: upper,
                        intersection: intersection,
                        tolerance: tolerance
                    , using: &execution)
                }
                if (lowerResidual < 0.0) != (upperResidual < 0.0) {
                    let root = try bisectedRoot(
                        lower: lower,
                        lowerResidual: lowerResidual,
                        upper: upper,
                        intersection: intersection,
                        role: role,
                        boundary: boundary,
                        numericalResolution: numericalResolution,
                        tolerance: tolerance
                    , using: &execution)
                    return try contact(
                        fraction: root,
                        intersection: intersection,
                        tolerance: tolerance
                    , using: &execution)
                }
            }
            halfWidth *= 2.0
        }
        return nil
    }

    private func bisectedRoot(
        lower: Double,
        lowerResidual: Double,
        upper: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        boundary: Boundary,
        numericalResolution: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var low = lower
        var high = upper
        var lowResidual = lowerResidual
        for _ in 0..<80 {
            try execution.consumeWork(1)
            let middle = low + (high - low) * 0.5
            let middleResidual = try residual(
                fraction: middle,
                intersection: intersection,
                role: role,
                boundary: boundary,
                tolerance: tolerance
            , using: &execution)
            if abs(middleResidual) <= numericalResolution
                || high - low <= Double.ulpOfOne * 64.0 {
                return middle
            }
            if (middleResidual < 0.0) == (lowResidual < 0.0) {
                low = middle
                lowResidual = middleResidual
            } else {
                high = middle
            }
        }
        return low + (high - low) * 0.5
    }

    private func residual(
        fraction: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        boundary: Boundary,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let curveParameter = try curveParameter(fraction: fraction,
            domain: intersection.curve.parameterDomain, tolerance: tolerance)
        let pair = try intersection.surfaceParameterPair(atCurveParameter: curveParameter,
            tolerance: tolerance, using: &execution)
        let parameter = role == .first ? pair.first : pair.second
        return boundary.coordinate(parameter) - boundary.value
    }

    private func contact(
        fraction: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Contact {
        try execution.consumeWork(1)
        let parameter = try curveParameter(
            fraction: fraction,
            domain: intersection.curve.parameterDomain,
            tolerance: tolerance
        )
        return Contact(
            parameter: parameter,
            point: try intersection.curve.point(
                at: parameter,
                tolerance: tolerance
            , using: &execution)
        )
    }

    private func parameterCurve(
        intersection: SurfaceSurfaceIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole
    ) -> SurfaceParameterCurve {
        role == .first
            ? intersection.firstSurfaceParameterCurve
            : intersection.secondSurfaceParameterCurve
    }

    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        switch domain {
        case let .closed(lower, upper):
            let span = upper - lower
            guard span > tolerance.relative,
                  parameter >= lower - tolerance.relative,
                  parameter <= upper + tolerance.relative else {
                throw GeometryError.invalidDistance(parameter)
            }
            return min(max((parameter - lower) / span, 0.0), 1.0)
        case let .periodic(period):
            let remainder = parameter.truncatingRemainder(dividingBy: period)
            return (remainder >= 0.0 ? remainder : remainder + period) / period
        case .unbounded:
            throw GeometryError.invalidDistance(parameter)
        }
    }

    private func curveParameter(
        fraction: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        switch domain {
        case let .closed(lower, upper):
            return lower + (upper - lower) * fraction
        case let .periodic(period):
            return period * canonicalFraction(fraction, domain: domain)
        case .unbounded:
            throw GeometryError.invalidDistance(fraction)
        }
    }

    private func canonicalFraction(
        _ fraction: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case .periodic = domain else {
            return min(max(fraction, 0.0), 1.0)
        }
        let remainder = fraction.truncatingRemainder(dividingBy: 1.0)
        return remainder >= 0.0 ? remainder : remainder + 1.0
    }

    private func fractionDistance(
        _ first: Double,
        _ second: Double,
        domain: ParameterDomain
    ) -> Double {
        let direct = abs(first - second)
        guard case .periodic = domain else { return direct }
        return min(direct, 1.0 - direct)
    }

    private enum Boundary: Sendable {
        case u(Double)
        case v(Double)

        var value: Double {
            switch self {
            case let .u(value), let .v(value):
                value
            }
        }

        func coordinate(_ parameter: SurfaceParameter) -> Double {
            switch self {
            case .u: parameter.u
            case .v: parameter.v
            }
        }

        func coordinate(_ vector: Point2D) -> Double {
            switch self {
            case .u: vector.x
            case .v: vector.y
            }
        }
    }
}
