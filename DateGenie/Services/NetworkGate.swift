import Foundation
import Network

final class NetworkGate {
    static let shared = NetworkGate()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.gate")
    private var reachable: Bool = false
    private var constrained: Bool = false
    private var expensive: Bool = false
    private var waiters: [(Bool) -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            self?.reachable = online
            self?.constrained = path.isConstrained
            self?.expensive = path.isExpensive
            if online {
                let w = self?.waiters ?? []
                self?.waiters.removeAll()
                for cb in w { cb(true) }
            }
        }
        monitor.start(queue: queue)
    }

    var isOnline: Bool { reachable }
    // Pause only when there is no route; otherwise attempt network with backoff
    var canAttemptNetwork: Bool { reachable }

    func waitUntilOnline() async {
        if reachable { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append { _ in cont.resume() }
        }
    }
}


