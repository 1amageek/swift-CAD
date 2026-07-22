import CADCore
import CADGeometry
import Foundation
import Testing

struct GeometryKernelTests {
    @Test
    func boundingBoxContainsAndUnions() throws {
        let first = try BoundingBox3D(
            minimum: Point3D(x: 0.0, y: 0.0, z: 0.0),
            maximum: Point3D(x: 1.0, y: 1.0, z: 1.0)
        )
        let second = try BoundingBox3D(
            minimum: Point3D(x: 1.0, y: -1.0, z: 0.5),
            maximum: Point3D(x: 2.0, y: 0.0, z: 1.5)
        )
        let union = try first.union(second)
        #expect(first.contains(Point3D(x: 0.5, y: 0.5, z: 0.5), tolerance: 0.0))
        #expect(first.intersects(second, tolerance: 0.0))
        #expect(union.minimum == Point3D(x: 0.0, y: -1.0, z: 0.0))
        #expect(union.maximum == Point3D(x: 2.0, y: 1.0, z: 1.5))
    }

    @Test
    func uncertainOrientationFailsClosed() throws {
        let a = Point3D(x: 0.0, y: 0.0, z: 0.0)
        let b = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let c = Point3D(x: 0.0, y: 1.0, z: 0.0)
        let d = Point3D(x: 0.0, y: 0.0, z: 1.0)
        let sign = try RobustPredicates.orientation3D(
            a,
            b,
            c,
            relativeTo: d,
            determinantTolerance: 1.0e-12
        )
        #expect(sign == .negative)
    }

    @Test
    func adaptiveOrientationResolvesRoundoffBoundCase() throws {
        let epsilon = Double.ulpOfOne
        let sign = try RobustPredicates.orientation3D(
            Point3D(x: 1.0, y: 1.0, z: 1.0),
            Point3D(x: 1.0 + epsilon, y: 1.0, z: 1.0),
            Point3D(x: 1.0, y: 1.0 + epsilon, z: 1.0),
            relativeTo: .origin,
            determinantTolerance: 0.0
        )

        #expect(sign == .positive)
    }

