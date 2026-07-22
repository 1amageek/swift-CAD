import CADCore

struct PlaneBSplineBoundarySurfaceIntersector {
    private enum Boundary: CaseIterable {
        case uLower
        case uUpper
        case vLower
        case vUpper
    }

    private struct BoundaryCandidate {
        let boundary: Boundary
        let planeLayerCount: Int
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        let distances = surface.controlPoints.flatMap { row in
            row.map { signedDistance($0, plane: plane) }
        }
        let maximumResidual = distances.reduce(0.0) { max($0, abs($1)) }
        if distances.allSatisfy({ abs($0) <= tolerance.distance }) {
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: maximumResidual,
                tolerance: tolerance
            ))]
        }

        let candidates = Boundary.allCases.compactMap { boundary in
            boundaryCandidate(
                boundary,
                surface: surface,
                distances: distances,
                tolerance: tolerance
            )
        }
        guard !candidates.isEmpty else {
            if distances.allSatisfy({ $0 > tolerance.distance })
                || distances.allSatisfy({ $0 < -tolerance.distance }) {
                return []
            }
            return nil
        }
        for candidate in candidates where candidate.planeLayerCount > degree(
            for: candidate.boundary,
            surface: surface
        ) {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "Plane and B-spline surface share a non-discrete boundary strip."
            )
        }

        let boundaryIndexSet = Set(candidates.flatMap { candidate in
            (0..<candidate.planeLayerCount).flatMap {
                layerIndices(candidate.boundary, layer: $0, surface: surface)
            }
        })
        let interiorDistances = distances.enumerated().compactMap { index, distance in
            boundaryIndexSet.contains(index) ? nil : distance
        }
        let side: Double
        if interiorDistances.allSatisfy({ $0 > tolerance.distance }) {
            side = 1.0
        } else if interiorDistances.allSatisfy({ $0 < -tolerance.distance }) {
            side = -1.0
        } else {
            return nil
        }
        guard boundaryIndexSet.allSatisfy({ distances[$0] * side >= 0.0 }) else {
            return nil
        }

        return try candidates.map { candidate in
            let curve = try isoparametricCurve(
                candidate.boundary,
                surface: surface,
                tolerance: tolerance
            )
            let sampleParameters = try samples(curve.domain, tolerance: tolerance)
            return try verifier.curve(
                .bSpline(curve),
                kind: contactKind(for: candidate, among: candidates),
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: sampleParameters,
                tolerance: tolerance
            )
        }
    }

    private func boundaryCandidate(
        _ boundary: Boundary,
        surface: BSplineSurface3D,
        distances: [Double],
        tolerance: ModelingTolerance
    ) -> BoundaryCandidate? {
        guard isClamped(boundary, surface: surface) else { return nil }
        var planeLayerCount = 0
        for layer in 0..<layerCount(for: boundary, surface: surface) {
            let indices = layerIndices(boundary, layer: layer, surface: surface)
            guard indices.allSatisfy({ abs(distances[$0]) <= tolerance.distance }) else {
                break
            }
            planeLayerCount += 1
        }
        guard planeLayerCount > 0 else { return nil }
        return BoundaryCandidate(boundary: boundary, planeLayerCount: planeLayerCount)
    }

    private func signedDistance(
        _ point: Point3D,
        plane: CanonicalAnalyticSurface.Plane
    ) -> Double {
        (point - plane.origin).dot(plane.normal)
    }

    private func isClamped(
        _ boundary: Boundary,
        surface: BSplineSurface3D
    ) -> Bool {
        switch boundary {
        case .uLower:
            return isClampedLower(surface.uKnots, degree: surface.uDegree)
        case .uUpper:
            return isClampedUpper(surface.uKnots, degree: surface.uDegree)
        case .vLower:
            return isClampedLower(surface.vKnots, degree: surface.vDegree)
        case .vUpper:
            return isClampedUpper(surface.vKnots, degree: surface.vDegree)
        }
    }

    private func isClampedLower(_ knots: [Double], degree: Int) -> Bool {
        guard degree >= 0, knots.count > degree else { return false }
        let endpoint = knots[degree]
        return knots.prefix(degree + 1).allSatisfy { $0 == endpoint }
    }

    private func isClampedUpper(_ knots: [Double], degree: Int) -> Bool {
        guard degree >= 0, knots.count > degree else { return false }
        let endpoint = knots[knots.count - degree - 1]
        return knots.suffix(degree + 1).allSatisfy { $0 == endpoint }
    }

    private func layerCount(
        for boundary: Boundary,
        surface: BSplineSurface3D
    ) -> Int {
        switch boundary {
        case .uLower, .uUpper:
            return surface.uControlPointCount
        case .vLower, .vUpper:
            return surface.vControlPointCount
        }
    }

    private func degree(
        for boundary: Boundary,
        surface: BSplineSurface3D
    ) -> Int {
        switch boundary {
        case .uLower, .uUpper:
            return surface.uDegree
        case .vLower, .vUpper:
            return surface.vDegree
        }
    }

    private func layerIndices(
        _ boundary: Boundary,
        layer: Int,
        surface: BSplineSurface3D
    ) -> [Int] {
        switch boundary {
        case .uLower:
            return (0..<surface.vControlPointCount).map {
                $0 * surface.uControlPointCount + layer
            }
        case .uUpper:
            return (0..<surface.vControlPointCount).map {
                $0 * surface.uControlPointCount + surface.uControlPointCount - 1 - layer
            }
        case .vLower:
            let offset = layer * surface.uControlPointCount
            return (0..<surface.uControlPointCount).map { offset + $0 }
        case .vUpper:
            let offset = (surface.vControlPointCount - 1 - layer) * surface.uControlPointCount
            return (0..<surface.uControlPointCount).map { offset + $0 }
        }
    }

    private func isoparametricCurve(
        _ boundary: Boundary,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        switch boundary {
        case .uLower:
            guard case let .closed(lower, _) = surface.uDomain else {
                throw GeometryError.invalidDistance(0.0)
            }
            return try surface.vIsoparametricCurve(atU: lower, tolerance: tolerance)
        case .uUpper:
            guard case let .closed(_, upper) = surface.uDomain else {
                throw GeometryError.invalidDistance(0.0)
            }
            return try surface.vIsoparametricCurve(atU: upper, tolerance: tolerance)
        case .vLower:
            guard case let .closed(lower, _) = surface.vDomain else {
                throw GeometryError.invalidDistance(0.0)
            }
            return try surface.uIsoparametricCurve(atV: lower, tolerance: tolerance)
        case .vUpper:
            guard case let .closed(_, upper) = surface.vDomain else {
                throw GeometryError.invalidDistance(0.0)
            }
            return try surface.uIsoparametricCurve(atV: upper, tolerance: tolerance)
        }
    }

    private func samples(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard case let .closed(lower, upper) = domain,
              upper - lower > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline boundary intersection requires a finite non-degenerate curve domain."
            )
        }
        let span = upper - lower
        return [lower, lower + span * 0.25, lower + span * 0.5, lower + span * 0.75, upper]
    }

    private func contactKind(
        for candidate: BoundaryCandidate,
        among candidates: [BoundaryCandidate]
    ) -> CurveSurfaceIntersectionKind {
        if candidate.planeLayerCount > 1 {
            return .tangent
        }
        return candidates.contains { other in
            other.boundary != candidate.boundary
                && areAdjacent(candidate.boundary, other.boundary)
        } ? .mixed : .transverse
    }

    private func areAdjacent(_ first: Boundary, _ second: Boundary) -> Bool {
        switch (first, second) {
        case (.uLower, .vLower), (.uLower, .vUpper),
             (.uUpper, .vLower), (.uUpper, .vUpper),
             (.vLower, .uLower), (.vUpper, .uLower),
             (.vLower, .uUpper), (.vUpper, .uUpper):
            return true
        default:
            return false
        }
    }

}
