import Foundation
import Observation

@MainActor
@Observable
final class ImageLibrary {
    private let api: any APIService
    private var sessionID: UUID?
    private var models: [Int: ImageViewModel] = [:]
    private(set) var revision = 0

    init(api: any APIService) {
        self.api = api
        sessionID = api.mediaSessionID
    }

    func synchronizeConnection() {
        guard sessionID != api.mediaSessionID else { return }
        sessionID = api.mediaSessionID
        models.removeAll()
        revision &+= 1
    }

    func model(for image: MonekarAPI.Image) -> ImageViewModel {
        synchronizeConnection()
        if let model = models[image.id] { return model }
        let model = ImageViewModel(image: image, api: api) { [weak self] in
            self?.revision &+= 1
        }
        models[image.id] = model
        return model
    }

    func feed(
        fetch: @escaping (Int, Int) async throws -> MonekarAPI.Page<MonekarAPI.Image>
    ) -> PaginatedViewModel<MonekarAPI.Image> {
        PaginatedViewModel { [self] limit, offset in
            synchronizeConnection()
            let session = api.mediaSessionID
            let versions = models.mapValues(\.revision)
            let page = try await fetch(limit, offset)
            try Task.checkCancellation()
            guard session == api.mediaSessionID else { throw CancellationError() }
            for image in page.items {
                // Preserve mutations to this image, not unrelated images on the page.
                if let model = models[image.id], (versions[image.id] ?? 0) != model.revision { continue }
                model(for: image).receive(image)
            }
            return page
        }
    }
}

@MainActor
@Observable
final class ImageViewModel {
    private(set) var image: MonekarAPI.Image
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var revision = 0
    var tagName = ""
    private let api: any APIService
    private let sessionID: UUID?
    private let changed: () -> Void

    init(image: MonekarAPI.Image, api: any APIService, changed: @escaping () -> Void = {}) {
        self.image = image
        self.api = api
        sessionID = api.mediaSessionID
        self.changed = changed
    }

    fileprivate func receive(_ image: MonekarAPI.Image) {
        guard !isBusy else { return }
        self.image = image
    }

    func setFavourite(_ value: Bool) async {
        _ = await perform {
            let updated = try await api.setFavourite(imageID: image.id, isFavourite: value)
            try checkSession()
            guard updated.id == image.id else { throw ConnectionFailure.invalidResponse }
            image = updated
            didChange()
        }
    }

    func loadTags() async {
        _ = await perform {
            let tags = try await api.tags(imageID: image.id)
            try Task.checkCancellation()
            try checkSession()
            if tags != image.tags {
                image.tags = tags
                didChange()
            }
        }
    }

    func addTag() async {
        guard !isBusy else { return }
        guard !tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a tag name."
            return
        }
        let name = tagName
        let succeeded = await perform {
            let tag = try await api.addTag(imageID: image.id, name: name)
            try checkSession()
            if let index = image.tags.firstIndex(where: { $0.id == tag.id }) {
                image.tags[index] = tag
            } else {
                image.tags.append(tag)
            }
            didChange()
        }
        if succeeded && tagName == name { tagName = "" }
    }

    func removeTag(id: Int) async {
        _ = await perform {
            try await api.removeTag(imageID: image.id, tagID: id)
            try checkSession()
            image.tags.removeAll { $0.id == id }
            didChange()
        }
    }

    private func checkSession() throws {
        guard sessionID == api.mediaSessionID else { throw CancellationError() }
    }

    private func didChange() {
        revision &+= 1
        changed()
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isBusy, sessionID == api.mediaSessionID else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard sessionID == api.mediaSessionID else { return false }
            switch error as? ConnectionFailure {
            case .serverRejected(404):
                errorMessage = "This image is no longer available."
            case .serverRejected(400), .serverRejected(422):
                errorMessage = "The server rejected this tag. Check its name and try again."
            case .some(let failure):
                errorMessage = failure.message
            case .none:
                errorMessage = "Unable to update this image. Check your connection and try again."
            }
            return false
        }
    }
}
