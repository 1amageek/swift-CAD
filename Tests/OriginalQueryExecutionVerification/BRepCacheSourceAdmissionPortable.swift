@main
struct BRepCacheSourceAdmissionPortable {
    static func main() throws {
        try BRepCacheSourceAdmissionChecks.canonicalOriginalContentIgnoresRegeneratedTopologyIDs()
        print("PASS brep-cache-source canonical-original-content-and-regenerated-ids")
        try BRepCacheSourceAdmissionChecks.exactCumulativeWorkAndStorageBoundaries()
        print("PASS brep-cache-source exact-cumulative-work-and-storage")
        try BRepCacheSourceAdmissionChecks.nestedFailuresRetainTheirOriginalTypedCause()
        print("PASS brep-cache-source nested-original-typed-failures")
        try BRepCacheSourceAdmissionChecks.cancellationAndRetainedSourceLifetime()
        print("PASS brep-cache-source cancellation-and-retained-source-lifetime")
    }
}
