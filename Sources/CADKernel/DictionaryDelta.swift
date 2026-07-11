import CADCore

struct DictionaryDelta<Key, Value>: Sendable
where Key: Hashable & Sendable, Value: Equatable & Sendable {
    struct Update: Sendable {
        var before: Value
        var after: Value
    }

    var removed: [Key: Value]
    var inserted: [Key: Value]
    var updated: [Key: Update]

    init(
        removed: [Key: Value] = [:],
        inserted: [Key: Value] = [:],
        updated: [Key: Update] = [:]
    ) {
        self.removed = removed
        self.inserted = inserted
        self.updated = updated
    }

    init(before: [Key: Value], after: [Key: Value]) {
        var removed: [Key: Value] = [:]
        var inserted: [Key: Value] = [:]
        var updated: [Key: Update] = [:]
        removed.reserveCapacity(before.count)
        inserted.reserveCapacity(after.count)

        for (key, beforeValue) in before {
            guard let afterValue = after[key] else {
                removed[key] = beforeValue
                continue
            }
            if beforeValue != afterValue {
                updated[key] = Update(before: beforeValue, after: afterValue)
            }
        }
        for (key, afterValue) in after where before[key] == nil {
            inserted[key] = afterValue
        }
        self.removed = removed
        self.inserted = inserted
        self.updated = updated
    }

    init(before: PersistentMap<Key, Value>, after: PersistentMap<Key, Value>) {
        var removed: [Key: Value] = [:]
        var inserted: [Key: Value] = [:]
        var updated: [Key: Update] = [:]
        removed.reserveCapacity(before.count)
        inserted.reserveCapacity(after.count)

        for (key, beforeValue) in before {
            guard let afterValue = after[key] else {
                removed[key] = beforeValue
                continue
            }
            if beforeValue != afterValue {
                updated[key] = Update(before: beforeValue, after: afterValue)
            }
        }
        for (key, afterValue) in after where before[key] == nil {
            inserted[key] = afterValue
        }
        self.removed = removed
        self.inserted = inserted
        self.updated = updated
    }

    var changeCount: Int {
        removed.count + inserted.count + updated.count
    }

    var inverted: DictionaryDelta<Key, Value> {
        DictionaryDelta(
            removed: inserted,
            inserted: removed,
            updated: updated.mapValues { change in
                Update(before: change.after, after: change.before)
            }
        )
    }

    func apply(to table: inout [Key: Value], tableName: String) throws {
        try validate(in: table, tableName: tableName)
        applyValidated(to: &table)
    }

    func validate(in table: [Key: Value], tableName: String) throws {
        for (key, expectedValue) in removed where table[key] != expectedValue {
            throw IncrementalReplayError.stateMismatch(table: tableName)
        }
        for (key, change) in updated where table[key] != change.before {
            throw IncrementalReplayError.stateMismatch(table: tableName)
        }
        for key in inserted.keys where table[key] != nil {
            throw IncrementalReplayError.stateMismatch(table: tableName)
        }
    }

    func applyValidated(to table: inout [Key: Value]) {
        for key in removed.keys {
            table.removeValue(forKey: key)
        }
        for (key, change) in updated {
            table[key] = change.after
        }
        for (key, value) in inserted {
            table[key] = value
        }
    }

    func apply(to table: inout PersistentMap<Key, Value>, tableName: String) throws {
        try validate(in: table, tableName: tableName)
        applyValidated(to: &table)
    }

    func validate(in table: PersistentMap<Key, Value>, tableName: String) throws {
        for (key, expectedValue) in removed where table[key] != expectedValue {
            throw IncrementalReplayError.stateMismatch(table: tableName)
        }
        for (key, change) in updated where table[key] != change.before {
            throw IncrementalReplayError.stateMismatch(table: tableName)
        }
        for key in inserted.keys where table[key] != nil {
            throw IncrementalReplayError.stateMismatch(table: tableName)
        }
    }

    func applyValidated(to table: inout PersistentMap<Key, Value>) {
        for key in removed.keys {
            table.removeValue(forKey: key)
        }
        for (key, change) in updated {
            table[key] = change.after
        }
        for (key, value) in inserted {
            table[key] = value
        }
    }
}
