public enum CADIdentifierRules {
    public static func validate(_ name: String) throws {
        guard isValid(name) else {
            throw ParameterError.invalidName(name)
        }
    }

    public static func isValid(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else {
            return false
        }
        guard isIdentifierHead(first) else {
            return false
        }
        return name.unicodeScalars.dropFirst().allSatisfy(isIdentifierBody)
    }

    private static func isIdentifierHead(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || isASCIIAlpha(scalar)
    }

    private static func isIdentifierBody(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierHead(scalar) || isASCIIDigit(scalar)
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(Int(scalar.value))
    }
}
