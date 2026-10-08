import ConsumerFixtures
@main struct Proof {
    static func main() throws {
        try NativeExactFixtures.verifyCS()
        try NativeExactFixtures.verifySSI()
        try NativeExactFixtures.verifyFailures()
        print("PASS original domain consumer composition")
    }
}
