//
//  AddRestaurantSheet.swift
//  NivyBar
//

import SwiftUI

struct AddRestaurantSheet: View {
    @EnvironmentObject private var store: UserRestaurantStore
    @Environment(\.dismiss) private var dismiss

    var onAdded: (UUID) -> Void

    @State private var urlText       = ""
    @State private var isAnalyzing   = false
    @State private var urlError      = false
    @State private var aiError: String? = nil

    private var isValidURL: Bool {
        guard let u = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else { return false }
        return u.scheme == "http" || u.scheme == "https"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Add Restaurant")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                LabeledContent("URL *") {
                    TextField("", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: urlText) { _, _ in urlError = false; aiError = nil }
                }
                if urlError {
                    Text("Please enter a valid https:// URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            if let err = aiError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                if isAnalyzing {
                    ProgressView("Analyzing with AI…")
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                }
                Button {
                    Task { await addAndAnalyze() }
                } label: {
                    Label(isAnalyzing ? "Analyzing…" : "Add & Analyze", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440)
    }

    // MARK: - Action

    private func addAndAnalyze() async {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespaces)
        guard isValidURL else { urlError = true; return }

        isAnalyzing = true
        aiError = nil

        // Start with a placeholder name from the URL host
        let fallbackName = URL(string: trimmedURL)?.host ?? trimmedURL
        let restaurant = UserRestaurant(
            url: trimmedURL,
            displayName: fallbackName
        )
        store.add(restaurant)

        // Fetch the added restaurant to preserve the assigned displayOrder
        guard var added = store.restaurants.first(where: { $0.id == restaurant.id }) else { return }
        let newID = added.id

        // Run AI analysis
        let result = await AIRecipeGenerator.shared.generateRecipe(for: trimmedURL)
        switch result {
        case .success(let recipe):
            // Update name/location from AI extraction if available
            if let extractedName = recipe.extractedName?.trimmingCharacters(in: .whitespaces),
               !extractedName.isEmpty {
                added.displayName = extractedName
            }
            if let extractedLocation = recipe.extractedLocation?.trimmingCharacters(in: .whitespaces),
               !extractedLocation.isEmpty {
                added.zone = extractedLocation
            }
            if let colorHex = recipe.suggestedColorHex {
                added.accentColorHex = colorHex
            }
            if added.displayName != fallbackName || added.zone != nil {
                store.update(added)
            }
            store.updateRecipe(recipe, for: newID)
            dismiss()
            onAdded(newID)
        case .failure(let err):
            // Keep the restaurant (no recipe) but surface the error
            aiError = err.errorDescription ?? "AI analysis failed."
            isAnalyzing = false
            dismiss()
            onAdded(newID)
        }
    }
}
