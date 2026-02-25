import Foundation

// MARK: - Input Types

struct SearchPhotosInput: Codable {
    var startDate: String?
    var endDate: String?
    var mediaType: String?
    var albumName: String?
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case mediaType = "media_type"
        case albumName = "album_name"
        case limit
    }
}

struct GetPhotoMetadataInput: Codable {
    var id: String
}

// MARK: - Output Types

struct PhotoInfo: Codable, Sendable {
    var id: String
    var creationDate: String?
    var mediaType: String
    var width: Int
    var height: Int
    var isFavorite: Bool
    var location: PhotoLocationInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case creationDate = "creation_date"
        case mediaType = "media_type"
        case width, height
        case isFavorite = "is_favorite"
        case location
    }
}

struct PhotoLocationInfo: Codable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct PhotoDetailInfo: Codable, Sendable {
    var id: String
    var creationDate: String?
    var modificationDate: String?
    var mediaType: String
    var width: Int
    var height: Int
    var isFavorite: Bool
    var isHidden: Bool
    var duration: Double?
    var location: PhotoLocationInfo?
    var cameraMake: String?
    var cameraModel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case creationDate = "creation_date"
        case modificationDate = "modification_date"
        case mediaType = "media_type"
        case width, height
        case isFavorite = "is_favorite"
        case isHidden = "is_hidden"
        case duration, location
        case cameraMake = "camera_make"
        case cameraModel = "camera_model"
    }
}

struct AlbumInfo: Codable, Sendable {
    var id: String
    var title: String?
    var count: Int
    var albumType: String

    enum CodingKeys: String, CodingKey {
        case id, title, count
        case albumType = "album_type"
    }
}
