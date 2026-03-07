//
//  ConnectivityMonitor.swift
//  Cera
//
//  Created by Oskar Pajka on 07/03/2026.
//

import Foundation
import Network

/// Observes network reachability via `NWPathMonitor` and exposes a
/// simple boolean that views and view models can check.
@Observable
final class ConnectivityMonitor {

    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cera.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
