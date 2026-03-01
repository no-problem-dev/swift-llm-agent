import Foundation

#if os(iOS)
@preconcurrency import Contacts
@preconcurrency import CoreLocation
@preconcurrency import EventKit
import Photos
import UIKit
import UserNotifications
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(Speech)
import Speech
#endif
#endif

/// 設定画面で扱う統一的な権限 ID
public enum AppPermissionID: String, CaseIterable, Identifiable, Sendable, Codable {
    case calendarEvents
    case reminders
    case contacts
    case location
    case notifications
    case health
    case photos
    case camera
    case microphone
    case speechRecognition

    public var id: String { rawValue }
}

/// 設定画面に表示する権限メタデータ
public struct PermissionDescriptor: Identifiable, Sendable, Hashable {
    public let id: AppPermissionID
    public let title: String
    public let summary: String
    public let settingsPath: String
    public let featureNames: [String]
    public let iconName: String

    public init(
        id: AppPermissionID,
        title: String,
        summary: String,
        settingsPath: String,
        featureNames: [String],
        iconName: String
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.settingsPath = settingsPath
        self.featureNames = featureNames
        self.iconName = iconName
    }
}

/// 設定画面でユーザーに提示する次アクション
public enum PermissionActionKind: String, Sendable, Codable {
    case requestInApp
    case openSettings
    case none
}

/// 権限の最新状態
public struct PermissionSnapshot: Identifiable, Sendable {
    public let descriptor: PermissionDescriptor
    public let status: PermissionStatus
    public let action: PermissionActionKind
    public let message: String?

    public var id: AppPermissionID { descriptor.id }

    public init(
        descriptor: PermissionDescriptor,
        status: PermissionStatus,
        action: PermissionActionKind,
        message: String? = nil
    ) {
        self.descriptor = descriptor
        self.status = status
        self.action = action
        self.message = message
    }
}

/// 設定画面向けの権限カタログ
@MainActor
public enum PermissionCatalog {
    /// 表示順付きの全権限
    public static var descriptors: [PermissionDescriptor] {
        registry.map(\.descriptor)
    }

    /// 全権限の現在状態を取得
    public static func snapshots() async -> [PermissionSnapshot] {
        var results: [PermissionSnapshot] = []
        results.reserveCapacity(registry.count)

        for item in registry {
            results.append(await snapshot(for: item.descriptor.id))
        }

        return results
    }

    /// 単一権限の現在状態を取得
    public static func snapshot(for id: AppPermissionID) async -> PermissionSnapshot {
        guard let item = registry.first(where: { $0.descriptor.id == id }) else {
            return missingSnapshot(for: id)
        }

        guard let provider = item.makeProvider() else {
            return PermissionSnapshot(
                descriptor: item.descriptor,
                status: .restricted,
                action: .none,
                message: "このプラットフォームでは利用できません。"
            )
        }

        let status = await provider.resolvedStatus()
        return makeSnapshot(for: item.descriptor, status: status)
    }

    /// 未決定の権限を順番にまとめて要求
    public static func requestPendingAuthorizations() async -> [PermissionSnapshot] {
        var results: [PermissionSnapshot] = []
        results.reserveCapacity(registry.count)

        for item in registry {
            results.append(await requestAuthorization(for: item.descriptor.id))
        }

        return results
    }

    /// 単一権限を要求。拒否済みの場合は再要求せず状態のみ返す
    public static func requestAuthorization(for id: AppPermissionID) async -> PermissionSnapshot {
        guard let item = registry.first(where: { $0.descriptor.id == id }) else {
            return missingSnapshot(for: id)
        }

        guard let provider = item.makeProvider() else {
            return PermissionSnapshot(
                descriptor: item.descriptor,
                status: .restricted,
                action: .none,
                message: "このプラットフォームでは利用できません。"
            )
        }

        let current = await provider.resolvedStatus()
        switch current {
        case .authorized, .denied, .restricted:
            return makeSnapshot(for: item.descriptor, status: current)
        case .notDetermined:
            do {
                let requested = try await provider.requestAuthorization()
                return makeSnapshot(for: item.descriptor, status: requested)
            } catch {
                return PermissionSnapshot(
                    descriptor: item.descriptor,
                    status: .denied,
                    action: .openSettings,
                    message: error.localizedDescription
                )
            }
        }
    }

    /// アプリ設定を開く
    public static func openAppSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private static func makeSnapshot(
        for descriptor: PermissionDescriptor,
        status: PermissionStatus
    ) -> PermissionSnapshot {
        let action: PermissionActionKind
        switch status {
        case .authorized:
            action = .none
        case .notDetermined:
            action = .requestInApp
        case .denied:
            action = .openSettings
        case .restricted:
            action = .none
        }

        return PermissionSnapshot(
            descriptor: descriptor,
            status: status,
            action: action
        )
    }

    private static func missingSnapshot(for id: AppPermissionID) -> PermissionSnapshot {
        let descriptor = PermissionDescriptor(
            id: id,
            title: id.rawValue,
            summary: "",
            settingsPath: "",
            featureNames: [],
            iconName: "questionmark.circle"
        )
        return PermissionSnapshot(
            descriptor: descriptor,
            status: .restricted,
            action: .none,
            message: "権限定義が見つかりません。"
        )
    }

