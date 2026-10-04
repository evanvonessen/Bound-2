//
//  AchievementAccount.swift
//  Delta
//
//  Created by Natalie Pekker on 6/29/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

private extension AchievementAccount
{
    @Observable
    class AccountModel
    {
        var username: String
        
        var password: String = ""
        
        var authToken: String?
        
        var account: AchievementsManager.Account?
        
        var isHardcoreModeEnabled: Bool {
            didSet {
                Settings.features.retroAchievements.isHardcoreModeEnabled = self.isHardcoreModeEnabled
            }
        }
        
        init()
        {
            self.username = Keychain.shared.retroAchievementsUsername ?? ""
            self.authToken = Keychain.shared.retroAchievementsAuthToken
            self.account = AchievementsManager.shared.account
            self.isHardcoreModeEnabled = Settings.features.retroAchievements.isHardcoreModeEnabled
        }
    }
}

struct AchievementAccount: View
{
    @State
    private var accountModel = AccountModel()
    
    @State
    private var isSigningOut: Bool = false
    
    @State
    private var isShowingAuthError: Bool = false
    
    @State
    private var authError: Error?

    @State
    private var isSigningIn: Bool = false

    private var hasEnteredCredentials: Bool {
        !accountModel.username.isEmpty && !accountModel.password.isEmpty
    }

    private var info: some View {
        HStack(spacing: 12) {
            Image(systemName: "medal")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(6)
                .frame(width: 48, height: 48)
                .background(.indigo, in: RoundedRectangle(cornerRadius: 12))
            Text("Track your progress and achievements in retro games. [Learn more…](https://retroachievements.org/)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tint(Color(uiColor: .deltaPurple))
        }
    }
    
    private var signOutButton: some View {
        Button("Sign Out") {
            isSigningOut = true
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .foregroundStyle(.red)
        .confirmationDialog("Are you sure you'd like to sign out?", isPresented: $isSigningOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive, action: signOut)
        }
    }
    
    private var loggedOut: some View {
        List {
            Section {
                info
            }
            
            Section("Account") {
                TextField("Username", text: $accountModel.username)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $accountModel.password)
                    .onSubmit {
                        signIn()
                    }
            }
            
            Section {
                Button("Sign in") {
                    signIn()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!hasEnteredCredentials || isSigningIn)
                .foregroundStyle(Color(uiColor: .deltaPurple))
            }
        }
    }
    
    private func loggedIn(account: AchievementsManager.Account) -> some View {
        List {
            Section {
                info
            }
            
            Section("Account") {
                HStack {
                    AsyncImage(url: account.avatarURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ZStack {
                            Color(uiColor: .deltaLightPurple).opacity(0.3)
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text(account.username)
                            .font(.title3)
                            .bold()
                        Text(account.totalPoints, format: .number)
                            .font(.subheadline)
                    }
                }
            }
            
            Section {
                Toggle("Hardcore Mode", isOn: $accountModel.isHardcoreModeEnabled)
            } footer: {
                Text("Disables features that could provide an unfair advantage, such as cheats and save states.")
            }
            
            Section {
                signOutButton
            }
        }
    }
    
    private var loadingAccount: some View {
        List {
            Section {
                info
            }
            
            Section("Account") {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Account…")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                signOutButton
            }
        }
    }
    
    var body: some View {
        Group {
            if let account = accountModel.account
            {
                loggedIn(account: account)
            }
            else if accountModel.authToken != nil && authError == nil
            {
                loadingAccount
            }
            else
            {
                loggedOut
            }
        }
        .alert("Unable to Sign In", isPresented: $isShowingAuthError, presenting: authError) { error in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(verbatim: error.localizedDescription)
        }
        .navigationTitle("RetroAchievements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AchievementAccount
{
    @MainActor
    func signIn()
    {
        guard self.hasEnteredCredentials else { return }
        guard !self.isSigningIn else { return }
        self.isSigningIn = true

        Task<Void, Never> {
            defer { self.isSigningIn = false }

            do
            {
                let account = try await AchievementsManager.shared.authenticate(username: self.accountModel.username, password: self.accountModel.password)
                self.accountModel.account = account
                self.accountModel.authToken = Keychain.shared.retroAchievementsAuthToken
                self.accountModel.password = ""
            }
            catch
            {
                self.authError = error
                self.isShowingAuthError = true
            }
        }
    }
    
    func signOut()
    {
        AchievementsManager.shared.signOut()
        
        self.accountModel.username = ""
        self.accountModel.password = ""
        self.accountModel.authToken = nil
        self.accountModel.account = nil
    }
}


#Preview {
    AchievementAccount()
}
