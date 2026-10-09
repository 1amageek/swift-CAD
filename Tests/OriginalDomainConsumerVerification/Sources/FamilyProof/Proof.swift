import NativeDomainFamilyFixtures
@main struct Proof {
    static func main() throws {
        try FamilyFixtures.verifyCS()
        try FamilyFixtures.verifyPeriodic()
        try FamilyFixtures.verifySSI()
        try FamilyFixtures.verifyFailures()
        try PublicationFailureFixtures.verify()
        print("PASS M2 complete Native domain family consumers")
    }
}
