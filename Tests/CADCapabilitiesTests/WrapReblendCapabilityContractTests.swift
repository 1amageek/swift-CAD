import CADCapabilities
import CADCore
import Testing

@Suite("Wrap capability contract")
struct WrapReblendCapabilityContractTests {
    @Test(.timeLimit(.minutes(1)))
    func runtimeCatalogValidatesThePartialWrapEnvelope() throws {
        let catalog = KernelCapabilities.current
        try catalog.validate()

        let capability = try catalog.requireExecutable(operation: "wrap")
        #expect(capability.id == "MODEL-WRAP-001")
        #expect(capability.status == .partial)
        #expect(capability.failureCodes.contains(.unsupportedCapability))
        #expect(capability.acceptedInputs.contains("stableReferenceAndTargetFaces"))
        #expect(capability.exactOutputs.contains("validatedExactBRep"))
        #expect(capability.testFixtures.contains("WrapFeatureTests"))
        #expect(capability.testFixtures.contains("WrapReblendRequestAdmissionTests"))
    }

    @Test(.timeLimit(.minutes(1)))
    func completeSupportAdmissionRefusesThePartialWrapEnvelope() throws {
        do {
            _ = try KernelCapabilities.current.requireSupported(operation: "wrap")
            Issue.record("A partial Wrap capability was admitted as completely supported.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.category == .unsupportedDomain)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func wrapReblendRefusalRemainsBoundToTheEvaluatorSourceCondition() throws {
        let domain = try KernelCapabilities.current.domain(operation: "wrap")
        #expect(domain.knownLimitations.contains {
            $0.operations == ["wrap"]
                && $0.sourcePath == "Sources/CADKernel/WrapFeatureEvaluator.swift"
                && $0.condition.contains("nonlinear closed-chain Reblend producer")
                && $0.condition.contains("whole original radius")
                && $0.condition.contains("support incidence")
                && $0.condition.contains("tangency")
        })
    }
}
