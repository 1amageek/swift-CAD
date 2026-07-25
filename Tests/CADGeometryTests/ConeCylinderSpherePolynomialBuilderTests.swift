import CADCore
import Foundation
@testable import CADGeometry
import Testing

@Suite("Cone-cylinder sphere polynomial builder")
struct ConeCylinderSpherePolynomialBuilderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func polynomialMatchesQuadraticResultant() throws {
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 0.3, y: -0.4, z: 0.2),
            axis: try Vector3D(
                x: 0.2,
                y: -0.3,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            halfAngle: 0.55
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: -0.7, y: 0.6, z: -0.2),
            axis: try Vector3D(
                x: -0.1,
                y: 1.0,
                z: 0.25
            ).normalized(tolerance: tolerance.distance),
            radius: 1.3
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.8, y: -1.1, z: 0.9),
            radius: 1.7
        ))
        let context = try ConeCylinderSphereIntersectionContext(
            coneSurface: cone,
            cylinderSurface: cylinder,
            sphereSurface: sphere,
            tolerance: tolerance
        )
        let polynomial =
            DefaultConeCylinderSpherePolynomialBuilder().polynomial(
                context: context
            )
        let coefficients = polynomial.coefficients

        #expect(coefficients.count <= 9)
        #expect(polynomial.forwardErrorScale.isFinite)
        #expect(polynomial.forwardErrorScale > 0.0)
        for angle in [-2.4, -1.1, -0.2, 0.0, 0.7, 1.9, 2.8] {
            let coneHalfLinear = context.coneHalfLinear.value(at: angle)
            let coneBaseQuadratic =
                context.coneBaseQuadratic.value(at: angle)
            let sphereHalfLinear =
                context.sphereHalfLinear.value(at: angle)
            let sphereBaseQuadratic =
                context.sphereBaseQuadratic.value(at: angle)
            let heightLinear = 2.0 * (
                coneHalfLinear
                    - context.generatorQuadratic * sphereHalfLinear
            )
            let constant = coneBaseQuadratic
                - context.generatorQuadratic * sphereBaseQuadratic
            let resultant = constant * constant
                - 2.0 * sphereHalfLinear * constant * heightLinear
                + sphereBaseQuadratic * heightLinear * heightLinear
            let halfAngleTangent = tan(angle * 0.5)
            let denominator = 1.0
                + halfAngleTangent * halfAngleTangent
            let expected = resultant * pow(denominator, 4.0)
            let actual = evaluate(
                coefficients,
                at: halfAngleTangent
            )
            let scale = max(
                abs(expected),
                coefficients.reduce(0.0) { $0 + abs($1) },
                1.0
            )
            #expect(
                abs(actual - expected)
                    <= Double.ulpOfOne * scale * 16_384.0
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func zeroResultantSeparatesContinuousAndEmptyBranches() throws {
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let intersector = DefaultConeCylinderSphereIntersector()

        for halfAngle in [
            atan(0.5),
            Double.pi * 0.5 - 1.0e-2,
        ] {
            let cone = Surface3D.analytic(.cone(
                apex: .origin,
                axis: .unitZ,
                halfAngle: halfAngle
            ))
            let branchHeight = 1.0 / tan(halfAngle)
            let sphere = Surface3D.analytic(.sphere(
                center: Point3D(
                    x: 0.0,
                    y: 0.0,
                    z: branchHeight
                ),
                radius: 1.0
            ))
            let context = try ConeCylinderSphereIntersectionContext(
                coneSurface: cone,
                cylinderSurface: cylinder,
                sphereSurface: sphere,
                tolerance: tolerance
            )
            let polynomial =
                DefaultConeCylinderSpherePolynomialBuilder().polynomial(
                    context: context
                )
            let coefficientScale =
                polynomial.coefficients.map(abs).max() ?? 0.0
            let zeroThreshold = max(
                polynomial.forwardErrorScale,
                pow(context.characteristicLength, 4.0)
            ) * Double.ulpOfOne * 65_536.0
            #expect(coefficientScale <= zeroThreshold)
            let overlapping = try certifiedCurve(
                cone: cone,
                cylinder: cylinder,
                componentKind: .negativeFullBranch
            )
            let disjoint = try certifiedCurve(
                cone: cone,
                cylinder: cylinder,
                componentKind: .positiveFullBranch
            )

            do {
                _ = try intersector.intersections(
                    curve: overlapping,
                    sphereSurface: sphere,
                    options: .init(),
                    tolerance: tolerance
                )
                Issue.record(
                    "A sphere containing a complete certified branch must fail as non-discrete."
                )
            } catch let error as KernelError {
                #expect(error.phase == .geometry)
                #expect(error.code == .nonDiscreteIntersection)
                #expect(error.tolerance == tolerance)
            }

            let empty = try intersector.intersections(
                curve: disjoint,
                sphereSurface: sphere,
                options: .init(),
                tolerance: tolerance
            )
            #expect(empty.isEmpty)
        }
    }

    private func certifiedCurve(
        cone: Surface3D,
        cylinder: Surface3D,
        componentKind:
            CertifiedConeCylinderIntersectionCurve.ComponentKind
    ) throws -> CertifiedConeCylinderIntersectionCurve {
        try CertifiedConeCylinderIntersectionCurve(
            coneSurface: cone,
            cylinderSurface: cylinder,
            componentKind: componentKind,
            lowerAngle: 0.0,
            upperAngle: 2.0 * Double.pi,
            tolerance: tolerance
        )
    }

    private func evaluate(
        _ coefficients: [Double],
        at value: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) {
            $0 * value + $1
        }
    }
}
