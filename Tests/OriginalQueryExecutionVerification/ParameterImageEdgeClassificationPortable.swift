@main
struct ParameterImageEdgeClassificationPortable {
    static func main() throws {
        try ParameterImageEdgeClassificationChecks.run()
        print("PASS original parameter-image classifier open and closed endpoints")
    }
}
