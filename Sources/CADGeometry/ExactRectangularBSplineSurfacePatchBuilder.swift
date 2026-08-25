import Foundation
import CADCore

package struct ExactRectangularBSplineSurfacePatchBuilder: Sendable {
    package init() {}

    package func build(
        surface: Surface3D,
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularBSplineSurfacePatch {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard lowerU.isFinite,
              upperU.isFinite,
              lowerV.isFinite,
              upperV.isFinite,
              upperU - lowerU > tolerance.relative,
              upperV - lowerV > tolerance.relative,
              try surface.uDomain.containsSpan(
                  from: lowerU,
                  to: upperU,
                  tolerance: tolerance
              ),
              try surface.vDomain.containsSpan(
                  from: lowerV,
                  to: upperV,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An exact rectangular NURBS patch requires finite contained source bounds."
            )
        }

        let result: ExactRectangularBSplineSurfacePatch
        switch surface {
        case .plane, .analytic(.plane):
            result = try planarPatch(
                surface: surface,
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV,
                tolerance: tolerance
            )
        case let .cylinder(cylinder):
            let basis = try legacyCylinderBasis(
                axis: cylinder.axis,
                tolerance: tolerance
            )
            result = try cylindricalPatch(
                origin: cylinder.origin,
                axis: cylinder.axis,
                radius: cylinder.radius,
                radialU: basis.u,
                radialV: basis.v,
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV,
                tolerance: tolerance
            )
        case let .analytic(.cylinder(origin, axis, radius)):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            result = try cylindricalPatch(
                origin: origin,
                axis: axis,
                radius: radius,
                radialU: basis.u,
                radialV: basis.v,
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV,
                tolerance: tolerance
            )
        case let .analytic(.cone(apex, axis, halfAngle)):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            result = try conicalPatch(
                apex: apex,
                axis: axis,
                halfAngle: halfAngle,
                radialU: basis.u,
                radialV: basis.v,
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV,
                tolerance: tolerance
            )
        case let .analytic(.sphere(center, radius)):
            let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
            result = try sphericalPatch(
                center: center,
                radius: radius,
                radialU: basis.u,
                radialV: basis.v,
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV,
                tolerance: tolerance
            )
        case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            result = try toroidalPatch(
                center: center,
                axis: axis,
                majorRadius: majorRadius,
                minorRadius: minorRadius,
                radialU: basis.u,
                radialV: basis.v,
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV,
                tolerance: tolerance
            )
        case let .bSpline(spline):
            result = ExactRectangularBSplineSurfacePatch(
                surface: spline,
                uMapping: .init(
                    sourceLower: lowerU,
                    sourceUpper: upperU,
                    kind: .identity
                ),
                vMapping: .init(
                    sourceLower: lowerV,
                    sourceUpper: upperV,
                    kind: .identity
                )
            )
        case let .procedural(.offset(offset)):
            if let equivalent = try offset.exactChartPreservingSurface(
                tolerance: tolerance
            ) {
                return try build(
                    surface: equivalent,
                    lowerU: lowerU,
                    upperU: upperU,
                    lowerV: lowerV,
                    upperV: upperV,
                    tolerance: tolerance
                )
            }
            if try DefaultPlanarSurfaceResolver().exactPlane(
                for: surface,
                tolerance: tolerance
            ) != nil {
                result = try planarPatch(
                    surface: surface,
                    lowerU: lowerU,
                    upperU: upperU,
                    lowerV: lowerV,
                    upperV: upperV,
                    tolerance: tolerance
                )
            } else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact rational B-spline conversion requires a rationally representable source surface."
                )
            }
        case let .procedural(.ruled(ruled)):
            let interval = try ScalarInterval(lower: lowerU, upper: upperU)
            let curveBuilder = AnalyticCurveBSplineBuilder()
            guard let start = try curveBuilder.boundedCurve(
                      curve: ruled.startBoundary,
                      interval: interval,
                      maximumSpanCount: 64,
                      tolerance: tolerance
                  ),
                  let end = try curveBuilder.boundedCurve(
                      curve: ruled.endBoundary,
                      interval: interval,
                      maximumSpanCount: 64,
                      tolerance: tolerance
                  ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact rational B-spline conversion requires rationally representable ruled boundaries."
                )
            }
            let completeSurface = try ExactRuledBSplineSurfaceBuilder().build(
                startBoundary: start,
                endBoundary: end,
                tolerance: tolerance
            )
            guard let uMapping = ruledParameterMapping(
                start: ruled.startBoundary,
                end: ruled.endBoundary,
                lower: lowerU,
                upper: upperU
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact rational ruled conversion requires parameter-compatible rational boundary curves."
                )
            }
            result = ExactRectangularBSplineSurfacePatch(
                surface: try completeSurface.trimmed(
                    uFrom: 0.0,
                    uTo: 1.0,
                    vFrom: lowerV,
                    vTo: upperV,
                    tolerance: tolerance
                ),
                uMapping: uMapping,
                vMapping: identityMapping(lower: lowerV, upper: upperV)
            )
        }
        try result.surface.validate(tolerance: tolerance)
        return result
    }

    private func planarPatch(
        surface: Surface3D,
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularBSplineSurfacePatch {
        let point: (Double, Double) throws -> Point3D = { u, v in
            try surface.point(u: u, v: v, tolerance: tolerance)
        }
        return ExactRectangularBSplineSurfacePatch(
            surface: BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [lowerU, lowerU, upperU, upperU],
                vKnots: [lowerV, lowerV, upperV, upperV],
                controlPoints: [
                    [try point(lowerU, lowerV), try point(upperU, lowerV)],
                    [try point(lowerU, upperV), try point(upperU, upperV)],
                ]
            ),
            uMapping: identityMapping(lower: lowerU, upper: upperU),
            vMapping: identityMapping(lower: lowerV, upper: upperV)
        )
    }

    private func cylindricalPatch(
        origin: Point3D,
        axis: Vector3D,
        radius: Double,
        radialU: Vector3D,
        radialV: Vector3D,
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularBSplineSurfacePatch {
        let arc = try circularArc(
            lower: lowerU,
            upper: upperU,
            tolerance: tolerance
        )
        let rows = [lowerV, upperV].map { height in
            arc.controls.map { control in
                origin
                    + radialU * (control.x * radius)
                    + radialV * (control.y * radius)
                    + axis * height
            }
        }
        return ExactRectangularBSplineSurfacePatch(
            surface: BSplineSurface3D(
                uDegree: 2,
                vDegree: 1,
                uKnots: arc.knots,
                vKnots: [lowerV, lowerV, upperV, upperV],
                controlPoints: rows,
                weights: [arc.weights, arc.weights]
            ),
            uMapping: arc.mapping,
            vMapping: identityMapping(lower: lowerV, upper: upperV)
        )
    }

    private func conicalPatch(
        apex: Point3D,
        axis: Vector3D,
        halfAngle: Double,
        radialU: Vector3D,
        radialV: Vector3D,
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularBSplineSurfacePatch {
        let arc = try circularArc(lower: lowerU, upper: upperU, tolerance: tolerance)
        let sine = sin(halfAngle)
        let cosine = cos(halfAngle)
        let rows = [lowerV, upperV].map { slant in
            arc.controls.map { control in
                apex
                    + axis * (slant * cosine)
                    + radialU * (control.x * slant * sine)
                    + radialV * (control.y * slant * sine)
            }
        }
        return ExactRectangularBSplineSurfacePatch(
            surface: BSplineSurface3D(
                uDegree: 2,
                vDegree: 1,
                uKnots: arc.knots,
                vKnots: [lowerV, lowerV, upperV, upperV],
                controlPoints: rows,
                weights: [arc.weights, arc.weights]
            ),
            uMapping: arc.mapping,
            vMapping: identityMapping(lower: lowerV, upper: upperV)
        )
    }

    private func sphericalPatch(
        center: Point3D,
        radius: Double,
        radialU: Vector3D,
        radialV: Vector3D,
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularBSplineSurfacePatch {
        let longitude = try circularArc(lower: lowerU, upper: upperU, tolerance: tolerance)
        let latitude = try circularArc(lower: lowerV, upper: upperV, tolerance: tolerance)
        let rows = latitude.controls.map { meridian in
            longitude.controls.map { parallel in
                center
                    + radialU * (parallel.x * meridian.x * radius)
                    + radialV * (parallel.y * meridian.x * radius)
                    + Vector3D.unitZ * (meridian.y * radius)
            }
        }
        let weights = latitude.weights.map { latitudeWeight in
            longitude.weights.map { $0 * latitudeWeight }
        }
        return ExactRectangularBSplineSurfacePatch(
            surface: BSplineSurface3D(
                uDegree: 2,
                vDegree: 2,
                uKnots: longitude.knots,
                vKnots: latitude.knots,
                controlPoints: rows,
                weights: weights
            ),
            uMapping: longitude.mapping,
            vMapping: latitude.mapping
        )
    }

    private func toroidalPatch(
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        radialU: Vector3D,
        radialV: Vector3D,
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularBSplineSurfacePatch {
        let major = try circularArc(lower: lowerU, upper: upperU, tolerance: tolerance)
        let minor = try circularArc(lower: lowerV, upper: upperV, tolerance: tolerance)
        let rows = minor.controls.map { minorControl in
            major.controls.map { majorControl in
                let radialDistance = majorRadius + minorRadius * minorControl.x
                return center
                    + radialU * (majorControl.x * radialDistance)
                    + radialV * (majorControl.y * radialDistance)
                    + axis * (minorControl.y * minorRadius)
            }
        }
        let weights = minor.weights.map { minorWeight in
            major.weights.map { $0 * minorWeight }
        }
        return ExactRectangularBSplineSurfacePatch(
            surface: BSplineSurface3D(
                uDegree: 2,
                vDegree: 2,
                uKnots: major.knots,
                vKnots: minor.knots,
                controlPoints: rows,
                weights: weights
            ),
            uMapping: major.mapping,
            vMapping: minor.mapping
        )
    }

    private func circularArc(
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CircularArcData {
        let span = upper - lower
        guard span.isFinite,
              span > tolerance.angle,
              span < 2.0 * Double.pi - tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "An exact rectangular NURBS patch requires an angular span below one period."
            )
        }
        let segmentCount = max(1, Int(ceil(span / (Double.pi * 0.5))))
        let segmentAngle = span / Double(segmentCount)
        var controls: [CircularControl] = []
        var weights: [Double] = []
        var knots = [0.0, 0.0, 0.0]
        for segmentIndex in 0..<segmentCount {
            let start = lower + Double(segmentIndex) * segmentAngle
            let end = start + segmentAngle
            let middle = (start + end) * 0.5
            let middleWeight = cos(segmentAngle * 0.5)
            guard middleWeight > tolerance.relative else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "An exact circular NURBS segment has a singular middle weight."
                )
            }
            let segmentControls = [
                CircularControl(x: cos(start), y: sin(start)),
                CircularControl(
                    x: cos(middle) / middleWeight,
                    y: sin(middle) / middleWeight
                ),
                CircularControl(x: cos(end), y: sin(end)),
            ]
            if segmentIndex == 0 {
                controls.append(contentsOf: segmentControls)
                weights.append(contentsOf: [1.0, middleWeight, 1.0])
            } else {
                controls.append(contentsOf: segmentControls.dropFirst())
                weights.append(contentsOf: [middleWeight, 1.0])
                knots.append(contentsOf: [Double(segmentIndex), Double(segmentIndex)])
            }
        }
        knots.append(contentsOf: [Double(segmentCount), Double(segmentCount), Double(segmentCount)])
        return CircularArcData(
            controls: controls,
            weights: weights,
            knots: knots,
            mapping: .init(
                sourceLower: lower,
                sourceUpper: upper,
                kind: .rationalCircularArc(segmentCount: segmentCount)
            )
        )
    }

    private func identityMapping(
        lower: Double,
        upper: Double
    ) -> ExactRectangularBSplineSurfacePatch.AxisMapping {
        .init(sourceLower: lower, sourceUpper: upper, kind: .identity)
    }

    private func ruledParameterMapping(
        start: Curve3D,
        end: Curve3D,
        lower: Double,
        upper: Double
    ) -> ExactRectangularBSplineSurfacePatch.AxisMapping? {
        guard let startKind = ruledBoundaryMappingKind(
                  start,
                  lower: lower,
                  upper: upper
              ),
              let endKind = ruledBoundaryMappingKind(
                  end,
                  lower: lower,
                  upper: upper
              ),
              startKind == endKind else {
            return nil
        }
        return .init(
            sourceLower: lower,
            sourceUpper: upper,
            kind: startKind
        )
    }

    private func ruledBoundaryMappingKind(
        _ curve: Curve3D,
        lower: Double,
        upper: Double
    ) -> ExactRectangularBSplineSurfacePatch.AxisMapping.Kind? {
        switch curve {
        case .line, .analytic(.line), .analytic(.parabola), .bSpline:
            return .normalized
        case .circle, .analytic(.circle), .analytic(.arc), .analytic(.ellipse):
            return .normalizedRationalCircularArc(
                segmentCount: max(
                    1,
                    Int(ceil((upper - lower) / (Double.pi * 0.5)))
                )
            )
        case .analytic(.hyperbola):
            return .normalizedRationalHyperbola(
                spanCount: max(1, Int(ceil(upper - lower)))
            )
        case let .rigidImage(image):
            return ruledBoundaryMappingKind(
                image.source,
                lower: lower,
                upper: upper
            )
        case let .affineImage(image):
            return ruledBoundaryMappingKind(
                image.source,
                lower: lower,
                upper: upper
            )
        case .analytic(.planeTorus), .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }

    private func legacyCylinderBasis(
        axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let normalizedAxis = try axis.normalized(tolerance: tolerance.distance)
        let helper = abs(normalizedAxis.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normalizedAxis).normalized(tolerance: tolerance.distance)
        return (u, normalizedAxis.cross(u))
    }

    private struct CircularControl {
        let x: Double
        let y: Double
    }

    private struct CircularArcData {
        let controls: [CircularControl]
        let weights: [Double]
        let knots: [Double]
        let mapping: ExactRectangularBSplineSurfacePatch.AxisMapping
    }
}
