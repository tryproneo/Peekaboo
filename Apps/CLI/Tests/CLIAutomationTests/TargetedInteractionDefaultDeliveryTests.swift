import CoreGraphics
import Foundation
import PeekabooCore
import Testing
@testable import PeekabooCLI

@Suite(.tags(.safe), .serialized)
@MainActor
struct TargetedInteractionDefaultDeliveryTests {
    @Test
    func `targeted interaction commands default to background delivery`() async throws {
        let app = ServiceApplicationInfo(
            processIdentifier: 2468,
            bundleIdentifier: "com.apple.TextEdit",
            name: "TextEdit"
        )
        let automation = StubAutomationService()
        let applications = StubApplicationService(applications: [app])
        let clipboard = StubClipboardService()
        let services = TestServicesFactory.makePeekabooServices(
            applications: applications,
            clipboard: clipboard,
            automation: automation
        )

        try await self.assertTypeDefaultsToBackground(services: services, automation: automation)
        try await self.assertPressDefaultsToBackground(services: services, automation: automation)
        try await self.assertHotkeyDefaultsToBackground(services: services, automation: automation)
        try await self.assertPasteDefaultsToBackground(services: services, automation: automation)
        try await self.assertClickDefaultsToBackground(services: services, automation: automation)
        #expect(applications.activateCalls.isEmpty)
    }

    private func assertTypeDefaultsToBackground(
        services: PeekabooServices,
        automation: StubAutomationService
    ) async throws {
        let result = try await InProcessCommandRunner.run(
            ["type", "hello", "--app", "TextEdit", "--json", "--no-remote"],
            services: services
        )

        #expect(result.exitStatus == 0)
        let call = try #require(automation.targetedTypeActionsCalls.last)
        #expect(call.targetProcessIdentifier == 2468)
        let payload = try ExternalCommandRunner.decodeJSONResponse(
            from: result,
            as: CodableJSONResponse<TypeCommandResult>.self
        )
        #expect(payload.data.deliveryMode == "background")
        #expect(payload.data.targetPID == 2468)
    }

    private func assertPressDefaultsToBackground(
        services: PeekabooServices,
        automation: StubAutomationService
    ) async throws {
        let result = try await InProcessCommandRunner.run(
            ["press", "return", "--app", "TextEdit", "--json", "--no-remote"],
            services: services
        )

        #expect(result.exitStatus == 0)
        let call = try #require(automation.targetedTypeActionsCalls.last)
        #expect(call.targetProcessIdentifier == 2468)
        if case .key(.return) = call.actions.first {} else {
            Issue.record("Expected press to use a targeted return key action")
        }
        let payload = try ExternalCommandRunner.decodeJSONResponse(
            from: result,
            as: CodableJSONResponse<PressResult>.self
        )
        #expect(payload.data.deliveryMode == "background")
        #expect(payload.data.targetPID == 2468)
    }

    private func assertHotkeyDefaultsToBackground(
        services: PeekabooServices,
        automation: StubAutomationService
    ) async throws {
        let result = try await InProcessCommandRunner.run(
            ["hotkey", "cmd,l", "--app", "TextEdit", "--json", "--no-remote"],
            services: services
        )

        #expect(result.exitStatus == 0)
        let call = try #require(automation.targetedHotkeyCalls.last)
        #expect(call.keys == "cmd,l")
        #expect(call.targetProcessIdentifier == 2468)
        let payload = try ExternalCommandRunner.decodeJSONResponse(
            from: result,
            as: CodableJSONResponse<HotkeyResult>.self
        )
        #expect(payload.data.deliveryMode == "background")
        #expect(payload.data.targetPID == 2468)
    }

    private func assertPasteDefaultsToBackground(
        services: PeekabooServices,
        automation: StubAutomationService
    ) async throws {
        let result = try await InProcessCommandRunner.run(
            ["paste", "--text", "hello", "--app", "TextEdit", "--json", "--no-remote"],
            services: services
        )

        #expect(result.exitStatus == 0)
        let call = try #require(automation.targetedTypeActionsCalls.last)
        #expect(call.targetProcessIdentifier == 2468)
        if case .text("hello") = call.actions.first {} else {
            Issue.record("Expected paste text to use targeted text delivery")
        }
        let payload = try ExternalCommandRunner.decodeJSONResponse(
            from: result,
            as: CodableJSONResponse<PasteResult>.self
        )
        #expect(payload.data.deliveryMode == "background")
        #expect(payload.data.targetPID == 2468)
    }

    private func assertClickDefaultsToBackground(
        services: PeekabooServices,
        automation: StubAutomationService
    ) async throws {
        let result = try await InProcessCommandRunner.run(
            ["click", "--coords", "10,20", "--app", "TextEdit", "--global-coords", "--json", "--no-remote"],
            services: services
        )

        #expect(result.exitStatus == 0)
        let call = try #require(automation.targetedClickCalls.last)
        #expect(call.targetProcessIdentifier == 2468)
        if case let .coordinates(point) = call.target {
            #expect(point == CGPoint(x: 10, y: 20))
        } else {
            Issue.record("Expected click to use targeted coordinate delivery")
        }
        let payload = try ExternalCommandRunner.decodeJSONResponse(
            from: result,
            as: CodableJSONResponse<ClickDeliveryPayload>.self
        )
        #expect(payload.data.deliveryMode == "background")
    }
}

private struct ClickDeliveryPayload: Codable {
    let deliveryMode: String?
}
