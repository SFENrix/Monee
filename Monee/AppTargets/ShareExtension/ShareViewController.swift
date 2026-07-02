//
//  ShareViewController.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

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
            finish(success: false)
            return
        }

        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, _ in
            guard let self else { return }

            var image: UIImage?
            if let url = data as? URL, let imgData = try? Data(contentsOf: url) {
                image = UIImage(data: imgData)
            } else if let img = data as? UIImage {
                image = img
            } else if let imgData = data as? Data {
                image = UIImage(data: imgData)
            }

            guard let image, let jpeg = image.jpegData(compressionQuality: 0.9) else {
                self.finish(success: false)
                return
            }

            do {
                try jpeg.write(to: AppGroup.pendingReceiptImageURL, options: .atomic)
                AppGroup.defaults.set(true, forKey: AppGroupKey.hasPendingReceipt)
                AppGroup.defaults.set(Date(), forKey: AppGroupKey.pendingReceiptSavedAt)
                self.finish(success: true)
            } catch {
                self.finish(success: false)
            }
        }
    }

    private func finish(success: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if success {
                self.openHostApp(url: DeepLink.pendingReceipt.url)
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Share Extensions have no `UIApplication.shared` in-process — walking the
    /// responder chain to find it is the standard workaround for opening a URL
    /// in the host app from here.
    private func openHostApp(url: URL) {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.perform(#selector(openURL(_:)), with: url)
                return
            }
            responder = responder?.next
        }
    }

    @objc private func openURL(_ url: URL) {}
}