    private struct RegisteredPermission {
        let descriptor: PermissionDescriptor
        let makeProvider: @MainActor () -> (any PermissionProvider)?
    }

    private static var registry: [RegisteredPermission] {
        #if os(iOS)
        [
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .calendarEvents,
                    title: "カレンダー",
                    summary: "イベントの検索・作成に使用します。",
                    settingsPath: "Calendars",
                    featureNames: ["カレンダー", "カレンダーイベント追加"],
                    iconName: "calendar.badge.clock"
                ),
                makeProvider: {
                    let store = EKEventStore()
                    return CalendarEventPermission(eventStore: store)
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .reminders,
                    title: "リマインダー",
                    summary: "リマインダーの検索・作成に使用します。",
                    settingsPath: "Reminders",
                    featureNames: ["カレンダー"],
                    iconName: "checklist"
                ),
                makeProvider: {
                    let store = EKEventStore()
                    return CalendarReminderPermission(eventStore: store)
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .contacts,
                    title: "連絡先",
                    summary: "連絡先の検索・作成に使用します。",
                    settingsPath: "Contacts",
                    featureNames: ["連絡先"],
                    iconName: "person.crop.rectangle"
                ),
                makeProvider: {
                    ContactsPermission(contactStore: CNContactStore())
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .location,
                    title: "位置情報",
                    summary: "現在地取得・場所検索・地図選択に使用します。",
                    settingsPath: "Location Services",
                    featureNames: ["位置情報", "場所選択"],
                    iconName: "location"
                ),
                makeProvider: {
                    let manager = CLLocationManager()
                    let delegate = LocationManagerDelegate()
                    manager.delegate = delegate
                    return LocationPermission(
                        locationManager: manager,
                        delegate: delegate
                    )
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .notifications,
                    title: "通知",
                    summary: "ローカル通知の送信・管理に使用します。",
                    settingsPath: "Notifications",
                    featureNames: ["通知"],
                    iconName: "bell"
                ),
                makeProvider: {
                    NotificationPermission()
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .health,
                    title: "ヘルスケア",
                    summary: "ヘルスデータの読み取り・記録に使用します。",
                    settingsPath: "Health",
                    featureNames: ["ヘルスケア"],
                    iconName: "heart"
                ),
                makeProvider: {
                    #if canImport(HealthKit)
                    return HealthPermission(
                        healthStore: HKHealthStore(),
                        readTypes: HealthDataTypes.defaultReadTypes,
                        writeTypes: HealthDataTypes.defaultWriteTypes
                    )
                    #else
                    return nil
                    #endif
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .photos,
                    title: "写真",
                    summary: "写真の読み取りと写真選択に使用します。",
                    settingsPath: "Photos",
                    featureNames: ["写真", "写真選択"],
                    iconName: "photo.on.rectangle"
                ),
                makeProvider: {
                    PhotosPermission()
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .camera,
                    title: "カメラ",
                    summary: "カメラ撮影・バーコード・書類スキャンに使用します。",
                    settingsPath: "Camera",
                    featureNames: ["カメラ撮影", "バーコードスキャン", "ドキュメントスキャン"],
                    iconName: "camera"
                ),
                makeProvider: {
                    #if canImport(AVFoundation)
                    return CameraPermission()
                    #else
                    return nil
                    #endif
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .microphone,
                    title: "マイク",
                    summary: "音声入力の録音に使用します。",
                    settingsPath: "Microphone",
                    featureNames: ["音声入力"],
                    iconName: "mic"
                ),
                makeProvider: {
                    #if canImport(AVFoundation)
                    return MicrophonePermission()
                    #else
                    return nil
                    #endif
                }
            ),
            RegisteredPermission(
                descriptor: PermissionDescriptor(
                    id: .speechRecognition,
                    title: "音声認識",
                    summary: "音声入力の文字起こしに使用します。",
                    settingsPath: "Speech Recognition",
                    featureNames: ["音声入力"],
                    iconName: "waveform"
                ),
                makeProvider: {
                    #if canImport(Speech)
                    return SpeechRecognitionPermission()
                    #else
                    return nil
                    #endif
                }
            ),
        ]
        #else
        []
        #endif
    }
}

#if os(iOS) && canImport(AVFoundation)
private struct CameraPermission: PermissionProvider, Sendable {
    var permissionName: String { "Camera" }
    var settingsPath: String { "Camera" }

    func currentStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .authorized : .denied
    }
}

private struct MicrophonePermission: PermissionProvider, @unchecked Sendable {
    var permissionName: String { "Microphone" }
    var settingsPath: String { "Microphone" }

    func currentStatus() -> PermissionStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .authorized : .denied
    }
}
#endif

#if os(iOS) && canImport(Speech)
private struct SpeechRecognitionPermission: PermissionProvider, Sendable {
    var permissionName: String { "Speech Recognition" }
    var settingsPath: String { "Speech Recognition" }

    func currentStatus() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let status = await withCheckedContinuation { (
            continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>
        ) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }
}
#endif
