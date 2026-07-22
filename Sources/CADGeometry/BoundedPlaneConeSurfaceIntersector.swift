import CADCore
import Foundation

struct BoundedPlaneConeSurfaceIntersector {
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        let planeSurface = Self.planeSurface(firstSurface, secondSurface: secondSurface)
        let coneSurface = firstSurface == planeSurface ? secondSurface : firstSurface
        let containsApex = abs((cone.apex - plane.origin).dot(plane.normal))
            <= tolerance.distance
        guard containsApex == false else { return nil }
        guard boundaryPoints.count >= 2 else { return [] }

        let candidates = try PlaneConeSurfaceIntersector().intersections(
            plane: plane,
            cone: cone,
            firstSurface: planeSurface,
            secondSurface: coneSurface,
            tolerance: tolerance
        ).compactMap(Self.analyticConic)
        guard candidates.isEmpty == false else { return nil }

        let uniqueBoundaryPoints = deduplicated(boundaryPoints, tolerance: tolerance)
        var parametersByCandidate = Array(repeating: [Double](), count: candidates.count)
        for point in uniqueBoundaryPoints {
            var matchedCandidate: Int?
            for index in candidates.indices {
                guard let parameter = try parameter(
                    of: point,
                    on: candidates[index],
                    tolerance: tolerance
                ) else {
                    continue
                }
                guard matchedCandidate == nil else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        tolerance: tolerance,
                        message: "A bounded plane-cone boundary contact ambiguously belongs to multiple exact branches."
                    )
                }
                matchedCandidate = index
                parametersByCandidate[index].append(parameter)
            }
            guard matchedCandidate != nil else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A bounded plane-cone boundary contact does not lie on an exact section branch."
                )
            }
        }

        var result: [SurfaceSurfaceIntersection] = []
        for index in candidates.indices {
            let parameters = deduplicated(
                parametersByCandidate[index],
                tolerance: tolerance
            )
            guard let lower = parameters.first,
                  let upper = parameters.last,
                  upper > lower else {
                continue
            }
            let exactCurve = try CertifiedBoundedPlaneConeIntersectionCurve(
                planeSurface: planeSurface,
                coneSurface: coneSurface,
                analyticCurve: candidates[index],
                startParameter: lower,
                endParameter: upper,
                tolerance: tolerance
            )
            let wrapper = try CertifiedAnalyticAnalyticIntersectionCurve(
                boundedPlaneConeCurve: exactCurve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
            let builder = SurfaceIntersectionSplineBuilder(
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            )
            let segmentCount = min(8, max(1, options.maximumSeedCount))
            let breaks = (0...segmentCount).map {
                Double($0) / Double(segmentCount)
            }
            let derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: breaks,
                kind: .transverse,
                isClosed: false,
                pointAt: { fraction in
                    try exactCurve.point(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                }
            )
            guard case let .curve(derivedCurve) = derived else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A bounded plane-cone derived representation did not produce a curve."
                )
            }
            result.append(.curve(try SurfaceSurfaceIntersectionCurve(
                truth: .analyticAnalytic(wrapper),
                derivedRepresentation: derivedCurve.derivedRepresentation,
                kind: .transverse,
                firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
                secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
                tolerance: tolerance
            )))
        }
        return result
    }

    private static func planeSurface(
        _ firstSurface: Surface3D,
        secondSurface: Surface3D
    ) -> Surface3D {
        if case .plane = CanonicalAnalyticSurface(firstSurface) {
            return firstSurface
        }
        return secondSurface
    }

    private static func analyticConic(
        _ intersection: SurfaceSurfaceIntersection
    ) -> AnalyticCurve3D? {
        guard case let .curve(value) = intersection,
              case let .parametric(.analytic(curve)) = value.truth else {
            return nil
        }
        switch curve {
        case .hyperbola, .parabola:
            return curve
        case .line, .circle, .arc, .ellipse, .planeTorus:
            return nil
        }
    }

    private func parameter(
        of point: Point3D,
        on curve: AnalyticCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let parameter: Double
        switch curve {
        case let .hyperbola(hyperbola):
            parameter = try hyperbola.parameter(for: point, tolerance: tolerance)
        case let .parabola(parabola):
            parameter = try parabola.parameter(for: point, tolerance: tolerance)
        case .line, .circle, .arc, .ellipse, .planeTorus:
            return nil
        }
        let reconstructed = try curve.point(at: parameter, tolerance: tolerance)
        return (reconstructed - point).length <= tolerance.distance ? parameter : nil
    }

    private func deduplicated(
        _ points: [Point3D],
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        points.sorted(by: lexicographicPointOrder).reduce(into: []) { result, point in
            if result.last.map({ ($0 - point).length <= tolerance.distance }) != true {
                result.append(point)
            }
        }
    }

    private func deduplicated(
        _ parameters: [Double],
        tolerance: ModelingTolerance
    ) -> [Double] {
        parameters.sorted().reduce(into: []) { result, parameter in
            if result.last.map({ abs($0 - parameter) <= tolerance.relative }) != true {
                result.append(parameter)
            }
        }
    }

    private func lexicographicPointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}
