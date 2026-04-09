//
//  ConnectionsSettingsView.swift
//  Lokal
//
//  OAuth connection management screen. Lets the user sign in / out of GitHub,
//  Google Drive, OneDrive, plus configure the client IDs the providers require.
//

import SwiftUI

struct ConnectionsSettingsView: View {
    @Environment(ConnectionStore.self) private var store

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Eigene OAuth-App nötig", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Lokalo betreibt kein Backend und keine zentrale OAuth-App. Damit Lokalo nicht zwischen dir und deinem Provider sitzt, registrierst du bei jedem Provider deine eigene OAuth-App und trägst die Client-ID hier ein. Bei einem Provider ohne Client-ID erscheint statt „Verbinden\" der Button „Konfigurieren\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(OAuthProvider.allCases, id: \.self) { provider in
                    providerRow(provider)
                }
            } footer: {
                Text("Lokalo speichert Tokens nur in deinem iOS Keychain (geräteexklusiv, kein iCloud-Sync). Read-Only Scopes — Lokalo schreibt nirgendwo zurück.")
            }

            if let pending = store.pendingDeviceFlow {
                Section("GitHub-Anmeldung läuft") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Öffne diese Adresse im Browser:")
                            .font(.callout)
                        if let url = URL(string: pending.verificationURL) {
                            Link(pending.verificationURL, destination: url)
                                .font(.callout.weight(.medium))
                        } else {
                            Text(pending.verificationURL)
                                .font(.callout.weight(.medium))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                        Text("Und gib diesen Code ein:")
                            .font(.callout)
                        Text(pending.userCode)
                            .font(.title.weight(.semibold).monospaced())
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.vertical, 4)
                }
            }

            if let err = store.lastError {
                Section("Letzter Fehler") {
                    Text(err).font(.callout).foregroundStyle(.red)
                }
            }

            Section {
                NavigationLink {
                    OAuthProviderConfigView()
                } label: {
                    Label("Provider-IDs konfigurieren", systemImage: "key")
                }
            } footer: {
                Text("Du musst bei jedem Provider eine eigene App registrieren und die Client-ID hier eintragen, bevor du dich anmelden kannst.")
            }
        }
        .navigationTitle("Verbindungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func providerRow(_ provider: OAuthProvider) -> some View {
        let configured = !clientID(for: provider).isEmpty
        HStack(spacing: 12) {
            Image(systemName: provider.iconName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).font(.subheadline.weight(.medium))
                if let conn = store.connection(for: provider) {
                    Text(conn.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if configured {
                    Text("Bereit zum Verbinden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Client-ID erforderlich")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if store.isConnected(provider) {
                Button("Trennen", role: .destructive) {
                    store.signOut(provider)
                }
                .buttonStyle(.bordered)
            } else if configured {
                Button("Verbinden") {
                    Task { await store.signIn(provider) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                NavigationLink {
                    OAuthProviderConfigView()
                } label: {
                    Text("Konfigurieren")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    /// Returns the currently-stored client ID for `provider`, or `""` if the
    /// user hasn't configured one yet. Used to switch the row between the
    /// "Verbinden" and "Konfigurieren" states.
    private func clientID(for provider: OAuthProvider) -> String {
        switch provider {
        case .github: return GitHubOAuth.clientID
        case .googleDrive: return GoogleDriveOAuth.clientID
        case .onedrive: return OneDriveOAuth.clientID
        }
    }
}

// MARK: - Client-ID configuration

struct OAuthProviderConfigView: View {
    @State private var githubClientID = UserDefaults.standard.string(forKey: "Lokal.github.clientID") ?? ""
    @State private var googleClientID = UserDefaults.standard.string(forKey: "Lokal.googleDrive.clientID") ?? ""
    @State private var onedriveClientID = UserDefaults.standard.string(forKey: "Lokal.oneDrive.clientID") ?? ""

    var body: some View {
        Form {
            Section("GitHub") {
                TextField("OAuth App / GitHub App Client-ID", text: $githubClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Erstelle eine OAuth App auf github.com/settings/developers, Callback `com.slavkoklincov.lokal://oauth-callback`, Scope: `public_repo read:user`. Lokalo nutzt den Device-Flow, also kein Client-Secret nötig.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Google Drive") {
                TextField("Google iOS Client-ID", text: $googleClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("In console.cloud.google.com → APIs & Services → Credentials → iOS Client ID. Bundle: `com.slavkoklincov.lokal`. Scope: `drive.readonly`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("OneDrive / Microsoft Graph") {
                TextField("Microsoft App Client-ID (UUID)", text: $onedriveClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("In portal.azure.com → App registrations → \"Mobile and desktop\" Platform → Redirect URI `com.slavkoklincov.lokal://oauth-callback`. Scopes: `Files.Read offline_access User.Read`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Speichern") { save() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Provider-IDs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        UserDefaults.standard.set(githubClientID.trimmingCharacters(in: .whitespaces), forKey: "Lokal.github.clientID")
        UserDefaults.standard.set(googleClientID.trimmingCharacters(in: .whitespaces), forKey: "Lokal.googleDrive.clientID")
        UserDefaults.standard.set(onedriveClientID.trimmingCharacters(in: .whitespaces), forKey: "Lokal.oneDrive.clientID")
    }
}
