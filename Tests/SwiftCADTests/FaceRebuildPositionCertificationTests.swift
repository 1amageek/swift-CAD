import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
import SwiftCAD
import Testing

@Suite("Native Rebuild position publication")
struct FaceRebuildPositionCertificationTests {
    private let requestedDistance = 1e-6

    @Test(.timeLimit(.minutes(2)))
    func publicRebuildMustNotPublishTheOriginalInteriorBumpOutsideRequestedDistance() throws {
        let amplitude = 1e-3
        let original = originalSurface(amplitude: amplitude)
        do {
            let candidate = try publishedRebuild(of: original)

            // The only raised control multiplies two uniform cardinal cubic basis functions.
            // At their native center each is exactly 2/3, independently of any production fit.
            let literalHeight = 4 * amplitude / 9
            let literalCenter = Point3D(x: 1.0 / 8, y: 1.0 / 8, z: literalHeight)
            #expect(literalHeight > 400 * requestedDistance)
            let originalCenter = try original.point(u: 1.0 / 8, v: 1.0 / 8, tolerance: .standard)
            #expect((originalCenter - literalCenter).length <= 1e-12)

            let publishedCenter = try candidate.point(u: 1.0 / 8, v: 1.0 / 8, tolerance: .standard)
            let publishedPositionError = (publishedCenter - literalCenter).length
            #expect(publishedPositionError <= requestedDistance)
        } catch let error as KernelError {
            #expect(error.code == .approximationToleranceRejected)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func publicNativePlaneRebuildMeetsTheSamePositionRequest() throws {
        let original = originalSurface(amplitude: 0)
        let candidate = try publishedRebuild(of: original)
        for (u, v) in [(0.0, 0.0), (1.0 / 8, 1.0 / 8), (0.5, 0.5), (1.0, 1.0)] {
            let literal = Point3D(x: u, y: v, z: 0)
            let published = try candidate.point(u: u, v: v, tolerance: .standard)
            #expect((published - literal).length <= requestedDistance)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func callerLowPositionCertificationBudgetRejectsBeforePublication() throws {
        let limits = NativeSurfacePositionCertificationLimits(
            maximumCertificationBoxes: 1, maximumScalarCount: 1, maximumWorkUnits: 1
        )
        do {
            _ = try publishedRebuild(of: originalSurface(amplitude: 0), limits: limits)
            Issue.record("A caller budget below the certifier's admission cost unexpectedly published a rebuild.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func extensionOutsideOriginalNativeDomainIsTypedUnsupported() throws {
        do {
            _ = try publishedRebuild(of: originalSurface(amplitude: 0), extendU: 0.1)
            Issue.record("A rebuild extension outside the original native chart unexpectedly published.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }

    /// Native cubic graph on [0,1]^2 with unit weights and one interior raised control.
    /// Its bump support (1/16,3/16)^2 misses every initial fit Greville and quarter station.
    private func originalSurface(amplitude: Double) -> BSplineSurface3D {
        let knots: [Double] = [0, 0, 0, 0, 1.0 / 16, 3.0 / 32, 1.0 / 8,
                               5.0 / 32, 3.0 / 16, 1, 1, 1, 1]
        let abscissae = (0..<9).map { i in (knots[i + 1] + knots[i + 2] + knots[i + 3]) / 3 }
        let controls = (0..<9).map { j in (0..<9).map { i in
            Point3D(x: abscissae[i], y: abscissae[j], z: i == 4 && j == 4 ? amplitude : 0)
        } }
        return BSplineSurface3D(uDegree: 3, vDegree: 3, uKnots: knots, vKnots: knots,
            controlPoints: controls, weights: Array(repeating: Array(repeating: 1, count: 9), count: 9))
    }

    private func publishedRebuild(
        of original: BSplineSurface3D,
        limits: NativeSurfacePositionCertificationLimits = .standard,
        extendU: Double = 0,
        extendV: Double = 0
    ) throws -> BSplineSurface3D {
        let originalSnapshot = original
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sourceID = try builder.bSplineSurface(original)
        let sourceDocument = try builder.build(name: "Original native Rebuild source")
        let sourceSnapshot = sourceDocument
        // Deferred artifacts retain actual source/B-rep evaluation and avoid unrelated meshing.
        // Both evaluations enter the public pipeline with its actual concrete evaluator.
        let pipeline = CADPipeline(
            tolerance: .standard,
            evaluator: DocumentEvaluator(
                featureEvaluator: DefaultFeatureEvaluator(
                    nativeSurfacePositionCertificationLimits: limits
                ),
                tolerance: .standard,
                artifactPolicy: .deferred
            )
        )
        let sourceEvaluation = try pipeline.evaluate(sourceDocument)
        try sourceEvaluation.brep.validate(level: .exact, tolerance: .standard)
        let sourceFaceEntries = sourceEvaluation.subshapes.entries.filter { key, value in
            guard key.featureID == sourceID, case .face = value else { return false }
            return true
        }
        #expect(sourceFaceEntries.count == 1)
        let sourceFaceEntry = try #require(sourceFaceEntries.first)
        guard case let .face(sourceFaceID) = sourceFaceEntry.value else {
            Issue.record("The original source did not publish a face.")
            throw FeatureEvaluationError.invalidGraph("The source face selection is invalid.")
        }
        let sourceFace = try #require(sourceEvaluation.brep.faces[sourceFaceID])
        #expect(sourceEvaluation.brep.geometry.surfaces[sourceFace.surfaceID] == .bSpline(original))
        let reference = try sourceEvaluation.stableSubshapeReference(for: sourceFaceEntry.key)
        let rebuiltID = try builder.rebuildFaces(target: sourceID, faces: [reference],
            method: .tolerance(.constant(.length(requestedDistance, unit: .meter))),
            extendU: extendU, extendV: extendV, shrinks: true)
        let document = try builder.build(name: "Native Rebuild position publication")
        let published = try pipeline.evaluate(document)
        try published.brep.validate(level: .exact, tolerance: .standard)
        let faceIDs = published.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == rebuiltID, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faceIDs.count == 1)
        let faceID = try #require(faceIDs.first)
        let face = try #require(published.brep.faces[faceID])
        let support = try #require(published.brep.geometry.surfaces[face.surfaceID])
        guard case let .bSpline(candidate) = support else {
            Issue.record("Rebuild did not publish its actual B-spline support.")
            throw FeatureEvaluationError.invalidGraph("The rebuilt support is not a B-spline.")
        }
        // Rebuild fits the original native UV map on an outward-enclosed face extent.
        // Its knot endpoints may therefore overhang [0,1]; they do not rescale the chart.
        #expect(original.uDomain == .closed(0, 1) && original.vDomain == .closed(0, 1))
        guard case let .closed(uLower, uUpper) = candidate.uDomain,
              case let .closed(vLower, vUpper) = candidate.vDomain else {
            throw FeatureEvaluationError.invalidGraph("The rebuilt support needs a closed native chart.")
        }
        #expect(uLower <= 0 && uUpper >= 1 && vLower <= 0 && vUpper >= 1)
        #expect(candidate.uKnots.first == uLower && candidate.uKnots.last == uUpper)
        #expect(candidate.vKnots.first == vLower && candidate.vKnots.last == vUpper)
        // Unit-weight Greville XY controls establish affine precision over the whole chart,
        // independently of the fitter's sample diagnostics. Native (u,v) maps to (x,y)=(u,v),
        // so the original literal center is compared at the same candidate native parameters.
        for (j, row) in candidate.controlPoints.enumerated() {
            let nativeV = candidate.vKnots[(j + 1)...(j + candidate.vDegree)].reduce(0, +)
                / Double(candidate.vDegree)
            for (i, control) in row.enumerated() {
                let nativeU = candidate.uKnots[(i + 1)...(i + candidate.uDegree)].reduce(0, +)
                    / Double(candidate.uDegree)
                #expect(candidate.weights[j][i] == 1)
                #expect(abs(control.x - nativeU) <= 1e-12 && abs(control.y - nativeV) <= 1e-12)
            }
        }
        #expect(face.loops == sourceFace.loops)
        for loopID in sourceFace.loops {
            #expect(published.brep.loops[loopID] == sourceEvaluation.brep.loops[loopID])
        }
        let sourceNode = try #require(document.designGraph.nodes[sourceID])
        guard case let .bSplineSurface(retained) = sourceNode.operation else {
            throw FeatureEvaluationError.invalidGraph("The original source feature was not retained.")
        }
        #expect(retained.surface == original)
        #expect(published.document == document)
        #expect(sourceDocument == sourceSnapshot && original == originalSnapshot)
        return candidate
    }
}
