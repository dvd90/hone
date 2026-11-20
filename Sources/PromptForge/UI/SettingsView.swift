import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ProviderSettingsView().tabItem { Label("Provider", systemImage: "bolt.horizontal") }
            ActionsSettingsView().tabItem { Label("Actions", systemImage: "square.grid.2x2") }
            ShortcutSettingsView().tabItem { Label("Shortcut", systemImage: "keyboard") }
        }
        .frame(width: 600, height: 520)
        .tint(Theme.accent)
    }
}

// MARK: - Provider

struct ProviderSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var anthropicKey = Keychain.load(.anthropic) ?? ""
    @State private var openAIKey = Keychain.load(.openAI) ?? ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Picker("Use", selection: $state.providerSettings.kind) {
                    ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Subscriptions run through the official CLI you're already logged into. No API key needed, and usage counts against your plan.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }

            Section(state.providerSettings.kind.shortLabel) { details }

            Section {
                HStack {
                    Button("Test connection") {
                        Task {
                            testing = true
                            testResult = nil
                            testResult = await state.testConnection()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let t = testResult {
                        Text(t).font(.caption).foregroundStyle(.primary).lineLimit(3).textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: state.providerSettings.kind) { testResult = nil }
    }

    @ViewBuilder private var details: some View {
        switch state.providerSettings.kind {
        case .claudeCode:
            CLIStatusRow(name: "claude", loginHint: "Run `claude` in Terminal once and sign in with your Claude Pro/Max account.")
            TextField("Model", text: $state.providerSettings.claudeCodeModel, prompt: Text("default · or sonnet, opus, haiku"))
        case .codex:
            CLIStatusRow(name: "codex", loginHint: "Run `codex login` in Terminal and sign in with ChatGPT. Note: Codex doesn't stream, so results appear all at once.")
            TextField("Model", text: $state.providerSettings.codexModel, prompt: Text("default"))
        case .geminiCLI:
            CLIStatusRow(name: "gemini", loginHint: "Run `gemini` in Terminal once and choose “Login with Google”.")
            TextField("Model", text: $state.providerSettings.geminiModel, prompt: Text("default"))
        case .anthropic:
            SecureField("API key", text: $anthropicKey)
                .onChange(of: anthropicKey) { Keychain.save(anthropicKey, for: .anthropic) }
            Picker("Model", selection: $state.providerSettings.anthropicModel) {
                ForEach(ModelPreset.all) { Text($0.label).tag($0.id) }
                if !ModelPreset.all.contains(where: { $0.id == state.providerSettings.anthropicModel }) {
                    Text(state.providerSettings.anthropicModel).tag(state.providerSettings.anthropicModel)
                }
            }
            TextField("Custom model ID", text: $state.providerSettings.anthropicModel)
            Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
        case .openAICompatible:
            HStack {
                ForEach(OpenAICompatibleProvider.presets, id: \.url) { p in
                    Button(p.name) { state.providerSettings.openAIBaseURL = p.url }.controlSize(.small)
                }
            }
            TextField("Base URL", text: $state.providerSettings.openAIBaseURL)
            SecureField("API key (blank for local servers)", text: $openAIKey)
                .onChange(of: openAIKey) { Keychain.save(openAIKey, for: .openAI) }
            TextField("Model ID", text: $state.providerSettings.openAIModel, prompt: Text("required, e.g. the model name your provider lists"))
        }
    }
}

struct CLIStatusRow: View {
    let name: String
    let loginHint: String
    @State private var path: String?
    @State private var checked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !checked {
                    ProgressView().controlSize(.small)
                    Text("Looking for `\(name)`…")
                } else if let path {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                } else {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text("`\(name)` was not found on your PATH")
                }
            }
            Text(.init(loginHint)).font(.caption).foregroundStyle(Theme.muted)
        }
        .task(id: name) {
            checked = false
            path = await ShellEnvironment.shared.locate(name)?.path
            checked = true
        }
    }
}

// MARK: - Actions

struct ActionsSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: AIAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section("Built-in") {
                    ForEach(AIAction.builtIns) { a in row(a) }
                }
                Section("Custom") {
                    if state.customActions.isEmpty {
                        Text("Add your own actions: any instruction you want to apply to selected text.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(state.customActions) { a in row(a) }
                }
            }
            HStack {
                Button { editing = state.addCustomAction() } label: { Label("Add custom action", systemImage: "plus") }
                Spacer()
                Text("The first 9 visible actions get number shortcuts in the quick panel.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(12)
        }
        .sheet(item: $editing) { a in
            ActionEditor(action: a) { updated in
                state.updateCustomAction(updated)
                editing = nil
            } onDelete: {
                state.deleteCustomAction(a)
                editing = nil
            }
        }
    }

    private func row(_ a: AIAction) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { !state.hiddenActionIDs.contains(a.id) },
                set: { on in if on { state.hiddenActionIDs.remove(a.id) } else { state.hiddenActionIDs.insert(a.id) } })) {
                Label(a.name, systemImage: a.icon)
            }
            Spacer()
            Text(a.instruction).font(.caption).foregroundStyle(Theme.muted).lineLimit(1).frame(maxWidth: 260, alignment: .trailing)
            if !a.builtIn {
                Button("Edit") { editing = a }.controlSize(.small)
            }
        }
    }
}

struct ActionEditor: View {
    @State var action: AIAction
    let onSave: (AIAction) -> Void
    let onDelete: () -> Void

    private let icons = ["sparkles", "text.quote", "envelope", "bubble.left", "doc.text", "tag", "hammer",
                         "chart.bar", "megaphone", "graduationcap", "hare", "theatermasks"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom action").font(.headline)
            TextField("Name", text: $action.name).textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                ForEach(icons, id: \.self) { i in
                    Button { action.icon = i } label: { Image(systemName: i).frame(width: 22, height: 22) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(action.icon == i ? .accentColor : .secondary)
                }
            }
            Text("Instruction: what should happen to the selected text?").font(.subheadline)
            TextEditor(text: $action.instruction)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 120)
                .field()
            Text("Example: “Turn this into a LinkedIn post with a strong hook, max 120 words.”")
                .font(.caption).foregroundStyle(Theme.muted)
            HStack {
                Button("Delete", role: .destructive, action: onDelete)
                Spacer()
                Button("Save") { onSave(action) }
                    .capsuleButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
                    .disabled(action.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              action.instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

// MARK: - Shortcut & permissions

struct ShortcutSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var trusted = SelectionBridge.isTrusted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker("Quick actions hotkey", selection: $state.hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Select text in any app, press the hotkey, pick an action, then Replace (⏎) or Copy.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }

            Section("Accessibility permission") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Granted: Hone can read your selection and paste results back."
                                 : "Needed to read the selected text and to paste results back (Replace). Without it, the hotkey uses your clipboard instead.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !trusted {
                    HStack {
                        Button("Request access") { SelectionBridge.requestTrust() }
                        Button("Open System Settings") { SelectionBridge.openAccessibilitySettings() }
                    }
                }
            }

            Section("Also available") {
                Text("Right-click selected text → Services → **Hone: Improve Prompt** or **Hone: Quick Actions**. You can give these their own shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = SelectionBridge.isTrusted }
    }
}
