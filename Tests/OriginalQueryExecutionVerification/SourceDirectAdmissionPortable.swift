/// Runs the same thirteen source checks as the Native wrappers.
@main
struct SourceDirectAdmissionPortable {
    private struct GroupFailure: Error {
        let group: String
        let original: any Error
    }
    private static func group(_ identifier: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch { throw GroupFailure(group: identifier, original: error) }
    }
    static func main() throws {
        try group("stationaryNativeSupportCannotResetCallerSourceDepth") { try SourceDirectAdmissionChecks.stationaryNativeSupportCannotResetCallerSourceDepth() }
        print("PASS stationaryNativeSupportCannotResetCallerSourceDepth")
        try group("originalGainAdmitsItsActualFactorPayloadBeforeRetention") { try SourceDirectAdmissionChecks.originalGainAdmitsItsActualFactorPayloadBeforeRetention() }
        print("PASS originalGainAdmitsItsActualFactorPayloadBeforeRetention")
        for native in [false, true] {
            try group("sourceOperationsPreserveExactCallerResourceBoundaries native=\(native)") { try SourceDirectAdmissionChecks.sourceOperationsPreserveExactCallerResourceBoundaries(native: native) }
            print("PASS sourceOperationsPreserveExactCallerResourceBoundaries native=\(native)")
        }
        for native in [false, true] {
            try group("sourceOperationsObserveEntryAndTerminalCancellation native=\(native)") { try SourceDirectAdmissionChecks.sourceOperationsObserveEntryAndTerminalCancellation(native: native) }
            print("PASS sourceOperationsObserveEntryAndTerminalCancellation native=\(native)")
        }
        try group("factorOwnersAndIndependentZeroDepthKeepTheOriginalImageLaw") { try SourceDirectAdmissionChecks.factorOwnersAndIndependentZeroDepthKeepTheOriginalImageLaw() }
        print("PASS factorOwnersAndIndependentZeroDepthKeepTheOriginalImageLaw")
        for restricted in [false, true] {
            try group("selectedMiddleCurveJetsUseTheCallerStorageAdmission restricted=\(restricted)") { try SourceDirectAdmissionChecks.Graph.selectedMiddleCurveJetsUseTheCallerStorageAdmission(restricted: restricted) }
            print("PASS selectedMiddleCurveJetsUseTheCallerStorageAdmission restricted=\(restricted)")
        }
        for restricted in [false, true] {
            try group("originalGraphLawsRetainDirectionsAndExactCallerLimits restricted=\(restricted)") { try SourceDirectAdmissionChecks.Graph.originalGraphLawsRetainDirectionsAndExactCallerLimits(restricted: restricted) }
            print("PASS originalGraphLawsRetainDirectionsAndExactCallerLimits restricted=\(restricted)")
        }
        for restricted in [false, true] {
            try group("graphReadersPreserveCallerCancellation restricted=\(restricted)") { try SourceDirectAdmissionChecks.Graph.graphReadersPreserveCallerCancellation(restricted: restricted) }
            print("PASS graphReadersPreserveCallerCancellation restricted=\(restricted)")
        }
    }
}
