import Foundation
import Testing
import CADCore
import CADGeometry

@Suite("Certified involute approximation")
struct InvoluteApproximationTests {
    @Test func analyticFlankAndPersistence() throws {
        let approximator: any InvoluteCurveApproximating = CertifiedInvoluteCurveApproximator()
        let result = try approximator.approximate(baseRadius: 0.02, rollRange: 0...1,
            maximumError: 1e-8, maximumSegments: 1024, tolerance: .standard)
        #expect(result.positionErrorUpperBound <= 1e-8)
        #expect(result.spans.count > 1)
        for (index, span) in result.spans.enumerated() {
            guard case .closed(let a, let b) = span.domain else { Issue.record("Expected bounded span"); return }
            for fraction in [0.0, 0.13, 0.37, 0.5, 0.81, 1.0] {
                let t = a + (b - a) * fraction
                let expected = Point3D(x: 0.02 * (cos(t) + t * sin(t)),
                    y: 0.02 * (sin(t) - t * cos(t)), z: 0)
                let actual = try span.point(at: t, tolerance: .standard)
                #expect((actual - expected).length <= result.positionErrorUpperBound)
            }
            if index > 0 { #expect(result.spans[index - 1].controlPoints.last == span.controlPoints.first) }
        }
        #expect(result.spans.first?.domain == .closed(0, 1 / Double(result.spans.count)))
        let decoded = try JSONDecoder().decode([BSplineCurve3D].self,
            from: JSONEncoder().encode(result.spans))
        #expect(decoded == result.spans)
    }

    @Test func refusesInvalidAndUnattainableRequests() throws {
        let approximator = CertifiedInvoluteCurveApproximator()
        for radius in [0.0, -1, .infinity, .nan] {
            #expect(throws: KernelError.self) {
                try approximator.approximate(baseRadius: radius, rollRange: 0...1,
                    maximumError: 1e-8, maximumSegments: 32, tolerance: .standard)
            }
        }
        #expect(throws: KernelError.self) {
            try approximator.approximate(baseRadius: 0.02, rollRange: 0...1,
                maximumError: 1e-30, maximumSegments: 1, tolerance: .standard)
        }
        #expect(throws: KernelError.self) {
            try approximator.approximate(baseRadius: 0.02, rollRange: 0...17,
                maximumError: 1e-8, maximumSegments: 32, tolerance: .standard)
        }
    }
}
