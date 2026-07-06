//
//  ScreenshotFetcher.swift
//  Monee
//
//  Fetches the most recently taken screenshot from the Photos library. Used by
//  ScanReceiptTextIntent (Action Button flow) so the Shortcut never has to pass an
//  image into the intent as a parameter — Shortcuts has no way to bind a previous
//  step's output to a file/image-typed custom App Intent parameter (it only offers a
//  manual "Choose File" picker for those), so the intent fetches the screenshot
//  itself instead. The Shortcut becomes just "Take Screenshot" -> "Run App Intent",
//  with nothing to configure.
//

import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum ScreenshotFetcher {
    /// Returns the most recently taken screenshot, or nil if Photo Library access
    /// isn't authorized or no screenshot exists.
    static func fetchMostRecent() async -> UIImage? {
        guard await isAuthorized() else { return nil }

        // No mediaSubtype filter: Shortcuts' "Take Screenshot" action doesn't tag its
        // output with PHAssetMediaSubtype.photoScreenshot the way a hardware screenshot
        // (side+volume button) is tagged. Filtering on that subtype silently excluded
        // every screenshot Shortcuts ever produced, always falling back to whatever
        // older hardware-tagged screenshot happened to be last in the library — which
        // never changes. Just fetch the most recent image overall instead.
        //
        // fetchLimit is a small batch, not 1: Photos' PHAssetMediaType.image also
        // matches certain saved PDF documents (e.g. from Notes' scanner, Mail, Safari),
        // and a PDF happening to be more recent than the screenshot would otherwise win
        // the "most recent" fetch outright. Walk a few candidates and skip anything
        // that isn't an actual photo format.
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 10

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var candidates: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in candidates.append(asset) }

        for asset in candidates where isGenuinePhoto(asset) {
            if let image = await requestImage(for: asset) {
                return image
            }
        }
        return nil
    }

    /// Excludes PDFs and other non-photo documents that Photos can also store under
    /// PHAssetMediaType.image (see fetchMostRecent's comment above).
    private static func isGenuinePhoto(_ asset: PHAsset) -> Bool {
        guard let uti = PHAssetResource.assetResources(for: asset).first?.uniformTypeIdentifier,
              let type = UTType(uti) else {
            return true // unknown type — don't silently skip a real screenshot over this
        }
        return type.conforms(to: .image) && !type.conforms(to: .pdf)
    }

    private static func isAuthorized() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    private static func requestImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
