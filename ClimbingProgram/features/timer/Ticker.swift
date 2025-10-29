//
//  Ticker.swift
//
//  Created by Shahar Noy on 27.10.25.
//

import Foundation

public protocol Ticker: AnyObject {
    func start(_ handler: @escaping () -> Void)
    func stop()
}

public final class DispatchTicker: Ticker {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "timer.ticker.queue", qos: .userInitiated)
    private let interval: TimeInterval

    public init(interval: TimeInterval = 0.25) { // 4Hz – smooth & efficient
        self.interval = interval
    }

    public func start(_ handler: @escaping () -> Void) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(10))
        t.setEventHandler { handler() }
        t.resume()
        self.timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}
