//
//  ShareViewController.swift
//  Monee
//
//  Handles shared plain text and shared images identically: extract text (directly for
//  text shares, via VisionOCRService for image shares), then stage it through
//  ReceiptCaptureService — the exact same parsing rule the Action Button flow uses.
//  Unlike the old version, nothing is saved until the user confirms Income/Expense on
//  ShareConfirmationView. A failed/empty OCR result on an image share behaves the same
//  as "no amount found": nothing is staged, and the photo itself is not retained
//  anywhere after this runs.
//
//  ⚠️ Requires this file's Info.plist NSExtensionActivationRule to accept BOTH
//  public.plain-text and public.image (see ShareExtension/Info.plist).
//
//  ⚠️ Target membership: this file needs RegexParser.swift, Transaction.swift,
//  AppGroup.swift, VisionOCRServiceError.swift, CurrencyFormat.swift,
//  NotificationService.swift, ReceiptCaptureService.swift, and
//  ShareConfirmationView.swift all added to the ShareExtension target in Xcode's File
//  Inspector.
//
//  ⚠️ UI PLACEHOLDER — bare loading/confirmation states, not a designed screen.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Reading receipt…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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

        stageAndConfirm(rawText: text)
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
        stageAndConfirm(rawText: text)
    }

    private func stageAndConfirm(rawText: String) {
        NotificationService.configure() // defensive — extension launch may skip app init

        switch ReceiptCaptureService.stage(rawText: rawText) {
        case .amountNotFound:
            finish()
        case .needsConfirmation(let parsed):
            DispatchQueue.main.async { [weak self] in
                self?.presentConfirmation(for: parsed)
            }
        }
    }

    private func presentConfirmation(for parsed: ParsedReceiptData) {
        loadingLabel.removeFromSuperview()

        let confirmationView = ShareConfirmationView(parsed: parsed) { [weak self] category in
            ReceiptCaptureService.save(
                title: parsed.suggestedTitle,
                amount: parsed.amount ?? 0,
                date: parsed.date ?? Date(),
                category: category,
                rawKeyword: parsed.keyword
            )
            self?.finish()
        }

        let hosting = UIHostingController(rootView: confirmationView)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
