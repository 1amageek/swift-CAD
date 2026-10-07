extension OriginalSingularFieldContext {
    package convenience init<B: RationalAlgebraAdmitting>(original: ExactBivariateSystemRoot, usage: inout B) throws {
        try self.init(original: original.scalarAuthority, usage: &usage)
    }
}
