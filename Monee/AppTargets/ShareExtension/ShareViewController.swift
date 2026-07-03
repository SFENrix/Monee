//
//  ShareViewController.swift
//  Monee
//
//  Handles shared plain text and shared images identically: extract text (directly for
//  text shares, via VisionOCRService for image shares), then hand off to
//  ReceiptCaptureService — the exact same save-or-skip rule the Action Button flow uses.
//  A failed/empty OCR result on an image share behaves the same as "no amount found":
//  nothing is saved, and the photo itself is not retained anywhere after this runs.
//
//  ⚠️ Requires this file's Info.plist NSExtensionActivationRule to accept BOTH
//  public.plain-text and public.image (see ShareExtension/Info.plist).
//
//  ⚠️ Target membership: this file needs RegexParser.swift, Transaction.swift,
//  AppGroup.swift, VisionOCRServiceError.swift, CurrencyFormat.swift,
//  NotificationService.swift, and ReceiptCaptureService.swift all added to the
//  ShareExtension target in Xcode's File Inspector.
//
//  ⚠️ UI PLACEHOLDER — bare loading state, not a designed screen.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
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
        Task { await handleSharedItem() }
    }

    private func handleSharedItem() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = item.attachments?.first else {
            finish()
            return
        }

        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            await handleSharedText(attachment)
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            await handleSharedImage(attachment)
        } else {
            finish()
        }
    }

    private func handleSharedText(_ attachment: NSItemProvider) async {
        guard let data = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil),
              let text = data as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish()
            return
        }

        capture(rawText: text)
        finish()
    }

    private func handleSharedImage(_ attachment: NSItemProvider) async {
        guard let data = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) else {
            finish()
            return
        }

        var image: UIImage?
        if let url = data as? URL, let imgData = try? Data(contentsOf: url) {
            image = UIImage(data: imgData)
        } else if let img = data as? UIImage {
            image = img
        } else if let imgData = data as? Data {
            image = UIImage(data: imgData)
        }

        guard let image else {
            finish()
            return
        }

        let text = (try? await VisionOCRService.recognizeText(from: image)) ?? ""
        capture(rawText: text)
        finish()
    }

    private func capture(rawText: String) {
        NotificationService.configure() // defensive — extension launch may skip app init
        _ = ReceiptCaptureService.capture(rawText: rawText)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
