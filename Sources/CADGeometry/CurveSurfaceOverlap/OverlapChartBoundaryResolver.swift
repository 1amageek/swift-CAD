import CADCore

/// Reduces complete chart-boundary discovery to existing certified plane queries.
struct OverlapChartBoundaryResolver {
    struct Boundary {
        let plane: Surface3D
        let parameterPlaneSource: Curve3D?
    }

    func boundaries(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                    tolerance: ModelingTolerance) throws -> [Boundary] {
        var uValues = endpoints(options.surfaceURange, domain: surface.uDomain)
        var vValues = endpoints(options.surfaceVRange, domain: surface.vDomain)
        if case .bSpline(let spline) = surface, let affine = ExactAffineBSplineSurfacePatch(spline) {
            guard case let .closed(uLower, uUpper) = spline.uDomain,
                  case let .closed(vLower, vUpper) = spline.vDomain else {
                throw error("An affine overlap patch must retain its bounded chart.", tolerance)
            }
            uValues.append(contentsOf: [uLower, uUpper])
            vValues.append(contentsOf: [vLower, vUpper])
            let normal = try affine.uDirection.cross(affine.vDirection).normalized(tolerance: tolerance.distance)
            return try uValues.map { value in
                try boundary(origin: affine.origin + affine.uDirection * ((value - uLower) / (uUpper - uLower)),
                             normal: normal.cross(affine.vDirection), source: nil, tolerance: tolerance)
            } + vValues.map { value in
                try boundary(origin: affine.origin + affine.vDirection * ((value - vLower) / (vUpper - vLower)),
                             normal: normal.cross(affine.uDirection), source: nil, tolerance: tolerance)
            }
        }
        switch CanonicalAnalyticSurface(surface) {
        case .plane:
            if uValues.isEmpty, vValues.isEmpty { return [] }
            let geometry = try surface.differentialGeometry(u: 0, v: 0, tolerance: tolerance)
            return try uValues.map {
                try boundary(origin: surface.point(u: $0, v: 0, tolerance: tolerance),
                             normal: geometry.normal.cross(geometry.tangentV), source: nil, tolerance: tolerance)
            } + vValues.map {
                try boundary(origin: surface.point(u: 0, v: $0, tolerance: tolerance),
                             normal: geometry.normal.cross(geometry.tangentU), source: nil, tolerance: tolerance)
            }
        case .cylinder(let cylinder):
            return try angularBoundaries(surface: surface, origin: cylinder.origin, axis: cylinder.axis,
                uValues: uValues, vValues: vValues, referenceV: 0, tolerance: tolerance)
        case .cone(let cone):
            return try angularBoundaries(surface: surface, origin: cone.apex, axis: cone.axis,
                uValues: uValues, vValues: vValues, referenceV: 1, tolerance: tolerance)
        case .sphere(let sphere):
            return try angularBoundaries(surface: surface, origin: sphere.center, axis: .unitZ,
                uValues: uValues, vValues: vValues, referenceV: 0, tolerance: tolerance)
        case .torus(let torus):
            return try angularBoundaries(surface: surface, origin: torus.center, axis: torus.axis,
                uValues: uValues, vValues: vValues, referenceV: 0, tolerance: tolerance)
        case .unsupported:
            if case let .closed(lower, upper) = surface.uDomain { uValues.append(contentsOf: [lower, upper]) }
            if case let .closed(lower, upper) = surface.vDomain { vValues.append(contentsOf: [lower, upper]) }
            if uValues.isEmpty, vValues.isEmpty { return [] }
            if case .surfaceLift(let lift) = curve, lift.surface == surface, isIndependentCoordinateCurve(lift.parameterCurve) {
                let plane = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
                let surrogate = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: plane, parameterCurve: lift.parameterCurve))
                let geometry = try plane.differentialGeometry(u: 0, v: 0, tolerance: tolerance)
                return try uValues.map {
                    try boundary(origin: plane.point(u: $0, v: 0, tolerance: tolerance),
                                 normal: geometry.tangentU, source: surrogate, tolerance: tolerance)
                } + vValues.map {
                    try boundary(origin: plane.point(u: 0, v: $0, tolerance: tolerance),
                                 normal: geometry.tangentV, source: surrogate, tolerance: tolerance)
                }
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Complex authored pcurves and free-surface
            // coincidence without a retained coordinate curve lack complete chart clipping.
            // Production intersectionResult must certify every boundary crossing before
            // it may classify connected cells and return continuous overlap intervals.
            throw error("Continuous overlap chart clipping has no complete boundary reduction for this representation.", tolerance)
        }
    }

    private func angularBoundaries(surface: Surface3D, origin: Point3D, axis: Vector3D,
                                   uValues: [Double], vValues: [Double], referenceV: Double,
                                   tolerance: ModelingTolerance) throws -> [Boundary] {
        try uValues.map {
            let radial = try surface.point(u: $0, v: referenceV, tolerance: tolerance) - origin
            return try boundary(origin: origin, normal: axis.cross(radial), source: nil, tolerance: tolerance)
        } + vValues.map {
            try boundary(origin: surface.point(u: 0, v: $0, tolerance: tolerance), normal: axis,
                         source: nil, tolerance: tolerance)
        }
    }

    private func boundary(origin: Point3D, normal: Vector3D, source: Curve3D?, tolerance: ModelingTolerance) throws -> Boundary {
        Boundary(plane: .plane(Plane3D(origin: origin, normal: try normal.normalized(tolerance: tolerance.distance))),
                 parameterPlaneSource: source)
    }

    private func endpoints(_ range: ScalarInterval?, domain: ParameterDomain) -> [Double] {
        guard let range else { return [] }
        if case .periodic(let period) = domain, range.width >= period { return [] }
        return range.lower == range.upper ? [range.lower] : [range.lower, range.upper]
    }

    private func isIndependentCoordinateCurve(_ curve: SurfaceParameterCurve) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline: return true
        case .periodicTranslation(let base, _, _): return isIndependentCoordinateCurve(base)
        default: return false
        }
    }

    private func error(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
}
