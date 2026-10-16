import CADGeometry

protocol STEPSourceIdentityWriting: Sendable {
    func append(uuid: String, role: STEPSourceIdentityRole, target: Int,
                table: inout ExactSTEPWriter.EntityTable, using execution: inout OriginalQueryExecution) throws
}
