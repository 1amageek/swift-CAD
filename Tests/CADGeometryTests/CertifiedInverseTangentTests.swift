import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Test(.timeLimit(.minutes(1)))
func certifiedInverseTangentEnclosesReferenceAndRejectsInvalidInput() throws {
    for value in [0.0, 0.001, 0.1, 0.5, 1, 2, 16] {
        let interval = try CertifiedRotationTrigonometry.inverseTangent(.exact(value), tolerance: .standard)
        #expect(interval.contains(atan(value)))
        #expect(interval.width < 1e-11)
    }
    let interval = try CertifiedRotationTrigonometry.inverseTangent(
        .init(lower: 0.25, upper: 0.5), tolerance: .standard)
    #expect(interval.contains(atan(0.25)))
    #expect(interval.contains(atan(0.5)))
    for value in [-1.0, 17, Double.infinity, Double.nan] {
        #expect(throws: KernelError.self) {
            try CertifiedRotationTrigonometry.inverseTangent(.exact(value), tolerance: .standard)
        }
    }
}
