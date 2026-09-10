//
//  SignInFeature.swift
//  Miya
//

import ComposableArchitecture
import SwiftUI

/// The sign-in wall.
///
/// Providers are modelled as a list rather than a single hardcoded button: App
/// Store Guideline 4.8 requires an equivalent privacy-preserving option
/// alongside Google SSO, so Sign in with Apple is a likely addition, and this
/// shape makes it one more case rather than a rewrite.
@Reducer
struct SignInFeature {
    enum Provider: String, Equatable, Sendable, Identifiable, CaseIterable {
        case google

        var id: String { rawValue }
        var title: String {
            switch self {
            case .google: return "Continue with Google"
            }
        }

        var systemImage: String {
            switch self {
            case .google: return "globe"
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        /// True while the launch-time Keychain read is in flight, so the wall
        /// shows a spinner instead of flashing a sign-in button at someone who
        /// is already signed in.
        var isRestoring: Bool
        var authenticatingProvider: Provider?
        @Presents var alert: AlertState<Action.Alert>?

        var isBusy: Bool { isRestoring || authenticatingProvider != nil }

        init(isRestoring: Bool = false) {
            self.isRestoring = isRestoring
        }
    }

    enum Action: ViewAction {
        enum View {
            case providerTapped(Provider)
        }

        @CasePathable
        enum Delegate {
            /// Carries only the profile: tokens never enter an action, because
            /// TCA prints actions through CustomDump in `_printChanges`,
            /// `TestStore` diffs, and `reportIssue`.
            case signedIn(UserProfile)
        }

        enum Alert: Equatable {}

        case view(View)
        case signInResponse(Result<UserProfile, Error>)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
    }

    @Dependency(\.authClient) var authClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(.providerTapped(provider)):
                guard !state.isBusy else { return .none }
                state.authenticatingProvider = provider
                return .run { send in
                    await send(
                        .signInResponse(Result { try await authClient.signInWithGoogle() })
                    )
                }

            case let .signInResponse(.success(profile)):
                state.authenticatingProvider = nil
                return .send(.delegate(.signedIn(profile)))

            case let .signInResponse(.failure(error)):
                state.authenticatingProvider = nil
                // Dismissing the Google sheet is a decision, not a failure.
                // Alerting on it would scold the user for changing their mind.
                if case AuthError.canceled = error { return .none }
                state.alert = AlertState {
                    TextState("Couldn't sign in")
                } actions: {
                    ButtonState(role: .cancel) { TextState("OK") }
                } message: {
                    TextState(
                        (error as? LocalizedError)?.errorDescription
                            ?? "Something went wrong. Please try again."
                    )
                }
                return .none

            case .alert, .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

@ViewAction(for: SignInFeature.self)
struct SignInView: View {
    @Bindable var store: StoreOf<SignInFeature>

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Miya")
                    .font(.largeTitle)
                Text("Your images and audio, everywhere.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if store.isRestoring {
                ProgressView()
                    .accessibilityLabel("Restoring your session")
            } else {
                VStack(spacing: 12) {
                    ForEach(SignInFeature.Provider.allCases) { provider in
                        providerButton(provider)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .background(Color(.systemBackground))
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    private func providerButton(_ provider: SignInFeature.Provider) -> some View {
        Button {
            send(.providerTapped(provider))
        } label: {
            HStack(spacing: 10) {
                if store.authenticatingProvider == provider {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: provider.systemImage)
                }
                Text(provider.title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            // 52pt clears the 44pt HIG minimum touch target with room for
            // Dynamic Type to grow the label.
            .frame(minHeight: 52)
            .foregroundStyle(Color(.systemBackground))
            .background(Color(.label), in: .rect(cornerRadius: 12))
        }
        .disabled(store.isBusy)
        .accessibilityLabel(provider.title)
        .accessibilityHint("Opens a secure Google sign-in page")
    }
}

#Preview {
    SignInView(
        store: Store(initialState: SignInFeature.State()) {
            SignInFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}
