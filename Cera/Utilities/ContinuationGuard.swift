//
//  ContinuationGuard.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import Foundation

/// Prevents a checked continuation from being resumed more than once.
///
/// Vision request handlers can fire their completion block AND throw from
/// `perform()` in rare edge cases. Wrapping resume calls with this guard
/// ensures only the first one goes through.
///
/// Usage:
///   let guard = ContinuationGuard()
///   // In completion handler:
///   guard guard.claim() else { return }
///   continuation.resume(...)
final class ContinuationGuard: @unchecked Sendable {
    private var _resumed = false
    private let lock = NSLock()

    /// Attempts to claim the single resume slot.
    /// Returns `true` exactly once; all subsequent calls return `false`.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_resumed else { return false }
        _resumed = true
        return true
    }
}
