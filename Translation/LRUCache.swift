import Foundation

/// A dictionary-like cache with a fixed capacity. Once full, adding a new
/// entry evicts the least-recently-*used* one (not just the oldest-inserted —
/// reading an entry counts as using it, so frequently-looked-up words stay
/// cached even if they were added long ago).
///
/// This is a `final class` rather than a `struct` specifically to avoid a
/// Swift compiler bug: calling a `mutating` method of a *generic* struct
/// through an actor-isolated stored property is sometimes misdiagnosed as
/// requiring an implicit `async` hop ("actor-isolated property cannot be
/// passed 'inout' to implicitly async function call"), even though nothing
/// involved is actually async. As a class, access to it through the actor's
/// stored property is a plain reference read — no formal `inout` access, so
/// the bug doesn't trigger.
///
/// Not thread-safe on its own — callers running on a single actor (as
/// TranslationCacheStore does) get that for free; a multi-threaded caller
/// would need its own synchronization.
final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    /// Least-recently-used first, most-recently-used last.
    private var usageOrder: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be positive")
        self.capacity = capacity
    }

    func value(forKey key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        markUsed(key)
        return value
    }

    func setValue(_ newValue: Value?, forKey key: Key) {
        guard let newValue else {
            storage[key] = nil
            usageOrder.removeAll { $0 == key }
            return
        }
        if storage[key] == nil {
            usageOrder.append(key)
        } else {
            markUsed(key)
        }
        storage[key] = newValue
        evictOverflow()
    }

    private func markUsed(_ key: Key) {
        if let index = usageOrder.firstIndex(of: key) {
            usageOrder.remove(at: index)
        }
        usageOrder.append(key)
    }

    private func evictOverflow() {
        // A simple array scan for the LRU entry is O(n), but n here is capped
        // at `capacity` (a few hundred at most) and evictions are infrequent
        // relative to lookups — no need for a more complex O(1) linked-list
        // structure for a cache this size.
        while storage.count > capacity, !usageOrder.isEmpty {
            let leastRecentlyUsed = usageOrder.removeFirst()
            storage[leastRecentlyUsed] = nil
        }
    }
}
