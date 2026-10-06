struct STEPSourceIdentityWriter: STEPSourceIdentityWriting {
    func append(uuid: String, role: STEPSourceIdentityRole, target: Int,
                table: inout ExactSTEPWriter.EntityTable) throws {
        let source = try table.add("EXTERNAL_SOURCE(IDENTIFIER(\(try table.quotedString(STEPSourceIdentityRole.namespace))))")
        let identificationRole = try table.add("IDENTIFICATION_ROLE(\(try table.quotedString(role.rawValue)),$)")
        _ = try table.add("APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT(\(try table.quotedString(uuid)),#\(identificationRole),#\(source),(#\(target)))")
    }
}
