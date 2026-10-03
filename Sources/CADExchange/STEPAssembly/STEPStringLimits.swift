public struct STEPStringLimits: Equatable, Sendable {
    public let maximumInputBytes: Int
    public let maximumOutputBytes: Int
    public let maximumWork: Int
    public init(maximumInputBytes: Int = 32769, maximumOutputBytes: Int = 32769,
                maximumWork: Int = 65538) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumWork = maximumWork
    }
    public static let standard = Self()
    func validate() throws {
        guard maximumInputBytes >= 0, maximumOutputBytes >= 0, maximumWork >= 0 else {
            throw STEPStringError.invalidLimits
        }
    }
}
