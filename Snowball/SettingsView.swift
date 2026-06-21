import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("snowball.theme") private var themeRaw = AppTheme.system.rawValue

    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var restoreMessage: String?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Snowball \(v)"
    }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                strategySection
                appearanceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .tint(Color.snowAccent)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("Erase All Data?", isPresented: $showDeleteConfirm) {
                Button("Erase", role: .destructive) {
                    appModel.deleteAllData()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases all your debts and payment history on this device. This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                HStack {
                    Label("Snowball Pro", systemImage: "snowflake")
                    Spacer()
                    Text("Unlocked").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Haptics.tap(); showPaywall = true
                } label: {
                    HStack {
                        Label("Unlock Snowball Pro", systemImage: "snowflake")
                        Spacer()
                        Text(store.displayPrice).foregroundStyle(.secondary)
                    }
                }
                Button("Restore Purchase") {
                    Task {
                        await store.restore()
                        restoreMessage = store.isPro ? "Restored." : "No previous purchase found."
                    }
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } footer: {
            if !store.isPro {
                Text("One-time purchase. Unlimited debts, the avalanche comparison, payoff-date projection and sharing.")
            }
        }
    }

    private var strategySection: some View {
        Section {
            Picker("Method", selection: Binding(
                get: { appModel.strategy },
                set: { appModel.strategy = $0 }
            )) {
                ForEach(PayoffStrategy.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Payoff method")
        } footer: {
            Text(appModel.strategy.blurb)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeRaw) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        Section {
            Link("Privacy Policy", destination: URL(string: "https://shimondeitel.github.io/snowball-site/privacy.html")!)
            Button("Erase All Data", role: .destructive) { showDeleteConfirm = true }
        } footer: {
            Text(version).frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
        }
    }
}
