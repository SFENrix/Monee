//
//  ShareViewController.swift
//  Monee
//
//  Updated 02/07/26 — replaced the responder-chain openURL hack (unreliable on modern iOS,
//  extensions rarely have UIApplication in their responder chain) with the officially
//  supported NSExtensionContext.open(_:completionHandler:). Added os_log tracing since
//  extension UI dismisses too fast to see alerts — use Console.app or Xcode's device
//  console filtered to subsystem "com.rioferdinand.freelancefinance.share" to debug.
//

import UIKit
import UniformTypeIdentifiers
import os.log

class ShareViewController: UIViewController {

    private let log = Logger(subsystem: "com.rioferdinand.freelancefinance.share", category: "ShareExtension")

    override func viewDidLoad() {
        super.viewDidLoad()
        // ⚠️ UI PLACEHOLDER — bare loading state, not a designed screen.
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Saving to Monee…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        extractSharedImage()
    }

    private func extractSharedImage() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachment = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            })
        else {
            log.error("No image attachment found in extension input items")
            finish(success: false)
            return
        }

        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, error in
            guard let self else { return }

            if let error {
                self.log.error("loadItem failed: \(error.localizedDescription, privacy: .public)")
            }

            var image: UIImage?
            if let url = data as? URL, let imgData = try? Data(contentsOf: url) {
                image = UIImage(data: imgData)
            } else if let img = data as? UIImage {
                image = img
            } else if let imgData = data as? Data {
                image = UIImage(data: imgData)
            }

            guard let image, let jpeg = image.jpegData(compressionQuality: 0.9) else {
                self.log.error("Could not decode/encode loaded item as JPEG")
                self.finish(success: false)
                return
            }

            do {
                try jpeg.write(to: AppGroup.pendingReceiptImageURL, options: .atomic)
                AppGroup.defaults.set(true, forKey: AppGroupKey.hasPendingReceipt)
                AppGroup.defaults.set(Date(), forKey: AppGroupKey.pendingReceiptSavedAt)
                self.log.debug("Wrote pending receipt to \(AppGroup.pendingReceiptImageURL.path, privacy: .public)")
                self.finish(success: true)
            } catch {
                self.log.error("Failed writing to App Group container: \(error.localizedDescription, privacy: .public)")
                self.finish(success: false)
            }
        }
    }

    private func finish(success: Bool) {
        guard success else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        // The supported way for an extension to hand off to its host app — no
        // UIApplication lookup required, and it works from the extension's own
        // process. completionHandler tells us definitively whether iOS actually
        // opened Monee, instead of guessing.
        extensionContext?.open(DeepLink.pendingReceipt.url) { [weak self] opened in
            if !opened {
                self?.log.error("extensionContext.open returned false — host app did not open. Check moneeapp:// URL scheme is registered on the Main App target's Info tab.")
            } else {
                self?.log.debug("Host app open requested successfully")
            }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
