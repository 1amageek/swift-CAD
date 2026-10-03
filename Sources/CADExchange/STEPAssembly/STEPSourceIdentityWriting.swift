protocol STEPSourceIdentityWriting: Sendable {
    func append(uuid: String, role: STEPSourceIdentityRole, target: Int,
                table: inout ExactSTEPWriter.EntityTable) throws
}
