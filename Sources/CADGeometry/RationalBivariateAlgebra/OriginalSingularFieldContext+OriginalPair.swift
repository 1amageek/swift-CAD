extension OriginalSingularFieldContext {
    package convenience init<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariateSystemRoot, usage: inout B) throws {
        try self.init(original: original.scalarAuthority, usage: &usage)
    }
}
