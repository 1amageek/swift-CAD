import CADCore
import CADGeometry
@testable import CADTopology
import Foundation
import Testing

@Suite("Certified B-spline surface Bezier extraction")
struct CertifiedBSplineSurfaceBezierExtractorTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func rationalRepeatedKnotPatchesContainOriginalHomogeneousJets() throws {
        let surface = rationalRepeatedKnotSurface()
        let patches = try #require(
            try CertifiedBSplineSurfaceBezierExtractor().patches(
                surface: surface,
                tolerance: tolerance
            )
        )
        #expect(patches.count == 4)

        for patch in patches {
            let usesRightUSide = patch.uLower >= 0.5
            let usesRightVSide = patch.vLower >= 0.5
            for (uFraction, vFraction) in [
                (0.0, 0.0),
                (1.0, 0.0),
                (0.0, 1.0),
                (1.0, 1.0)
            ] {
                let u = patch.uLower + (patch.uUpper - patch.uLower) * uFraction
                let v = patch.vLower + (patch.vUpper - patch.vLower) * vFraction
                let expected = literalHomogeneousJet(
                    surface,
                    u: u,
                    v: v,
                    usesRightUSide: usesRightUSide,
                    usesRightVSide: usesRightVSide
                )
                let actual = emittedHomogeneousJet(
                    patch,
                    uFraction: uFraction,
                    vFraction: vFraction
                )
                expectContains(actual, expected)
            }

            let uFraction = 0.5
            let vFraction = 0.5
            let u = patch.uLower + (patch.uUpper - patch.uLower) * uFraction
            let v = patch.vLower + (patch.vUpper - patch.vLower) * vFraction
            let expected = literalHomogeneousJet(
                surface,
                u: u,
                v: v,
                usesRightUSide: usesRightUSide,
                usesRightVSide: usesRightVSide
            )
            let actual = emittedHomogeneousJet(
                patch,
                uFraction: uFraction,
                vFraction: vFraction
            )
            for index in 0..<6 {
                expectContains(actual.x[index], expected.x[index])
                expectContains(actual.y[index], expected.y[index])
                expectContains(actual.z[index], expected.z[index])
                expectContains(actual.weight[index], expected.weight[index])
            }
            let hasPositiveWeights = patch.controls
                .flatMap { $0 }
                .allSatisfy { $0.isFiniteAndPositiveWeight }
            #expect(hasPositiveWeights)
        }
    }

    @Test
    func manySpanPolynomialSurfaceFitsTheUnchangedControlAllowance() throws {
        let controlPointCount = 535
        var uKnots = Array(repeating: 0.0, count: 4)
        for index in 1...177 {
            uKnots.append(contentsOf: repeatElement(Double(index) / 178.0, count: 3))
        }
        uKnots.append(contentsOf: repeatElement(1.0, count: 4))
        let surface = BSplineSurface3D(
            uDegree: 3,
            vDegree: 1,
            uKnots: uKnots,
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: (0..<2).map { vIndex in
                (0..<controlPointCount).map { uIndex in
                    let u = Double(uIndex) / Double(controlPointCount - 1)
                    return Point3D(
                        x: u,
                        y: Double(vIndex),
                        z: u * u * (1.0 + Double(vIndex))
                    )
                }
            }
        )
        let patches = try #require(
            try CertifiedBSplineSurfaceBezierExtractor().patches(
                surface: surface,
                tolerance: tolerance
            )
        )
        #expect(patches.count == 178)
        #expect(patches.allSatisfy {
            $0.controls.flatMap({ $0 }).allSatisfy(\.isFiniteAndPositiveWeight)
        })
    }

    @Test
    func lowBudgetAndCheckedOverflowRefuseWithTypedResourceFailure() throws {
        let surface = rationalRepeatedKnotSurface()
        for allowance in [0, Int.min] {
            do {
                _ = try CertifiedBSplineSurfaceBezierExtractor(
                    maximumControlOperations: allowance
                ).patches(surface: surface, tolerance: tolerance)
                Issue.record("Surface extraction unexpectedly succeeded under a resource limit.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            } catch {
                Issue.record("Unexpected resource-limit error: \(error)")
            }
        }
    }

    @Test
    func cancellationIsPropagatedBeforeSurfaceTraversal() async {
        let surface = rationalRepeatedKnotSurface()
        let tolerance = self.tolerance
        let task = Task { () throws -> Void in
            _ = try CertifiedBSplineSurfaceBezierExtractor().patches(
                surface: surface,
                tolerance: tolerance
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled surface extraction returned a success value.")
        } catch is CancellationError {
            // Expected: extraction checks cancellation before source traversal.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    private struct BasisJet {
        let value: Double
        let first: Double
        let second: Double
    }

    private struct HomogeneousJet {
        var x: [Double]
        var y: [Double]
        var z: [Double]
        var weight: [Double]

        init() {
            x = Array(repeating: 0.0, count: 6)
            y = Array(repeating: 0.0, count: 6)
            z = Array(repeating: 0.0, count: 6)
            weight = Array(repeating: 0.0, count: 6)
        }
    }

    private struct HomogeneousBoundsJet {
        var x: [CertifiedHomogeneousBezierSurfacePatch.ScalarBounds]
        var y: [CertifiedHomogeneousBezierSurfacePatch.ScalarBounds]
        var z: [CertifiedHomogeneousBezierSurfacePatch.ScalarBounds]
        var weight: [CertifiedHomogeneousBezierSurfacePatch.ScalarBounds]

        init() {
            let zero = CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(0.0)
            x = Array(repeating: zero, count: 6)
            y = Array(repeating: zero, count: 6)
            z = Array(repeating: zero, count: 6)
            weight = Array(repeating: zero, count: 6)
        }
    }

    private func rationalRepeatedKnotSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
            vKnots: [0, 0, 0, 0.5, 1, 1, 1],
            controlPoints: (0..<4).map { vIndex in
                (0..<5).map { uIndex in
                    let u = Double(uIndex) / 4.0
                    let v = Double(vIndex) / 4.0
                    return Point3D(x: u, y: v, z: 0.25 * u * v)
                }
            },
            weights: (0..<4).map { vIndex in
                (0..<5).map { uIndex in
                    1.0 + 0.0625 * Double(uIndex) + 0.03125 * Double(vIndex)
                }
            }
        )
    }

    private func literalHomogeneousJet(
        _ surface: BSplineSurface3D,
        u: Double,
        v: Double,
        usesRightUSide: Bool,
        usesRightVSide: Bool
    ) -> HomogeneousJet {
        let uBasis = literalUBasis(at: u, usesRightSide: usesRightUSide)
        let vBasis = literalVBasis(at: v, usesRightSide: usesRightVSide)
        var result = HomogeneousJet()
        for vIndex in vBasis.indices {
            for uIndex in uBasis.indices {
                let control = surface.controlPoints[vIndex][uIndex]
                let weight = surface.weights[vIndex][uIndex]
                let homogeneous = [
                    control.x * weight,
                    control.y * weight,
                    control.z * weight,
                    weight
                ]
                let uJet = uBasis[uIndex]
                let vJet = vBasis[vIndex]
                let factors = [
                    uJet.value * vJet.value,
                    uJet.first * vJet.value,
                    uJet.value * vJet.first,
                    uJet.second * vJet.value,
                    uJet.first * vJet.first,
                    uJet.value * vJet.second
                ]
                for index in 0..<6 {
                    result.x[index] += homogeneous[0] * factors[index]
                    result.y[index] += homogeneous[1] * factors[index]
                    result.z[index] += homogeneous[2] * factors[index]
                    result.weight[index] += homogeneous[3] * factors[index]
                }
            }
        }
        return result
    }

    private func emittedHomogeneousJet(
        _ patch: CertifiedHomogeneousBezierSurfacePatch,
        uFraction: Double,
        vFraction: Double
    ) -> HomogeneousBoundsJet {
        let uWidth = CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(
            patch.uUpper - patch.uLower
        )
        let vWidth = CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(
            patch.vUpper - patch.vLower
        )
        let uBasis = bernsteinJet(at: uFraction)
        let vBasis = bernsteinJet(at: vFraction)
        let uWidthSquared = uWidth * uWidth
        let vWidthSquared = vWidth * vWidth
        var result = HomogeneousBoundsJet()
        for vIndex in patch.controls.indices {
            for uIndex in patch.controls[vIndex].indices {
                let control = patch.controls[vIndex][uIndex]
                let uJet = uBasis[uIndex]
                let vJet = vBasis[vIndex]
                let factors = [
                    CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(
                        uJet.value * vJet.value
                    ),
                    CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(uJet.first)
                        / uWidth
                        * CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(vJet.value),
                    CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(vJet.first)
                        / vWidth
                        * CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(uJet.value),
                    CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(uJet.second)
                        / uWidthSquared
                        * CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(vJet.value),
                    CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(
                        uJet.first * vJet.first
                    ) / uWidth / vWidth,
                    CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(vJet.second)
                        / vWidthSquared
                        * CertifiedHomogeneousBezierSurfacePatch.ScalarBounds.exact(uJet.value)
                ]
                for index in 0..<6 {
                    result.x[index] = result.x[index] + control.x * factors[index]
                    result.y[index] = result.y[index] + control.y * factors[index]
                    result.z[index] = result.z[index] + control.z * factors[index]
                    result.weight[index] = result.weight[index] + control.weight * factors[index]
                }
            }
        }
        return result
    }

    private func literalUBasis(
        at parameter: Double,
        usesRightSide: Bool
    ) -> [BasisJet] {
        let isRight = usesRightSide
        let local = isRight ? 2.0 * parameter - 1.0 : 2.0 * parameter
        let values = [
            (1.0 - local) * (1.0 - local),
            2.0 * local * (1.0 - local),
            local * local
        ]
        let first = [
            -2.0 * (1.0 - local),
            2.0 - 4.0 * local,
            2.0 * local
        ].map { $0 * 2.0 }
        let second = [8.0, -16.0, 8.0]
        var result = Array(
            repeating: BasisJet(value: 0.0, first: 0.0, second: 0.0),
            count: 5
        )
        let start = isRight ? 2 : 0
        for index in 0..<3 {
            result[start + index] = BasisJet(
                value: values[index],
                first: first[index],
                second: second[index]
            )
        }
        return result
    }

    private func literalVBasis(
        at parameter: Double,
        usesRightSide: Bool
    ) -> [BasisJet] {
        if !usesRightSide {
            return [
                BasisJet(
                    value: (1.0 - 2.0 * parameter) * (1.0 - 2.0 * parameter),
                    first: -4.0 + 8.0 * parameter,
                    second: 8.0
                ),
                BasisJet(
                    value: 4.0 * parameter - 6.0 * parameter * parameter,
                    first: 4.0 - 12.0 * parameter,
                    second: -12.0
                ),
                BasisJet(
                    value: 2.0 * parameter * parameter,
                    first: 4.0 * parameter,
                    second: 4.0
                ),
                BasisJet(value: 0.0, first: 0.0, second: 0.0)
            ]
        }
        let w = 1.0 - parameter
        return [
            BasisJet(value: 0.0, first: 0.0, second: 0.0),
            BasisJet(value: 2.0 * w * w, first: -4.0 * w, second: 4.0),
            BasisJet(
                value: 4.0 * w - 6.0 * w * w,
                first: -4.0 + 12.0 * w,
                second: -12.0
            ),
            BasisJet(
                value: (1.0 - 2.0 * w) * (1.0 - 2.0 * w),
                first: 4.0 * (1.0 - 2.0 * w),
                second: 8.0
            )
        ]
    }

    private func bernsteinJet(at parameter: Double) -> [BasisJet] {
        let first = 2.0 * parameter * (1.0 - parameter)
        return [
            BasisJet(
                value: (1.0 - parameter) * (1.0 - parameter),
                first: -2.0 * (1.0 - parameter),
                second: 2.0
            ),
            BasisJet(value: first, first: 2.0 - 4.0 * parameter, second: -4.0),
            BasisJet(
                value: parameter * parameter,
                first: 2.0 * parameter,
                second: 2.0
            )
        ]
    }

    private func expectContains(
        _ bounds: CertifiedHomogeneousBezierSurfacePatch.ScalarBounds,
        _ value: Double
    ) {
        #expect(bounds.lower <= value)
        #expect(bounds.upper >= value)
    }

    private func expectContains(
        _ actual: HomogeneousBoundsJet,
        _ expected: HomogeneousJet
    ) {
        for index in 0..<6 {
            expectContains(actual.x[index], expected.x[index])
            expectContains(actual.y[index], expected.y[index])
            expectContains(actual.z[index], expected.z[index])
            expectContains(actual.weight[index], expected.weight[index])
        }
    }
}
