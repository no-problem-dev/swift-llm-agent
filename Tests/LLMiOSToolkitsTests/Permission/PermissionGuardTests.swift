import Foundation
import Testing
@testable import LLMiOSToolkits
import LLMTool

// MARK: - Mock

struct MockPermissionProvider: PermissionProvider, @unchecked Sendable {
    var permissionName: String = "Test"
    var settingsPath: String = "Test"
    var status: PermissionStatus
    var requestResult: PermissionStatus?
    var requestError: Error?

    func currentStatus() -> PermissionStatus {
        status
    }

    func requestAuthorization() async throws -> PermissionStatus {
        if let error = requestError { throw error }
        return requestResult ?? status
    }
}

// MARK: - Tests

@Suite("PermissionGuard")
struct PermissionGuardTests {

    @Test("authorized の場合は nil を返す")
    func authorizedReturnsNil() async {
        let provider = MockPermissionProvider(status: .authorized)
        let guard_ = PermissionGuard(provider: provider)

        let result = await guard_.ensureAuthorized()
        #expect(result == nil)
    }

    @Test("denied の場合はエラーを返す")
    func deniedReturnsError() async {
        let provider = MockPermissionProvider(
            permissionName: "Calendar",
            settingsPath: "Calendars",
            status: .denied
        )
        let guard_ = PermissionGuard(provider: provider)

        let result = await guard_.ensureAuthorized()
        guard case .error(let message) = result else {
            Issue.record("Expected .error but got \(String(describing: result))")
            return
        }
        #expect(message.contains("Calendar"))
        #expect(message.contains("Calendars"))
    }

    @Test("restricted の場合はエラーを返す")
    func restrictedReturnsError() async {
        let provider = MockPermissionProvider(
            permissionName: "Health",
            settingsPath: "Health",
            status: .restricted
        )
        let guard_ = PermissionGuard(provider: provider)

        let result = await guard_.ensureAuthorized()
        guard case .error(let message) = result else {
            Issue.record("Expected .error but got \(String(describing: result))")
            return
        }
        #expect(message.contains("restricted"))
    }

    @Test("notDetermined で認可成功なら nil を返す")
    func notDeterminedGrantedReturnsNil() async {
        let provider = MockPermissionProvider(
            status: .notDetermined,
            requestResult: .authorized
        )
        let guard_ = PermissionGuard(provider: provider)

        let result = await guard_.ensureAuthorized()
        #expect(result == nil)
    }

    @Test("notDetermined で認可拒否ならエラーを返す")
    func notDeterminedDeniedReturnsError() async {
        let provider = MockPermissionProvider(
            permissionName: "Reminders",
            settingsPath: "Reminders",
            status: .notDetermined,
            requestResult: .denied
        )
        let guard_ = PermissionGuard(provider: provider)

        let result = await guard_.ensureAuthorized()
        guard case .error(let message) = result else {
            Issue.record("Expected .error but got \(String(describing: result))")
            return
        }
        #expect(message.contains("Reminders"))
    }

    @Test("notDetermined で例外発生ならエラーを返す")
    func notDeterminedThrowsReturnsError() async {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "test failure" }
        }

        let provider = MockPermissionProvider(
            permissionName: "Calendar",
            settingsPath: "Calendars",
            status: .notDetermined,
            requestError: TestError()
        )
        let guard_ = PermissionGuard(provider: provider)

        let result = await guard_.ensureAuthorized()
        guard case .error(let message) = result else {
            Issue.record("Expected .error but got \(String(describing: result))")
            return
        }
        #expect(message.contains("test failure"))
    }
}
