import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Sketch spline form")
struct SketchSplineFormTests {
    private func points(_ count: Int) -> [SketchPoint] {
        (0..<count).map { SketchPoint(x: .constant(.length(Double($0), unit: .meter)), y: .constant(.length(0, unit: .meter))) }
    }

    @Test func aChainNeedsDegreeTimesSpansPlusOnePoints() throws {
        try SketchSpline(controlPoints: points(7)).validateForm()
        try SketchSpline(controlPoints: points(11), degree: 5).validateForm()
        #expect(SketchSpline(controlPoints: points(11), degree: 5).spanCount == 2)
        #expect(SketchSpline(controlPoints: points(11), degree: 5).jointIndices == [0, 5, 10])
        #expect(throws: SketchError.self) { try SketchSpline(controlPoints: points(8), degree: 5).validateForm() }
        #expect(throws: SketchError.self) { try SketchSpline(controlPoints: points(3), degree: 0).validateForm() }
        #expect(throws: SketchError.self) {
            try SketchSpline(controlPoints: points(13), degree: SketchSpline.maximumDegree + 1).validateForm()
        }
    }

    @Test func theChainFormResolvesItsKnots() {
        #expect(SketchSpline(controlPoints: points(7)).knotVector == [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2])
        #expect(SketchSpline(controlPoints: points(6), degree: 5).knotVector == [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1])
    }

    @Test func explicitKnotsAreClampedNonDecreasingAndOfLimitedMultiplicity() throws {
        try SketchSpline(controlPoints: points(5), knots: [0, 0, 0, 0, 0.4, 1, 1, 1, 1]).validateForm()
        #expect(SketchSpline(controlPoints: points(5), knots: [0, 0, 0, 0, 0.4, 1, 1, 1, 1]).jointIndices == [0, 4])
        // A full-multiplicity interior knot passes through the control point before its run.
        #expect(SketchSpline(controlPoints: points(7), knots: [0, 0, 0, 0, 0.5, 0.5, 0.5, 1, 1, 1, 1]).jointIndices == [0, 3, 6])
        // Wrong count, not clamped, decreasing, empty domain, interior multiplicity above degree.
        for knots: [Double] in [
            [0, 0, 0, 0, 1, 1, 1, 1],
            [0, 0, 0, 0.1, 0.4, 1, 1, 1, 1],
            [0, 0, 0, 0, 0.6, 0.4, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1, 1],
        ] {
            #expect(throws: SketchError.self) { try SketchSpline(controlPoints: points(5), knots: knots).validateForm() }
        }
        #expect(throws: SketchError.self) {
            try SketchSpline(controlPoints: points(7), knots: [0, 0, 0, 0, 0.5, 0.5, 0.5, 0.5, 1, 1, 1]).validateForm()
        }
    }

    @Test func aCubicChainEncodesAsBeforeAndOtherFormsRoundTrip() throws {
        let cubic = SketchSpline(controlPoints: points(4))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(cubic)) as? [String: Any])
        #expect(Set(object.keys) == ["controlPoints", "isClosed"])
        let legacy = try JSONDecoder().decode(SketchSpline.self, from: JSONEncoder().encode(cubic))
        #expect(legacy == cubic && legacy.degree == 3 && legacy.knots == nil)

        let quintic = SketchSpline(controlPoints: points(6), degree: 5)
        #expect(try JSONDecoder().decode(SketchSpline.self, from: JSONEncoder().encode(quintic)) == quintic)
        let explicit = SketchSpline(controlPoints: points(5), knots: [0, 0, 0, 0, 0.4, 1, 1, 1, 1])
        #expect(try JSONDecoder().decode(SketchSpline.self, from: JSONEncoder().encode(explicit)) == explicit)
    }

    @Test func aSmoothJointConstraintNamesAChainJointOfTheSplinesDegree() throws {
        let id = SketchEntityID()
        func sketch(_ spline: SketchSpline, index: Int) -> Sketch {
            Sketch(plane: .xy, entities: [id: .spline(spline)], constraints: [.smoothSplineControlPoint(entity: id, index: index)])
        }
        try sketch(SketchSpline(controlPoints: points(11), degree: 5), index: 5).validate(tolerance: .standard)
        #expect(throws: SketchError.self) { try sketch(SketchSpline(controlPoints: points(11), degree: 5), index: 3).validate(tolerance: .standard) }
        #expect(throws: SketchError.self) {
            try sketch(SketchSpline(controlPoints: points(5), knots: [0, 0, 0, 0, 0.4, 1, 1, 1, 1]), index: 2).validate(tolerance: .standard)
        }
    }
}
