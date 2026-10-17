import CADCore
import CADGeometry

@main
struct LinearPlaneWholeSupportPortable {
    static func main() throws {
        for (name, check) in LinearPlaneWholeSupportChecks.checks {
            try check()
            print("PASS line whole-plane \(name)")
        }
    }
}
