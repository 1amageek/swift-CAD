import CADCore

struct PlaneBSplineSurfaceIntersector {
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        planeIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        if let boundaryIntersections = try PlaneBSplineBoundarySurfaceIntersector().intersections(
            plane: plane,
            surface: surface,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            planeIsFirst: planeIsFirst,
            tolerance: tolerance
        ) {
            return boundaryIntersections
        }
        if let isoparametric = try PlaneBSplineIsoparametricIntersector().intersections(
            plane: plane, surface: surface, firstSurface: firstSurface, secondSurface: secondSurface,
            planeIsFirst: planeIsFirst, tolerance: tolerance
        ) {
            return isoparametric
        }
        return try AnalyticBSplineSurfaceIntersector().intersections(
            analytic: .plane(plane),
            surface: surface,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            analyticIsFirst: planeIsFirst,
            options: options,
            tolerance: tolerance
        )
    }
}
