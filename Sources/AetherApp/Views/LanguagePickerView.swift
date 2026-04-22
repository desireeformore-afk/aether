import SwiftUI

struct LanguagePickerView: View {
    @AppStorage("preferredLanguage") var preferredLanguage: String = "pl"
    @AppStorage("preferredCountry") var preferredCountry: String = "PL"

    var onDismiss: (() -> Void)?

    private let languages: [(code: String, label: String)] = [
        ("pl", "🇵🇱 Polski"),
        ("en", "🇺🇸 English"),
        ("tr", "🇹🇷 Türkçe"),
        ("de", "🇩🇪 Deutsch"),
        ("fr", "🇫🇷 Français"),
        ("es", "🇪🇸 Español"),
        ("ar", "🇸🇦 العربية"),
    ]

    private let countries: [(code: String, label: String)] = [
        ("PL", "🇵🇱 Polska"),
        ("US", "🇺🇸 United States"),
        ("TR", "🇹🇷 Türkiye"),
        ("DE", "🇩🇪 Deutschland"),
        ("FR", "🇫🇷 France"),
        ("ES", "🇪🇸 España"),
        ("AR", "🇸🇦 Arabia"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferencje")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("", selection: $preferredLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Kraj")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("", selection: $preferredCountry) {
                    ForEach(countries, id: \.code) { country in
                        Text(country.label).tag(country.code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
