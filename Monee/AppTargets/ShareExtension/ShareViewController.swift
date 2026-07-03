//
//  ShareViewController.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Updated 03/07/26 — now handles shared PLAIN TEXT in addition to shared images, and
//  runs OCR + RegexParser directly in the extension process instead of handing an image
//  off to the main app to process. Vision framework works fine inside extensions, no
//  special entitlement needed. This retires the old single-slot App Group handoff
//  (loadPendingReceipt in ContentView) — both paths now stage into PendingReceiptStore
//  and fire the same rich notification the Action Button flow uses.
//
//  ⚠️ Requires this file's Info.plist NSExtensionActivationRule to accept BOTH
//  public.plain-text and public.image (previously image-only). Simple dictionary form:
//    NSExtensionActivationRule = {
//      NSExtensionActivationSupportsText = YES
//      NSExtensionActivationSupportsImageWithMaxCount = 1
//    }
//
//  ⚠️ Target membership: this file needs RegexParser.swift, Transaction.swift,
//  AppGroup.swift, PendingReceiptText.swift, NotificationCategory.swift, and
//  VisionOCRServiceError.swift (which contains VisionOCRService) all added to the
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

        stageAndNotify(rawText: text, imageData: nil)
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

        let jpeg = image.jpegData(compressionQuality: 0.85)
        // Reuse the same VisionOCRService the in-app manual scan uses — one OCR
        // implementation, not two. If recognition fails outright, still stage an
        // (empty-text) entry with the image attached so the capture isn't silently
        // lost; the "Edit" path lets the user fill everything in by hand.
        let text = (try? await VisionOCRService.recognizeText(from: image)) ?? ""
        stageAndNotify(rawText: text, imageData: jpeg)
        finish()
    }

    private func stageAndNotify(rawText: String, imageData: Data?) {
        let parsed = RegexParser.parse(rawText)
        let entry = PendingReceiptStore.add(
            rawText: rawText,
            parsed: parsed,
            source: .shareExtension,
            imageData: imageData
        )
        NotificationService.configure() // defensive — extension launch may skip app init
        NotificationService.scheduleReceiptNotification(for: entry)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
