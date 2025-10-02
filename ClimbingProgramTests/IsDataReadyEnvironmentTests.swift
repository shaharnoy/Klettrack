// IsDataReadyEnvironmentTests.swift
// klettrack Tests
// Created by Shahar Noy on 05.10.25.

import XCTest
import SwiftUI
import UIKit
@testable import klettrack

// Host a SwiftUI view in a window so onAppear/onChange fire like in-app
private final class TestHost {
    let window = UIWindow(frame: UIScreen.main.bounds)
    init<V: View>(_ view: V) {
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
    }
}

// Probe object to capture the last isDataReady value seen by a SwiftUI view
@MainActor
private final class IsDataReadyProbe: ObservableObject {
    @Published var lastValue: Bool?
}

// Reader view: observes environment and forwards updates to the probe
private struct IsDataReadyReader: View {
    @Environment(\.isDataReady) private var isDataReady
    @ObservedObject var probe: IsDataReadyProbe

    var body: some View {
        Color.clear
            .onAppear { probe.lastValue = isDataReady }
            #if swift(>=5.9)
            .onChange(of: isDataReady) { _, newValue in
                probe.lastValue = newValue
            }
            #else
            .onChange(of: isDataReady) { newValue in
                probe.lastValue = newValue
            }
            #endif
    }
}

// Controller to deterministically drive the environment value from the test
@MainActor
private final class ReadyController: ObservableObject {
    @Published var ready: Bool = false
}

final class IsDataReadyEnvironmentTests: XCTestCase {

    // Keep the host alive for the duration of each test
    private var host: TestHost?

    override func tearDown() {
        host = nil
        super.tearDown()
    }

    @MainActor
    func testDefaultIsFalse() async throws {
        let probe = IsDataReadyProbe()
        host = TestHost(IsDataReadyReader(probe: probe))

        // Give the runloop a moment for onAppear
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(probe.lastValue, false, "Default isDataReady should be false")
    }

    @MainActor
    func testExplicitInjectionIsRead() async throws {
        let probe = IsDataReadyProbe()
        host = TestHost(
            IsDataReadyReader(probe: probe)
                .environment(\.isDataReady, true)
        )

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(probe.lastValue, true, "Injected environment value should be read by children")
    }

    @MainActor
    func testEnvironmentChangesPropagate() async throws {
        struct Wrapper: View {
            @ObservedObject var controller: ReadyController
            let probe: IsDataReadyProbe
            var body: some View {
                // Referencing controller.ready here ensures body recomputes when it changes,
                // propagating the updated value through the environment.
                IsDataReadyReader(probe: probe)
                    .environment(\.isDataReady, controller.ready)
            }
        }

        let probe = IsDataReadyProbe()
        let controller = ReadyController()
        host = TestHost(Wrapper(controller: controller, probe: probe))

        // Wait for the initial onAppear to propagate a value
        // Poll briefly until probe.lastValue is set to avoid flakiness.
        let start = Date()
        while probe.lastValue == nil && Date().timeIntervalSince(start) < 1.0 {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Initial read should be false
        XCTAssertEqual(probe.lastValue, false, "Initial value should be false")

        // Now toggle the environment deterministically
        controller.ready = true

        // Wait for propagation
        let changeStart = Date()
        while probe.lastValue != true && Date().timeIntervalSince(changeStart) < 1.0 {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        XCTAssertEqual(probe.lastValue, true, "Updated environment value should propagate to children")
    }
}
