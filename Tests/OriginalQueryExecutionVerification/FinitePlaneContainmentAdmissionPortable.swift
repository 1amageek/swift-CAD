@main
struct FinitePlaneContainmentAdmissionPortable {
    static func main() throws {
        try FinitePlaneContainmentAdmissionChecks.finitePlaneProximityUsesRetainedMaterialAndSource()
        print("PASS finitePlaneProximityUsesRetainedMaterialAndSource")
        try FinitePlaneContainmentAdmissionChecks.finiteBoundsAndOutsideToleranceKeepTheirCompletePath()
        print("PASS finiteBoundsAndOutsideToleranceKeepTheirCompletePath")
        try FinitePlaneContainmentAdmissionChecks.primitiveProjectionPreservesCallerWorkAndCancellation()
        print("PASS primitiveProjectionPreservesCallerWorkAndCancellation")
    }
}
