import Foundation
import LLMClient
import LLMTool
import LLMMCP
import Photos

// MARK: - PhotosToolKit

/// 写真ライブラリのメタデータを操作する ToolKit
///
/// PhotoKit を使用して、写真の検索・メタデータ取得・アルバム一覧を提供します。
/// 写真のバイナリデータは返しません（メタデータのみ）。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     PhotosToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `search_photos`: 日付・メディアタイプ・アルバムで写真を検索
/// - `get_photo_metadata`: 写真の詳細メタデータを取得
/// - `get_albums`: アルバム一覧を取得
public final class PhotosToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "photos"

    private let guard_: PermissionGuard

    // MARK: - Initialization

    public init() {
        self.guard_ = PermissionGuard(provider: PhotosPermission())
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            searchPhotosTool,
            getPhotoMetadataTool,
            getAlbumsTool,
        ]
    }

    // MARK: - search_photos

    private var searchPhotosTool: BuiltInTool {
        BuiltInTool(
            name: "search_photos",
            description: "Search photos by date range, media type, or album. "
                + "Returns photo metadata (not the image data itself).",
            inputSchema: .object(
                properties: [
                    "start_date": .string(description: "Start date in ISO8601 format"),
                    "end_date": .string(description: "End date in ISO8601 format"),
                    "media_type": .string(
                        description: "Filter by type: 'photo', 'video', or 'all' (default: 'all')"
                    ),
                    "album_name": .string(description: "Filter by album name (partial match)"),
                    "limit": .integer(description: "Maximum results (default: 20, max: 100)"),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Search Photos",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(SearchPhotosInput.self, from: data)
            let limit = min(input.limit ?? 20, 100)

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
            fetchOptions.fetchLimit = limit

            var predicates: [NSPredicate] = []

            // 日付フィルタ
            if let startStr = input.startDate,
               let start = CalendarDateHelper.parseDate(startStr) {
                predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
            }
            if let endStr = input.endDate,
               let end = CalendarDateHelper.parseDate(endStr) {
                predicates.append(NSPredicate(format: "creationDate <= %@", end as NSDate))
            }

            // メディアタイプフィルタ
            let mediaType = input.mediaType?.lowercased() ?? "all"
            if mediaType == "photo" {
                predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
            } else if mediaType == "video" {
                predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
            }

            if !predicates.isEmpty {
                fetchOptions.predicate = NSCompoundPredicate(
                    andPredicateWithSubpredicates: predicates
                )
            }

            // アルバムフィルタ
            let assets: PHFetchResult<PHAsset>
            if let albumName = input.albumName?.lowercased() {
                let albums = PHAssetCollection.fetchAssetCollections(
                    with: .album, subtype: .any, options: nil
                )
                var targetCollection: PHAssetCollection?
                albums.enumerateObjects { collection, _, stop in
                    if collection.localizedTitle?.lowercased().contains(albumName) == true {
                        targetCollection = collection
                        stop.pointee = true
                    }
                }
                if let collection = targetCollection {
                    assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                } else {
                    return .error("Album '\(input.albumName ?? "")' not found.")
                }
            } else {
                assets = PHAsset.fetchAssets(with: fetchOptions)
            }

            var results: [PhotoInfo] = []
            assets.enumerateObjects { asset, _, stop in
                if results.count >= limit {
                    stop.pointee = true
                    return
                }
                results.append(Self.photoInfo(from: asset))
            }

            return try .encoded(results)
        }
    }

    // MARK: - get_photo_metadata

    private var getPhotoMetadataTool: BuiltInTool {
        BuiltInTool(
            name: "get_photo_metadata",
            description: "Get detailed metadata for a specific photo by ID. "
                + "Includes camera info, location, dimensions, and more.",
            inputSchema: .object(
                properties: [
                    "id": .string(description: "Photo ID from search_photos results"),
                ],
                required: ["id"]
            ),
            annotations: ToolAnnotations(
                title: "Get Photo Metadata",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(GetPhotoMetadataInput.self, from: data)

            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: [input.id],
                options: nil
            )
            guard let asset = result.firstObject else {
                return .error("Photo not found with ID: \(input.id)")
            }

            let detail = PhotoDetailInfo(
                id: asset.localIdentifier,
                creationDate: asset.creationDate.map { CalendarDateHelper.formatDate($0) },
                modificationDate: asset.modificationDate.map { CalendarDateHelper.formatDate($0) },
                mediaType: Self.mediaTypeName(asset.mediaType),
                width: asset.pixelWidth,
                height: asset.pixelHeight,
                isFavorite: asset.isFavorite,
                isHidden: asset.isHidden,
                duration: asset.mediaType == .video ? asset.duration : nil,
                location: asset.location.map {
                    PhotoLocationInfo(
                        latitude: $0.coordinate.latitude,
                        longitude: $0.coordinate.longitude
                    )
                },
                cameraMake: nil,
                cameraModel: nil
            )

            return try .encoded(detail)
        }
    }

    // MARK: - get_albums

    private var getAlbumsTool: BuiltInTool {
        BuiltInTool(
            name: "get_albums",
            description: "List all photo albums with their names and photo counts.",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Albums",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            var albums: [AlbumInfo] = []

            // ユーザーアルバム
            let userAlbums = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: nil
            )
            userAlbums.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                albums.append(AlbumInfo(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle,
                    count: count,
                    albumType: "user"
                ))
            }

            // スマートアルバム
            let smartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .any, options: nil
            )
            smartAlbums.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                guard count > 0 else { return }
                albums.append(AlbumInfo(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle,
                    count: count,
                    albumType: "smart"
                ))
            }

            return try .encoded(albums)
        }
    }

    // MARK: - Helpers

    private static func photoInfo(from asset: PHAsset) -> PhotoInfo {
        PhotoInfo(
            id: asset.localIdentifier,
            creationDate: asset.creationDate.map { CalendarDateHelper.formatDate($0) },
            mediaType: mediaTypeName(asset.mediaType),
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            isFavorite: asset.isFavorite,
            location: asset.location.map {
                PhotoLocationInfo(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            }
        )
    }

    private static func mediaTypeName(_ type: PHAssetMediaType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "audio"
        default: return "unknown"
        }
    }
}
