import Foundation
import Testing
import CADCore
@testable import CADTopology

@Suite("Offset disk-section volume integration")
struct OffsetDiskSectionVolumeIntegratorTests {
    @Test
    func offsetTorusAnnulusIntersectionMatchesIndependentOracle() throws {
        let tolerance = ModelingTolerance.standard
        let firstMajorRadius = 3.0
        let firstMinorRadius = 0.5
        let secondMajorRadius = 3.0
        let secondMinorRadius = 1.5
        let axialOffset = 0.25
        let radialOffset = 2.2
        let firstTubeRadius: (Double) -> Double = { coordinate in
            sqrt(max(
                0.0,
                firstMinorRadius * firstMinorRadius - coordinate * coordinate
            ))
        }
        let secondTubeRadius: (Double) -> Double = { coordinate in
            let local = coordinate - axialOffset
            return sqrt(max(
                0.0,
                secondMinorRadius * secondMinorRadius - local * local
            ))
        }

        let volume = try OffsetDiskSectionVolumeIntegrator().annulusIntersectionVolume(
            breakpoints: [-0.5, 0.0, 0.25, 0.5],
            centerDistance: radialOffset,
            characteristicLength: 4.5,
            tolerance: tolerance,
            firstInnerRadiusAt: { firstMajorRadius - firstTubeRadius($0) },
            firstOuterRadiusAt: { firstMajorRadius + firstTubeRadius($0) },
            secondInnerRadiusAt: { secondMajorRadius - secondTubeRadius($0) },
            secondOuterRadiusAt: { secondMajorRadius + secondTubeRadius($0) }
        )

        let expectedVolume = 7.285_038_823_821_337
        let errorBound = tolerance.distance * 4.5 * 4.5 * 8.0
        #expect(abs(volume - expectedVolume) <= errorBound)
    }
}
