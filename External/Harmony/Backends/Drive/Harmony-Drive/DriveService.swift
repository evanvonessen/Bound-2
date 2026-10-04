//
//  DriveService.swift
//  Harmony-Drive
//
//  Created by Riley Testut on 1/25/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import Harmony

import GTMSessionFetcher
import GoogleSignIn
import GoogleAPIClientForREST

let fileQueryFields = "id, mimeType, name, headRevisionId, modifiedTime, appProperties, size"
let appDataFolder = "appDataFolder"

private let kGoogleHTTPErrorDomain = "com.google.HTTPStatus"

public class DriveService: NSObject, Service
{
    public static let shared = DriveService()

    public let localizedName = NSLocalizedString("Google Drive", comment: "")
    public let identifier = "com.rileytestut.Harmony.Drive"

    public var clientID: String?

    let service = GTLRDriveService()
    
    private var authorizationCompletionHandlers = [(Result<Account, AuthenticationError>) -> Void]()
    
    private weak var presentingViewController: UIViewController?

    private override init()
    {
        super.init()
        
        self.service.shouldFetchNextPages = true
    }
}

public extension DriveService
{
    func authenticate(withPresentingViewController viewController: UIViewController, completionHandler: @escaping (Result<Account, AuthenticationError>) -> Void)
    {
        self.authorizationCompletionHandlers.append(completionHandler)
        
        do
        {
            guard let clientID else { throw AuthenticationError.invalidClientID }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.signIn(with: config, presenting: viewController, hint: nil, additionalScopes: [kGTLRAuthScopeDriveAppdata]) { user, error in
                self.didSignIn(user: user, error: error)
            }
        }
        catch
        {
            self.didSignIn(user: nil, error: error)
        }
    }

    func authenticateInBackground(completionHandler: @escaping (Result<Account, AuthenticationError>) -> Void)
    {
        self.authorizationCompletionHandlers.append(completionHandler)
        
        // Must run on main thread.
        DispatchQueue.main.async {
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                self.didSignIn(user: user, error: error)
            }
        }
    }
    
    func deauthenticate(completionHandler: @escaping (Result<Void, DeauthenticationError>) -> Void)
    {
        GIDSignIn.sharedInstance.signOut()
        completionHandler(.success)
    }
}

extension DriveService
{
    func process<T>(_ result: Result<T, Error>) throws -> T
    {
        do
        {
            do
            {
                let value = try result.get()
                return value
            }
            catch let error where error._domain == kGIDSignInErrorDomain
            {
                switch error._code
                {
                case GIDSignInError.canceled.rawValue: throw GeneralError.cancelled
                case GIDSignInError.hasNoAuthInKeychain.rawValue: throw AuthenticationError.noSavedCredentials
                default: throw ServiceError(error)
                }
            }
            catch let error where error._domain == kGTLRErrorObjectDomain || error._domain == kGoogleHTTPErrorDomain
            {
                switch error._code
                {
                case 400, 401: throw AuthenticationError.tokenExpired
                case 403: throw ServiceError.rateLimitExceeded
                case 404: throw ServiceError.itemDoesNotExist
                default: throw ServiceError(error)
                }
            }
            catch
            {
                throw ServiceError(error)
            }
        }
        catch let error as HarmonyError
        {
            throw error
        }
        catch
        {
            assertionFailure("Non-HarmonyError thrown from DriveService.process(_:)")
            throw error
        }
    }
}

private extension DriveService
{
    func didSignIn(user: GIDGoogleUser?, error: Error?)
    {
        let result: Result<Account, AuthenticationError>
        
        do
        {
            let user = try self.process(Result(user, error))
            
            // Should always be non-nil if sign-in succeeded according to documentation, but throw fallback error just in case.
            guard let profile = user.profile else { throw AuthenticationError.other(GeneralError.unknown) }
            
            self.service.authorizer = user.authentication.fetcherAuthorizer()
            
            let account = Account(name: profile.name, emailAddress: profile.email)
            result = .success(account)
        }
        catch
        {
            result = .failure(AuthenticationError(error))
        }
        
        // Reset self.authorizationCompletionHandlers _before_ calling all the completion handlers.
        // This stops us from accidentally calling completion handlers twice in some instances.
        let completionHandlers = self.authorizationCompletionHandlers
        self.authorizationCompletionHandlers.removeAll()
        
        completionHandlers.forEach { $0(result) }
    }
}
