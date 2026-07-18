struct StrictAnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key: Hashable {
    func validateOnlyExpectedKeys(
        _ expectedKeys: Set<Key>,
        in decoder: Decoder
    ) throws {
        let rawContainer = try decoder.container(keyedBy: StrictAnyCodingKey.self)
        let expectedNames = Set(expectedKeys.map(\.stringValue))
        let unexpectedNames = rawContainer.allKeys
            .map(\.stringValue)
            .filter { expectedNames.contains($0) == false }
            .sorted()
        guard unexpectedNames.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unexpected keys: \(unexpectedNames.joined(separator: ", "))."
                )
            )
        }
    }
}
