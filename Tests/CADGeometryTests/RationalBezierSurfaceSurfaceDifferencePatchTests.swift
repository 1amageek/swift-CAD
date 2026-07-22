import CADCore
@testable import CADGeometry
import Testing

@Suite("Rational Bezier Surface-Surface Difference Patch")
struct RationalBezierSurfaceSurfaceDifferencePatchTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func homogeneousDifferenceExcludesSeparatedRationalSurfaces() throws {
        let first = horizontalPatch(height: 0.0)
        let second = horizontalPatch(height: 1.0)

        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(difference.excludesZero())
        #expect(difference.excludesZero(tolerance: tolerance))
    }

    @Test
    func toleranceBandPreventsFalseExclusionOfNearContact() throws {
        let first = horizontalPatch(height: 0.0)
        let second = horizontalPatch(height: tolerance.distance * 0.5)
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(difference.excludesZero())
        #expect(difference.excludesZero(tolerance: tolerance) == false)
    }

    @Test
    func subdivisionPreservesIntersectingLocusAndParameterQuadrantOrder() throws {
        let first = horizontalPatch(height: 0.0)
        let second = RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.5, y: 0.0, z: -1.0),
                    Point3D(x: 0.5, y: 1.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: 0.0, z: 1.0),
                    Point3D(x: 0.5, y: 1.0, z: 1.0),
                ],
            ],
            weights: [[1.0, 0.9], [1.1, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: first,
            second: second,
            tolerance: tolerance
        )
        #expect(difference.excludesZero() == false)

        let children = difference.subdividedFirstSurface()

        #expect(children.count == 4)
        #expect(children[0].firstULower == 0.0)
        #expect(children[0].firstUUpper == 0.5)
        #expect(children[0].firstVLower == 0.0)
        #expect(children[0].firstVUpper == 0.5)
        #expect(children[1].firstULower == 0.5)
        #expect(children[1].firstUUpper == 1.0)
        #expect(children[1].firstVLower == 0.0)
        #expect(children[1].firstVUpper == 0.5)
        #expect(children[2].firstULower == 0.0)
        #expect(children[2].firstUUpper == 0.5)
        #expect(children[2].firstVLower == 0.5)
        #expect(children[2].firstVUpper == 1.0)
        #expect(children[3].firstULower == 0.5)
        #expect(children[3].firstUUpper == 1.0)
        #expect(children[3].firstVLower == 0.5)
        #expect(children[3].firstVUpper == 1.0)
        #expect(children.contains { $0.excludesZero() == false })
    }

    @Test
    func intervalJacobianCertifiesARegularTransverseIntersection() throws {
        let first = unitHorizontalPatch()
        let second = RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.5, y: 0.0, z: -1.0),
                    Point3D(x: 0.5, y: 1.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: 0.0, z: 1.0),
                    Point3D(x: 0.5, y: 1.0, z: 1.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: first,
            second: second,
            tolerance: tolerance
        )

        switch difference.rankThreeCertificate() {
        case let .regular(freeParameterIndex):
            #expect(freeParameterIndex == 1 || freeParameterIndex == 2)
        case .unresolved:
            Issue.record("A transverse affine intersection must have a rank-three certificate.")
        }
    }

    @Test
    func boundaryAlignedAffineGaugeHasClosedKrawczykGraphCertificate() throws {
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: verticalPatch(yLower: 0.0, yUpper: 1.0),
            tolerance: tolerance
        )

        switch difference.gaugeRootCertificate() {
        case let .fullGraph(freeParameterIndex):
            #expect(freeParameterIndex == 1 || freeParameterIndex == 2)
        case .uniqueMidpointRoot, .cellEmpty, .midpointSliceEmpty, .unresolved, .rankUnresolved:
            Issue.record("A boundary-aligned affine gauge must certify one closed contraction graph.")
        }
    }

    @Test
    func parameterizedKrawczykCertifiesACompleteRegularGraph() throws {
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: verticalPatch(yLower: -1.0, yUpper: 2.0),
            tolerance: tolerance
        )

        #expect(difference.gaugeRootCertificate() == .fullGraph(freeParameterIndex: 1))
    }

    @Test
    func boundaryKrawczykFindsExactlyTwoEndpointsOfACompleteRegularGraph() throws {
        let forward = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: verticalPatch(yLower: -1.0, yUpper: 2.0),
            tolerance: tolerance
        )
        let reverse = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: verticalPatch(yLower: -1.0, yUpper: 2.0),
            second: unitHorizontalPatch(),
            tolerance: tolerance
        )

        for difference in [forward, reverse] {
            let certificates = boundaryCertificates(difference)
            #expect(certificates.filter { $0 == .unique }.count == 2)
            #expect(certificates.filter { $0 == .empty }.count == 6)
            #expect(certificates.contains(.unresolved) == false)
        }
    }

    @Test
    func boundaryKrawczykCertifiesCornerRootsByClosedContraction() throws {
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: verticalPatch(yLower: 0.0, yUpper: 1.0),
            tolerance: tolerance
        )

        #expect(
            difference.boundaryRootCertificate(
                fixedParameterIndex: 1,
                side: .lower,
                tolerance: tolerance
            ) == .unique
        )
        #expect(
            difference.boundaryRootCertificate(
                fixedParameterIndex: 1,
                side: .upper,
                tolerance: tolerance
            ) == .unique
        )
    }

    @Test
    func partialRegularGraphRetainsOnlyItsMidpointCertificate() throws {
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: verticalPatch(yLower: 0.4, yUpper: 1.6),
            tolerance: tolerance
        )

        #expect(
            difference.gaugeRootCertificate()
                == .uniqueMidpointRoot(freeParameterIndex: 1)
        )
    }

    @Test
    func emptyMidpointGaugeDoesNotExcludeARegularFourDimensionalCell() throws {
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: verticalPatch(yLower: -1.0, yUpper: 0.2),
            tolerance: tolerance
        )

        #expect(difference.excludesZero(tolerance: tolerance) == false)
        #expect(
            difference.gaugeRootCertificate()
                == .midpointSliceEmpty(freeParameterIndex: 1)
        )
    }

    @Test
    func parameterizedKrawczykCertifiesARegularCellAsEmpty() throws {
        let second = RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: -2.459652124224179, y: -0.35163296453165693, z: 1.6254581017068912),
                    Point3D(x: -2.2476824774748887, y: 0.3915847511658801, z: -2.241890362340242),
                ],
                [
                    Point3D(x: -2.36707580081365, y: -0.7680604868663097, z: -0.29430778275744074),
                    Point3D(x: 0.6152102024844814, y: -0.6283575602505174, z: -2.542556565900744),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: unitHorizontalPatch(),
            second: second,
            tolerance: tolerance
        )

        #expect(difference.gaugeRootCertificate() == .cellEmpty(freeParameterIndex: 3))
    }

    @Test
    func intervalJacobianDoesNotCertifyAQuadraticTangencyAsRegular() throws {
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: quadraticHorizontalPatch(),
            second: tangentParaboloidPatch(),
            tolerance: tolerance
        )

        #expect(difference.rankThreeCertificate() == .unresolved)
        #expect(difference.gaugeRootCertificate() == .rankUnresolved)
    }

    private func horizontalPatch(height: Double) -> RationalBezierSurfacePatch3D {
        RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: height),
                    Point3D(x: 1.0, y: 0.0, z: height),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: height),
                    Point3D(x: 1.0, y: 1.0, z: height),
                ],
            ],
            weights: [[1.0, 0.8], [1.2, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
    }

    private func unitHorizontalPatch() -> RationalBezierSurfacePatch3D {
        RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
    }

    private func verticalPatch(
        yLower: Double,
        yUpper: Double
    ) -> RationalBezierSurfacePatch3D {
        RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.5, y: yLower, z: -1.0),
                    Point3D(x: 0.5, y: yUpper, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: yLower, z: 1.0),
                    Point3D(x: 0.5, y: yUpper, z: 1.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
    }

    private func boundaryCertificates(
        _ difference: RationalBezierSurfaceSurfaceDifferencePatch
    ) -> [RationalBezierSurfaceSurfaceDifferencePatch.BoundaryRootCertificate] {
        (0..<4).flatMap { parameterIndex in
            RationalBezierSurfaceSurfaceDifferencePatch.BoundarySide.allCases.map { side in
                difference.boundaryRootCertificate(
                    fixedParameterIndex: parameterIndex,
                    side: side,
                    tolerance: tolerance
                )
            }
        }
    }

    private func quadraticHorizontalPatch() -> RationalBezierSurfacePatch3D {
        let coordinates = [-1.0, 0.0, 1.0]
        return RationalBezierSurfacePatch3D(
            controlPoints: coordinates.map { y in
                coordinates.map { x in Point3D(x: x, y: y, z: 0.0) }
            },
            weights: Array(repeating: Array(repeating: 1.0, count: 3), count: 3),
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
    }

    private func tangentParaboloidPatch() -> RationalBezierSurfacePatch3D {
        let coordinates = [-1.0, 0.0, 1.0]
        let quadraticCoefficients = [1.0, -1.0, 1.0]
        return RationalBezierSurfacePatch3D(
            controlPoints: coordinates.indices.map { vIndex in
                coordinates.indices.map { uIndex in
                    Point3D(
                        x: coordinates[uIndex],
                        y: coordinates[vIndex],
                        z: quadraticCoefficients[uIndex] + quadraticCoefficients[vIndex]
                    )
                }
            },
            weights: Array(repeating: Array(repeating: 1.0, count: 3), count: 3),
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
    }
}
