private struct StrictAnyCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        return nil
    }
}

extension KeyedDecodingContainer where Key: Hashable {
    func validateOnlyExpectedKeys(_ expectedKeys: Set<Key>, in decoder: Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: StrictAnyCodingKey.self)
        let expectedKeyNames = Set(expectedKeys.map(\.stringValue))
        let unexpectedKey = rawContainer.allKeys
            .filter { !expectedKeyNames.contains($0.stringValue) }
            .sorted { $0.stringValue < $1.stringValue }
            .first
        guard let unexpectedKey else {
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath + [unexpectedKey],
                debugDescription: "Unexpected key \(unexpectedKey.stringValue)."
            )
        )
    }
}