    @Test
    func sphereDifferentialGeometryIsOrthonormal() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let differential = try sphere.differentialGeometry(
            atU: 0.4,
            v: 0.3,
            tolerance: .standard
        )
        #expect(abs(differential.normal.length - 1.0) < 1.0e-12)
        #expect(abs((differential.position - Point3D.origin).length - 2.0) < 1.0e-12)
        let frame = try sphere.uvnFrame(
            atU: 0.4,
            v: 0.3,
            tolerance: .standard
        )
        #expect(abs(frame.u.dot(frame.v)) < 1.0e-12)
        #expect(abs(frame.u.cross(frame.v).dot(frame.normal) - 1.0) < 1.0e-12)
        #expect(abs(differential.meanCurvature + 0.5) < 1.0e-12)
    }

    @Test
    func ellipseHasExactEndpointAndCurvature() throws {
        let ellipse = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 4.0,
            minorRadius: 2.0
        ))
        let differential = try ellipse.differentialGeometry(
            at: 0.0,
            tolerance: .standard
        )
        #expect(differential.position == Point3D(x: 4.0, y: 0.0, z: 0.0))
        #expect(differential.curvature.isFinite)
    }

    @Test
    func polynomialRootIsolationPreservesRepeatedQuarticRoot() throws {
        let solver = try RealPolynomialRootSolver(
            rootTolerance: 1.0e-12,
            residualTolerance: 1.0e-12
        )
        let roots = try solver.realRoots(coefficients: [1.0, -4.0, 6.0, -4.0, 1.0])

        guard roots.count == 1 else {
            Issue.record("Expected one repeated real root, received \(roots).")
            return
        }
        #expect(abs(roots[0] - 1.0) <= 1.0e-9)
    }

    @Test
    func polynomialRootIsolationFindsFourDistinctQuarticRoots() throws {
        let solver = try RealPolynomialRootSolver(
            rootTolerance: 1.0e-12,
            residualTolerance: 1.0e-12
        )
        let roots = try solver.realRoots(coefficients: [4.0, 0.0, -5.0, 0.0, 1.0])

        guard roots.count == 4 else {
            Issue.record("Expected four distinct real roots, received \(roots).")
            return
        }
        #expect(abs(roots[0] + 2.0) <= 1.0e-9)
        #expect(abs(roots[1] + 1.0) <= 1.0e-9)
        #expect(abs(roots[2] - 1.0) <= 1.0e-9)
        #expect(abs(roots[3] - 2.0) <= 1.0e-9)
    }

    @Test
    func polynomialRootIsolationPreservesSymmetricRootsAcrossZero() throws {
        let solver = try RealPolynomialRootSolver(
            rootTolerance: 1.0e-12,
            residualTolerance: 1.0e-12
        )
        let roots = try solver.realRoots(
            coefficients: [1.75, 0.0, -12.5, 0.0, 1.75]
        )

        #expect(roots.count == 4)
        #expect(abs(roots[0] + sqrt(7.0)) <= 1.0e-9)
        #expect(abs(roots[1] + 1.0 / sqrt(7.0)) <= 1.0e-9)
        #expect(abs(roots[2] - 1.0 / sqrt(7.0)) <= 1.0e-9)
        #expect(abs(roots[3] - sqrt(7.0)) <= 1.0e-9)
    }

    @Test
    func polynomialRootIsolationPreservesRepeatedZeroRoot() throws {
        let solver = try RealPolynomialRootSolver(
            rootTolerance: 1.0e-12,
            residualTolerance: 1.0e-12
        )
        let roots = try solver.realRoots(
            coefficients: [0.0, 0.0, 1.0, 0.0, 1.0]
        )

        #expect(roots.count == 1)
        #expect(abs(roots[0]) <= 1.0e-12)
    }

    @Test
    func rationalBezierCurveEvaluatesHomogeneousDerivatives() throws {
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
            ]
        )
        let differential = try curve.differentialGeometry(
            at: 0.5,
            tolerance: .standard
        )
        #expect(abs(differential.position.x - 1.0) < 1.0e-12)
        #expect(abs(differential.position.y - 0.5) < 1.0e-12)
        #expect(differential.firstDerivative.length > 0.0)
    }

    @Test
    func rationalSurfaceUsesUnifiedEvaluationProjectionAndTrimPath() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
        let differential = try surface.differentialGeometry(
            atU: 0.25,
            v: 0.75,
            tolerance: .standard
        )
        #expect(abs(differential.position.x - 0.25) < 1.0e-12)
        #expect(abs(differential.position.y - 0.75) < 1.0e-12)
        #expect(differential.normal == .unitZ)

        let projection = try Surface3D.bSpline(surface).parameterProjection(
            of: differential.position,
            tolerance: .standard
        )
        #expect(abs(projection.u - 0.25) <= ModelingTolerance.standard.distance)
        #expect(abs(projection.v - 0.75) <= ModelingTolerance.standard.distance)

        let trimmed = try surface.trimmed(
            uFrom: 0.2,
            uTo: 0.8,
            vFrom: 0.3,
            vTo: 0.9,
            tolerance: .standard
        )
        let trimmedPoint = try trimmed.point(
            u: 0.25,
            v: 0.75,
            tolerance: .standard
        )
        #expect(trimmedPoint.isApproximatelyEqual(
            to: differential.position,
            tolerance: ModelingTolerance.standard.distance
        ))
    }

    @Test
    func rationalSurfaceNormalRejectsLocallySingularParameter() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 2,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.5, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 0.0, z: 1.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ],
            ]
        )
        try surface.validate(tolerance: .standard)

        do {
            _ = try surface.normal(u: 0.0, v: 0.0, tolerance: .standard)
            Issue.record("A singular surface parameter must not borrow a normal from a nearby point.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.residual.map { $0 <= ModelingTolerance.standard.distance } == true)
            #expect(error.tolerance == .standard)
        }

        let nearbyNormal = try surface.normal(u: 0.1, v: 0.1, tolerance: .standard)
        #expect(abs(nearbyNormal.length - 1.0) <= ModelingTolerance.standard.distance)
    }

    @Test
    func rationalQuarterCylinderProvidesExactCurvatureAndUVNFrame() throws {
        let diagonalWeight = sqrt(0.5)
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                ],
                [
                    Point3D(x: 1.0, y: 0.0, z: 1.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                    Point3D(x: 0.0, y: 1.0, z: 1.0),
                ],
            ],
            weights: [
                [1.0, diagonalWeight, 1.0],
                [1.0, diagonalWeight, 1.0],
            ]
        )
        let geometry = try surface.differentialGeometry(
            atU: 0.5,
            v: 0.4,
            tolerance: .standard
        )
        let expectedCoordinate = sqrt(0.5)
        #expect(abs(geometry.position.x - expectedCoordinate) <= 1.0e-12)
        #expect(abs(geometry.position.y - expectedCoordinate) <= 1.0e-12)
        #expect(abs(geometry.position.z - 0.4) <= 1.0e-12)
        #expect(abs(geometry.normal.x - expectedCoordinate) <= 1.0e-12)
        #expect(abs(geometry.normal.y - expectedCoordinate) <= 1.0e-12)
        #expect(abs(geometry.gaussianCurvature) <= 1.0e-12)
        #expect(abs(geometry.meanCurvature + 0.5) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalCurvature + 1.0) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalCurvature) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.dot(geometry.normal)) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.dot(geometry.normal)) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.dot(geometry.maximumPrincipalDirection)) <= 1.0e-12)

        let frame = try Surface3D.bSpline(surface).uvnFrame(
            atU: 0.5,
            v: 0.4,
            tolerance: .standard
        )
        #expect(abs(frame.u.length - 1.0) <= 1.0e-12)
        #expect(abs(frame.v.length - 1.0) <= 1.0e-12)
        #expect(abs(frame.normal.length - 1.0) <= 1.0e-12)
        #expect(abs(frame.u.dot(frame.v)) <= 1.0e-12)
        #expect(abs(frame.u.cross(frame.v).dot(frame.normal) - 1.0) <= 1.0e-12)
    }

    @Test
    func rationalSurfaceResolvesScaleQualifiedPrincipalDirectionsBelowDistanceTolerance() throws {
        let firstCurvatureCoefficient = 1.0e-7
        let secondCurvatureCoefficient = 4.0e-7
        let coordinates = [0.0, 0.5, 1.0]
        let squaredCoefficients = [0.0, 0.0, 1.0]
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: coordinates.indices.map { vIndex in
                coordinates.indices.map { uIndex in
                    Point3D(
                        x: coordinates[uIndex],
                        y: coordinates[vIndex],
                        z: firstCurvatureCoefficient * squaredCoefficients[uIndex]
                            + secondCurvatureCoefficient * squaredCoefficients[vIndex]
                    )
                }
            }
        )

        let geometry = try surface.differentialGeometry(
            atU: 0.5,
            v: 0.5,
            tolerance: .standard
        )

        #expect(
            geometry.maximumPrincipalCurvature - geometry.minimumPrincipalCurvature
                > ModelingTolerance.standard.relative
        )
        #expect(abs(geometry.minimumPrincipalDirection.length - 1.0) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.length - 1.0) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.dot(geometry.normal)) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.dot(geometry.normal)) <= 1.0e-12)
        #expect(
            abs(
                geometry.minimumPrincipalDirection.dot(
                    geometry.maximumPrincipalDirection
                )
            ) <= 1.0e-12
        )
    }

    @Test
    func rationalSurfaceDifferentialGeometryIsScaleInvariantAboveTolerance() throws {
        let extent = 1.0e-6
        let scaleTolerance = ModelingTolerance(
            distance: 1.0e-12,
            angle: 1.0e-12,
            relative: 1.0e-12
        )
        let surface = BSplineSurface3D.bilinearPatch(
            bottomLeft: .origin,
            bottomRight: Point3D(x: extent, y: 0.0, z: 0.0),
            topRight: Point3D(x: extent, y: extent, z: 0.0),
            topLeft: Point3D(x: 0.0, y: extent, z: 0.0)
        )

        let geometry = try surface.differentialGeometry(
            atU: 0.37,
            v: 0.61,
            tolerance: scaleTolerance
        )
        let frame = try Surface3D.bSpline(surface).uvnFrame(
            atU: 0.37,
            v: 0.61,
            tolerance: scaleTolerance
        )

        #expect(abs(geometry.normal.z - 1.0) <= scaleTolerance.angle)
        #expect(abs(geometry.meanCurvature) <= scaleTolerance.relative)
        #expect(abs(geometry.gaussianCurvature) <= scaleTolerance.relative)
        #expect(abs(frame.u.length - 1.0) <= scaleTolerance.relative)
        #expect(abs(frame.v.length - 1.0) <= scaleTolerance.relative)
        #expect(abs(frame.u.dot(frame.v)) <= scaleTolerance.angle)
    }

    @Test
    func rationalSurfaceIsoparametricCurvesPreserveLocusAndDifferentials() throws {
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.3),
                    Point3D(x: 2.0, y: 0.0, z: 0.1),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.2),
                    Point3D(x: 1.0, y: 1.0, z: 0.7),
                    Point3D(x: 2.0, y: 1.0, z: -0.1),
                ],
                [
                    Point3D(x: 0.0, y: 2.0, z: -0.2),
                    Point3D(x: 1.0, y: 2.0, z: 0.4),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 0.8, 1.2],
                [1.1, 0.7, 1.3],
                [0.9, 1.4, 1.0],
            ]
        )
        let fixedU = 0.31
        let fixedV = 0.67
        let uCurve = try surface.uIsoparametricCurve(atV: fixedV, tolerance: .standard)
        let vCurve = try surface.vIsoparametricCurve(atU: fixedU, tolerance: .standard)

        for parameter in [0.0, 0.19, 0.53, 0.86, 1.0] {
            let expectedU = try surface.differentialGeometry(
                atU: parameter,
                v: fixedV,
                tolerance: .standard
            )
            let actualU = try uCurve.differentialGeometry(at: parameter, tolerance: .standard)
            #expect((actualU.position - expectedU.position).length <= ModelingTolerance.standard.distance)
            #expect((actualU.firstDerivative - expectedU.tangentU).length <= ModelingTolerance.standard.distance)

            let expectedV = try surface.differentialGeometry(
                atU: fixedU,
                v: parameter,
                tolerance: .standard
            )
            let actualV = try vCurve.differentialGeometry(at: parameter, tolerance: .standard)
            #expect((actualV.position - expectedV.position).length <= ModelingTolerance.standard.distance)
            #expect((actualV.firstDerivative - expectedV.tangentV).length <= ModelingTolerance.standard.distance)
        }
    }

    @Test
    func rationalSurfaceDecodingRequiresCurrentStrictSchema() throws {
        let surface = BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )
        let encoded = try JSONEncoder().encode(surface)
        let decoded = try JSONDecoder().decode(BSplineSurface3D.self, from: encoded)
        #expect(decoded == surface)

        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("The encoded rational surface must be a keyed JSON object.")
            return
        }
        object.removeValue(forKey: "weights")
        let missingWeights = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(BSplineSurface3D.self, from: missingWeights)
            Issue.record("The current rational surface schema must require explicit weights.")
        } catch DecodingError.keyNotFound {
        }

        object["weights"] = surface.weights
        object["legacyDegreeU"] = surface.uDegree
        let unknownKey = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(BSplineSurface3D.self, from: unknownKey)
            Issue.record("The current rational surface schema must reject unknown legacy keys.")
        } catch DecodingError.dataCorrupted {
        }
    }

    @Test
    func rationalCurveDecodingRequiresCurrentStrictSchema() throws {
        let curve3D = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.5),
                Point3D(x: 2.0, y: 0.0, z: 1.0),
            ],
            weights: [1.0, 0.75, 1.25]
        )
        let encoded3D = try JSONEncoder().encode(curve3D)
        #expect(try JSONDecoder().decode(BSplineCurve3D.self, from: encoded3D) == curve3D)
        guard var object = try JSONSerialization.jsonObject(with: encoded3D) as? [String: Any] else {
            Issue.record("The encoded rational curve must be a keyed JSON object.")
            return
        }
        object.removeValue(forKey: "weights")
        let missingWeights = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(BSplineCurve3D.self, from: missingWeights)
            Issue.record("The current rational curve schema must require explicit weights.")
        } catch DecodingError.keyNotFound {
        }

        object["weights"] = curve3D.weights
        object["legacyOrder"] = curve3D.order
        let unknownKey = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(BSplineCurve3D.self, from: unknownKey)
            Issue.record("The current rational curve schema must reject unknown legacy keys.")
        } catch DecodingError.dataCorrupted {
        }

        let curve2D = BSplineCurve2D(
            degree: curve3D.degree,
            knots: curve3D.knots,
            controlPoints: curve3D.controlPoints.map { Point2D(x: $0.x, y: $0.y) },
            weights: curve3D.weights
        )
        let encoded2D = try JSONEncoder().encode(curve2D)
        #expect(try JSONDecoder().decode(BSplineCurve2D.self, from: encoded2D) == curve2D)
    }
}
