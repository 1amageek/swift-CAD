import Foundation
import Testing
import CADCore
import CADGeometry

@Suite("Certified rotation Taylor bounds")
struct CertifiedRotationTrigonometryTests {
    @Test(.timeLimit(.minutes(1)))
    func wholeAngleIntervalEnclosesTrigonometry() throws {
        for value in [-15.0, -3.0, -0.5, 0.0, 0.5, 3.0, 15.0] {
            let interval = OutwardScalarInterval(lower: value - 1e-8, upper: value + 1e-8)
            let result = try CertifiedRotationTrigonometry.evaluate(interval, tolerance: .standard)
            for angle in [interval.lower, value, interval.upper] {
                #expect(result.sine.contains(sin(angle)))
                #expect(result.cosine.contains(cos(angle)))
            }
        }
        let zero = try CertifiedRotationTrigonometry.evaluate(.exact(0), tolerance: .standard)
        #expect(zero.sine.lower == 0 && zero.sine.upper == 0)
        #expect(zero.cosine.lower == 1 && zero.cosine.upper == 1)
        #expect(throws: KernelError.self) {
            _ = try CertifiedRotationTrigonometry.evaluate(.exact(17), tolerance: .standard)
        }
    }
}
