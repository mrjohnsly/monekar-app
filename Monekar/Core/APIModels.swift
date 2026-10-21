import Foundation

// Namespacing keeps the API's Image model distinct from SwiftUI.Image.
nonisolated enum MonekarAPI {
    nonisolated struct Person: Codable, Equatable, Sendable, Identifiable {
        let id: Int
        let name: String
        let albumCount: Int
        let imageCount: Int
        let thumbnailURL: String
    }

    nonisolated struct Album: Codable, Equatable, Sendable, Identifiable {
        let id: Int
        let personID: Int
        let name: String
        let date: String?
        let models: [String]?
        let photographer: String?
        let imageCount: Int
        let thumbnailURL: String
    }

    nonisolated struct Image: Codable, Equatable, Sendable, Identifiable {
        let id: Int
        let albumID: Int
        let fileName: String
        let format: String
        let byteSize: Int64
        let width: Int?
        let height: Int?
        let thumbnailURL: String
        let originalURL: String
        let isFavourite: Bool
        let tags: [Tag]
    }

    nonisolated struct Tag: Codable, Equatable, Sendable, Identifiable {
        let id: Int
        let name: String
    }

    nonisolated struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
        let items: [Item]
        let total: Int
        let limit: Int
        let offset: Int
    }

    nonisolated struct Health: Codable, Equatable, Sendable {
        let status: String
    }

    nonisolated struct ScanStatus: Codable, Equatable, Sendable {
        nonisolated enum State: String, Codable, Sendable {
            case idle, running, failed
        }

        nonisolated enum Phase: String, Codable, Sendable {
            case indexingPeople = "indexing people"
            case indexingAlbumCovers = "indexing album covers"
            case indexingAllImages = "indexing all images"
            case complete, failed
        }

        let state: State
        let phase: Phase
        let discoveredPeople: Int
        let indexedPeople: Int
        let discoveredImages: Int
        let scannedImages: Int
        let remainingImages: Int
        let percentage: Double
        // Keep Unix seconds rather than Foundation's reference-date timestamps.
        let startedAt: TimeInterval?
        let lastCompletedAt: TimeInterval?
        let lastError: String?
    }

    nonisolated struct ScanReport: Codable, Equatable, Sendable {
        nonisolated struct Issue: Codable, Equatable, Sendable {
            let reason: String
        }

        let people: Int
        let albums: Int
        let images: Int
        let ignoredFiles: Int
        let removedImages: Int
        let pruned: Bool
        let issues: [Issue]
    }

    nonisolated enum ThumbnailSize: Int, CaseIterable, Sendable {
        case small = 128
        case medium = 256
        case large = 512
        case extraLarge = 1024
    }
}

extension MonekarAPI.Page: Equatable where Item: Equatable {}

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

nonisolated struct APIRequest {
    let path: [String]
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var body: Data?
}
