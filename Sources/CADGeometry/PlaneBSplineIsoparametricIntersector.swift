import CADCore

/// Reduces a surface/plane zero locus independent of one parameter to a complete curve root set.
struct PlaneBSplineIsoparametricIntersector {
    func intersections(
        plane: CanonicalAnalyticSurface.Plane, surface: BSplineSurface3D,
        firstSurface: Surface3D, secondSurface: Surface3D, planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        let coefficients = surface.controlPoints.enumerated().map { v, row in
            row.enumerated().map { u, point in (point - plane.origin).dot(plane.normal) * surface.weights[v][u] }
        }
        let fixedU: Bool
        if coefficients.dropFirst().allSatisfy({ $0 == coefficients[0] }) {
            fixedU = true
        } else if coefficients.allSatisfy({ row in row.allSatisfy { $0 == row[0] } }) {
            fixedU = false
        } else {
            return nil
        }
        guard case .closed(let u0, let u1) = surface.uDomain,
              case .closed(let v0, let v1) = surface.vDomain else { return nil }
        let section = try fixedU
            ? surface.uIsoparametricCurve(atV: (v0 + v1) / 2, tolerance: tolerance)
            : surface.vIsoparametricCurve(atU: (u0 + u1) / 2, tolerance: tolerance)
        let roots = try DefaultCurveSurfaceIntersector().intersections(
            curve: .bSpline(section), surface: planeIsFirst ? firstSurface : secondSurface,
            options: .init(), tolerance: tolerance)
        return try roots.map { root in
            let curve = try fixedU
                ? surface.vIsoparametricCurve(atU: root.curveParameter, tolerance: tolerance)
                : surface.uIsoparametricCurve(atV: root.curveParameter, tolerance: tolerance)
            let lower = fixedU ? v0 : u0
            let upper = fixedU ? v1 : u1
            let pcurve: SurfaceParameterCurve = fixedU
                ? .constantU(u: root.curveParameter, vStart: lower, vEnd: upper)
                : .constantV(v: root.curveParameter, uStart: lower, uEnd: upper)
            return try SurfaceSurfaceIntersectionVerifier().curve(
                .bSpline(curve), kind: root.kind, firstSurface: firstSurface, secondSurface: secondSurface,
                sampleParameters: [lower, (lower + upper) / 2, upper],
                firstParameterCurve: planeIsFirst ? nil : pcurve,
                secondParameterCurve: planeIsFirst ? pcurve : nil, tolerance: tolerance)
        }
    }
}
