//
//  ReceiptConfirmationView.swift
//  Monee
//
//  Manual in-app capture only: PhotosPicker -> live Vision OCR right here. The old staged-
//  entry review path (Action Button / Share Extension low-confidence captures reviewed via
//  a PendingReceiptStore-backed pendingEntryID) is retired — those flows now save directly
//  via ReceiptCaptureService and, if the user needs to fix something, route to
//  QuickEntryFormView's edit mode instead (see NotificationDelegate + Task 4).
//
//  ⚠️ UI PLACEHOLDER: everything here is functional-only styling. UI team — restyle freely;
//  ScannerViewModel and QuickEntryViewModel are the only real contracts this depends on.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ReceiptConfirmationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scannerViewModel = ScannerViewModel()
    @StateObject private var entryViewModel = QuickEntryViewModel()

    @State private var selectedPhoto: PhotosPickerItem?

    /// Manual in-app capture only — PhotosPicker -> live OCR right here.
    var pendingImage: UIImage? = nil

    private var scanFailedBinding: Binding<Bool> {
        Binding(
            get: { scannerViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { scannerViewModel.errorMessage = nil }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerViewModel.isProcessing {
                    ProcessingView()
                } else if scannerViewModel.parsedData != nil {
                    ConfirmationForm(
                        image: scannerViewModel.capturedImage,
                        isComplete: scannerViewModel.parsedData?.isComplete ?? true,
                        viewModel: entryViewModel
                    )
                } else if pendingImage == nil {
                    CaptureChooserView(selectedPhoto: $selectedPhoto)
                } else {
                    // pendingImage is set but processing hasn't started yet — .task below
                    // kicks it off; this is a brief transitional frame.
                    ProcessingView()
                }
            }
            .navigationTitle("Confirm Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if scannerViewModel.parsedData != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Retake") {
                            scannerViewModel.reset()
                            entryViewModel.reset()
                            selectedPhoto = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!entryViewModel.canSave)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadAndProcess(newItem) }
            }
            .task {
                if let pendingImage, scannerViewModel.parsedData == nil, !scannerViewModel.isProcessing {
                    await scannerViewModel.processImage(pendingImage)
                    applyParsedDataIfAvailable()
                }
            }
            .alert("Scan Failed", isPresented: scanFailedBinding) {
                Button("OK") { scannerViewModel.reset() }
            } message: {
                Text(scannerViewModel.errorMessage ?? "")
            }
        }
    }

    private func loadAndProcess(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        await scannerViewModel.processImage(image)
        applyParsedDataIfAvailable()
    }

    private func applyParsedDataIfAvailable() {
        guard let parsed = scannerViewModel.parsedData else { return }
        entryViewModel.title = parsed.suggestedTitle
        entryViewModel.amount = parsed.amount
        entryViewModel.date = parsed.date ?? .now
        // isIncome must be set BEFORE category — QuickEntryViewModel resets category to
        // .unassigned as a side effect of isIncome's didSet, so category has to be the
        // last write to actually stick.
        entryViewModel.isIncome = parsed.isIncome
        entryViewModel.category = parsed.isIncome ? .income : parsed.category
        entryViewModel.source = .ocr
        entryViewModel.rawKeyword = parsed.keyword
    }

    private func save() {
        if entryViewModel.save(using: modelContext) {
            dismiss()
        }
    }
}

// MARK: - Capture

private struct CaptureChooserView: View {
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Scan a Receipt")
                .font(.title3.weight(.semibold))
            Text("Pick a photo of a receipt and we'll pull out the amount, date, and category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading receipt…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Confirmation

private struct ConfirmationForm: View {
    let image: UIImage?
    let isComplete: Bool
    @ObservedObject var viewModel: QuickEntryViewModel

    var body: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if !isComplete {
                Section {
                    Label(
                        "We couldn't confidently read every field — double-check the amount and date below.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Type", selection: $viewModel.isIncome) {
                    Text("Expense").tag(false)
                    Text("Income").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Details") {
                TextField("What was it for?", text: $viewModel.title)
                TextField("Amount", value: $viewModel.amount, format: FloatingPointFormatStyle<Double>.Currency.idr)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
            }

            if !viewModel.isIncome {
                Section("Category") {
                    Picker("Category", selection: $viewModel.category) {
                        ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            if let error = viewModel.validationError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

#Preview {
    ReceiptConfirmationView()
        .modelContainer(SwiftDataService.makePreviewContainer())
}
