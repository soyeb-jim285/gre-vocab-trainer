import GRECore
import SwiftUI

/// Lists only models that can honour a strict JSON schema -- anything else would
/// return prose and fail at grade time.
struct ModelPickerView: View {
    let title: String
    @Binding var selection: String

    @State private var models: [OpenRouterModel] = []
    @State private var error: String?
    @State private var search = ""

    private var visible: [OpenRouterModel] {
        let matches = search.isEmpty
            ? models
            : models.filter { $0.name.localizedCaseInsensitiveContains(search)
                           || $0.id.localizedCaseInsensitiveContains(search) }
        return matches.sorted { $0.pricing.promptPerToken < $1.pricing.promptPerToken }
    }

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(Theme.negative)
            }
            ForEach(visible) { model in
                Button {
                    selection = model.id
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name).foregroundStyle(Theme.primaryText)
                            Text(priceLabel(model))
                                .font(.footnote)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Spacer()
                        if model.id == selection {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(title)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .task {
            guard models.isEmpty else { return }
            do {
                // Unauthenticated on purpose: the catalogue is public, so the
                // picker works before a key has been pasted.
                models = try await OpenRouterClient(apiKey: "").availableModels()
            } catch {
                self.error = (error as? OpenRouterError)?.description ?? error.localizedDescription
            }
        }
    }

    private func priceLabel(_ model: OpenRouterModel) -> String {
        guard model.pricing.promptPerToken > 0 || model.pricing.completionPerToken > 0 else {
            return "Free · \(context(model))"
        }
        let inPrice = model.pricing.promptPerToken * 1_000_000
        let outPrice = model.pricing.completionPerToken * 1_000_000
        return String(format: "$%.2f in · $%.2f out per 1M · %@", inPrice, outPrice, context(model))
    }

    private func context(_ model: OpenRouterModel) -> String {
        model.contextLength >= 1000 ? "\(model.contextLength / 1000)k ctx" : "\(model.contextLength) ctx"
    }
}
