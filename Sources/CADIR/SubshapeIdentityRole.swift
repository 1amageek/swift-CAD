package enum SubshapeIdentityRole {
    package static func compose(
        generatedRole: String,
        subshapeRole: String? = nil
    ) -> String {
        guard let subshapeRole else { return generatedRole }
        return "\(generatedRole).\(subshapeRole)"
    }
}
