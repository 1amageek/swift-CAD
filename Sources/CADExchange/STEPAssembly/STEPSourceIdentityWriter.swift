import CADGeometry

struct STEPSourceIdentityWriter: STEPSourceIdentityWriting {
    func append(uuid: String, role: STEPSourceIdentityRole, target: Int,
                table: inout ExactSTEPWriter.EntityTable, using execution: inout OriginalQueryExecution) throws {
        let source = try table.add("EXTERNAL_SOURCE(IDENTIFIER(\(try table.quotedString(STEPSourceIdentityRole.namespace, using: &execution))))", using: &execution)
        let identificationRole = try table.add("IDENTIFICATION_ROLE(\(try table.quotedString(role.rawValue, using: &execution)),$)", using: &execution)
        _ = try table.add("APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT(\(try table.quotedString(uuid, using: &execution)),#\(identificationRole),#\(source),(#\(target)))", using: &execution)
    }
}
