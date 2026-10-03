import Foundation
import Testing
import CADCore

@Suite("Kernel failure contract")
struct KernelFailureContractTests {
    @Test(.timeLimit(.minutes(1)))
    func preservesTessellationResourceExhaustion() {
        let error = KernelError.wrapping(
            TessellationError.resourceExhausted(.triangleCount, requested: 12, limit: 10),
            phase: .evaluation, tolerance: .standard
        )
        #expect(error.code == .resourceLimitExceeded)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnsupportedImportAndExport() {
        let imported = KernelError.wrapping(
            ImportError.unsupportedFormat("unsupported"), phase: .exchange, tolerance: .standard
        )
        let exported = KernelError.wrapping(
            ExportError.unsupportedFeature("unsupported"), phase: .exchange, tolerance: .standard
        )
        #expect(imported.code == .unsupportedCapability)
        #expect(exported.code == .unsupportedCapability)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesFailureCausesThroughPublicNormalization() {
        let cases: [(any Error, KernelErrorCode, KernelFailureCategory)] = [
            (TessellationError.unsupportedFace(FaceID()), .unsupportedCapability, .unsupportedDomain),
            (TessellationError.degenerateFace(FaceID()), .singularGeometry, .singularity),
            (TessellationError.invalidUsage(.triangleCount, recorded: -1), .invalidInput, .invalidInput),
            (TessellationError.invalidLimit(.triangleCount, requested: -1), .invalidInput, .invalidInput),
            (ExportError.triangleCountOverflow, .resourceLimitExceeded, .resourceExhaustion),
            (ExportError.externalToolUnavailable("tool"), .dependencyUnavailable, .dependencyUnavailable),
            (ExportError.externalToolFailure(tool: "tool", output: "failed"), .externalFailure, .externalFailure),
            (ExportError.fileWriteFailure("failed"), .ioFailure, .ioFailure),
            (ImportError.fileReadFailure("failed"), .ioFailure, .ioFailure),
            (ImportError.securityViolation("forbidden reference"), .securityViolation, .securityRefusal),
            (ImportError.missingRequiredEntity("surface"), .missingReference, .missingReference),
            (TopologyError.missingSurface(SurfaceID()), .missingReference, .missingReference),
            (ParameterError.unknownReference(ParameterID()), .missingReference, .missingReference),
            (GeometryError.invalidRadius(-1), .invalidInput, .invalidInput),
        ]
        for (cause, code, category) in cases {
            let normalized = KernelError.wrapping(cause, phase: .evaluation, tolerance: .standard)
            #expect(normalized.code == code)
            #expect(normalized.category == category)
            #expect(!normalized.message.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesOriginalDiagnosticContextAndFillsMissingContext() {
        let originalFeature = FeatureID()
        let suppliedFeature = FeatureID()
        let original = KernelError(
            phase: .classification, code: .classificationFailure,
            featureID: originalFeature, residual: 0.125,
            tolerance: .standard, message: "The interval could not be classified."
        )
        let preserved = KernelError.wrapping(
            original, phase: .exchange, featureID: suppliedFeature, tolerance: nil
        )
        #expect(preserved == original)
        #expect(preserved.category == .numericalIndeterminacy)
        let missingContext = KernelError(
            phase: .topology, code: .nonDiscreteIntersection, tolerance: nil,
            message: "The intersection contains a curve."
        )
        let filled = KernelError.wrapping(
            missingContext, phase: .evaluation, featureID: suppliedFeature, tolerance: .standard
        )
        #expect(filled.phase == .topology)
        #expect(filled.featureID == suppliedFeature)
        #expect(filled.tolerance == .standard)
        #expect(filled.category == .nonDiscreteResult)
        #expect(filled.message == missingContext.message)
    }

    @Test(.timeLimit(.minutes(1)))
    func unknownFailureDoesNotBecomeInvalidInput() {
        enum ForeignFailure: Error { case opaque }
        let error = KernelError.wrapping(
            ForeignFailure.opaque, phase: .geometry, tolerance: .standard
        )
        #expect(error.code == .unclassifiedFailure)
        #expect(error.category == .unclassified)
    }

    @Test(.timeLimit(.minutes(1)))
    func realTaskCancellationSurvivesAnEvaluationBoundary() async throws {
        let task = Task { () -> KernelError? in
            do {
                try await Task.sleep(for: .seconds(1))
                return nil
            } catch {
                return KernelError.wrapping(error, phase: .evaluation, tolerance: .standard)
            }
        }
        task.cancel()
        let error = try #require(await task.value)
        #expect(error.code == .cancelled)
        #expect(error.category == .cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func serializesEveryDeclaredCauseWithoutLosingItsCategory() throws {
        for code in KernelErrorCode.allCases {
            let error = KernelError(phase: .evaluation, code: code, tolerance: .standard, message: "failure")
            let decoded = try JSONDecoder().decode(KernelError.self, from: JSONEncoder().encode(error))
            #expect(decoded == error)
            #expect(decoded.category == error.category)
        }
        #expect(Set(KernelErrorCode.allCases.map(\.category)) == Set(KernelFailureCategory.allCases))
    }

}
