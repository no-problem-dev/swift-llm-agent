import Foundation

/// iOS パーミッションの認可状態
public enum PermissionStatus: Sendable, Equatable {
    /// アクセスが許可されている
    case authorized
    /// ユーザーがアクセスを拒否した
    case denied
    /// デバイスの管理設定によりアクセスが制限されている
    case restricted
    /// まだ認可の判断が行われていない
    case notDetermined
}
