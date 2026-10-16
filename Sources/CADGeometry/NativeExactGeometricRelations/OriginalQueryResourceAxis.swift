/// Independent resource meanings preserved at a public query failure boundary.
public enum OriginalQueryResourceAxis: Sendable, Equatable {
    case sourceTextBytes, combinedUnits, work, storageBytes, sourceRecords, valueDepth, coefficientDepth, sourceDepth, transportDepth
    case cells, charts, families, identities, results, spans, polynomialDegree
    case extensionLevel, closures, attachments, geometricDepth, scalarSlots, countOverflow
}
