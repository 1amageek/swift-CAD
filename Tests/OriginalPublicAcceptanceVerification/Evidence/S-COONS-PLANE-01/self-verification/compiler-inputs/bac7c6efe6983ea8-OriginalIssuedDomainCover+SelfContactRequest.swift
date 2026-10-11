extension OriginalIssuedDomainCover: OriginalIssuedGraphSelfContactRequestReading where Field == OriginalExactScalarDomain {
    public var selfContactRequest: OriginalParameterSelection<Source,OriginalExactScalarDomain> { coverage.request }
}
