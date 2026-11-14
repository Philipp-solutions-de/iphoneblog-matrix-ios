import AuthenticationServices
import SwiftUI

/// The first screen: the logo, one sentence, one button. No server choice.
struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var username = ""
    @State private var password = ""

    private var isBusy: Bool {
        if case .signingIn = model.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: Theme.Size.signInLogo, height: Theme.Size.signInLogo)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Der iphoneblog-Chat")
                    .font(Theme.Font.signInTitle)
                    .foregroundStyle(Theme.ink)
                Text("Für alle, die mitlesen und mitreden.")
                    .font(.system(size: 16.5))
                    .foregroundStyle(Theme.ink2)
            }
            .multilineTextAlignment(.center)
            Spacer()

            if model.offersPasswordLogin {
                passwordForm
            } else {
                Button(action: signInWithBlog) {
                    Text("Mit iphoneblog.de anmelden")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: Theme.Size.corner + 1))
                .disabled(isBusy)
                .accessibilityIdentifier("signIn.blog")
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.coral)
                    .multilineTextAlignment(.center)
            }

            Text("Du nutzt dein Konto vom Blog. Wer Mitglied bei #one ist, kann schreiben. Auf jedem weiteren Gerät genauso, ohne Code.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .overlay {
            if isBusy { ProgressView().controlSize(.large) }
        }
    }

    /// For test servers without the blog sign-in.
    private var passwordForm: some View {
        VStack(spacing: 12) {
            TextField("Benutzername", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("signIn.username")
            SecureField("Passwort", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("signIn.password")
            Button("Anmelden") {
                Task { await model.signIn(username: username, password: password) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty || isBusy)
            .accessibilityIdentifier("signIn.submit")
        }
        .textFieldStyle(.roundedBorder)
    }

    private func signInWithBlog() {
        model.errorMessage = nil
        Task {
            do {
                let url = try await model.oauthLoginURL()
                // Not ephemeral: someone signed in to the blog in Safari taps once and is in.
                let callback = try await webAuthenticationSession.authenticate(
                    using: url,
                    callbackURLScheme: Brand.oauthRedirectScheme,
                    preferredBrowserSession: .shared)
                await model.completeOAuth(callbackURL: callback)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                model.cancelOAuth()
            } catch {
                model.errorMessage = String(localized: "Der Anmeldedienst ist gerade nicht erreichbar.")
            }
        }
    }
}
