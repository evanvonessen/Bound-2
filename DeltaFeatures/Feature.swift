//
//  Feature.swift
//  Delta
//
//  Created by Riley Testut on 4/5/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI
import Combine

public struct EmptyOptions
{
    public init() {}
}

// When Disabled == Bool, we interpret that to mean the Feature is an EnabledFeature (i.e. can be enabled/disabled).
extension Feature: EnabledFeature where Disabled == Bool {}

@propertyWrapper @dynamicMemberLookup
public final class Feature<Options, Disabled>: _AnyFeature
{
    public let name: LocalizedStringKey
    public let description: LocalizedStringKey?
    public let detailedDescription: LocalizedStringKey?
    
    // Assigned to property name.
    public internal(set) var key: String = ""
    
    // Used for `SettingsUserInfoKey.name` value in .settingsDidChange notification.
    public var settingsKey: SettingsName {
        return SettingsName(rawValue: self.key)
    }
    
    public var wrappedValue: some Feature {
        return self
    }
    
    private var options: Options
    
    public init(name: LocalizedStringKey, description: LocalizedStringKey? = nil, detailedDescription: LocalizedStringKey? = nil, options: Options = EmptyOptions()) where Disabled == Bool
    {
        self.name = name
        self.description = description
        self.detailedDescription = detailedDescription
        self.options = options
        
        self.prepareOptions()
    }
    
    // Always-enabled Features must provide Options (otherwise we should just remove the Feature entirely).
    public init(enabledWith options: Options) where Disabled == Never
    {
        self.name = ""
        self.description = nil
        self.detailedDescription = nil
        self.options = options
        
        self.prepareOptions()
    }
    
    // Use `KeyPath` instead of `WritableKeyPath` as parameter to allow accessing projected property wrappers.
    public subscript<T>(dynamicMember keyPath: KeyPath<Options, T>) -> T {
        get {
            options[keyPath: keyPath]
        }
        set {
            guard let writableKeyPath = keyPath as? WritableKeyPath<Options, T> else { return }
            options[keyPath: writableKeyPath] = newValue
        }
    }
}

public extension Feature
{
    var allOptions: [any AnyOption] {
        let features = Mirror(reflecting: self.options).children.compactMap { (child) -> (any AnyOption)? in
            let feature = child.value as? (any AnyOption)
            return feature
        }
        return features
    }
}

private extension Feature
{
    func prepareOptions()
    {
        // Update option keys + feature
        for case (let key?, let option as any _AnyOption) in Mirror(reflecting: self.options).children
        {
            // Remove leading underscore.
            let sanitizedKey = key.dropFirst()
            option.key = String(sanitizedKey)
            option.feature = self
        }
    }
}
