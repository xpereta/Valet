//
//  SecureEnclave.swift
//  Valet
//
//  Created by Dan Federman on 9/19/17.
//  Copyright © 2017 Square, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation


@available(macOS 10.11, *)
public final class SecureEnclave {
        
    // MARK: Internal Methods
    
    /// - Parameter service: The service of the keychain slice we want to check if we can access.
    /// - Parameter identifier: A non-empty identifier that scopes the slice of keychain we want to access.
    /// - Returns: `true` if the keychain is accessible for reading and writing, `false` otherwise.
    /// - Note: Determined by writing a value to the keychain and then reading it back out.
    internal static func canAccessKeychain(with service: Service, identifier: Identifier) -> Bool {
        // To avoid prompting the user for Touch ID or passcode, create a Valet with our identifier and accessibility and ask it if it can access the keychain.
        let noPromptValet: Valet
        switch service {
        case .standard:
            noPromptValet = .valet(with: identifier, accessibility: .whenPasscodeSetThisDeviceOnly)
        case .sharedAccessGroup:
            noPromptValet = .sharedAccessGroupValet(with: identifier, accessibility: .whenPasscodeSetThisDeviceOnly)
        }
        
        return noPromptValet.canAccessKeychain()
    }
    
    /// - Parameter object: A Data value to be inserted into the keychain.
    /// - Parameter key: A Key that can be used to retrieve the `object` from the keychain.
    /// - Parameter options: A base query used to scope the calls in the keychain.
    internal static func set(object: Data, forKey key: String, options: [String : AnyHashable]) throws {
        // Remove the key before trying to set it. This will prevent us from calling SecItemUpdate on an item stored on the Secure Enclave, which would cause iOS to prompt the user for authentication.
        try? Keychain.removeObject(forKey: key, options: options)
        
        try Keychain.set(object: object, forKey: key, options: options)
    }
    
    /// - Parameter key: A Key used to retrieve the desired object from the keychain.
    /// - Parameter userPrompt: The prompt displayed to the user in Apple's Face ID, Touch ID, or passcode entry UI.
    /// - Parameter options: A base query used to scope the calls in the keychain.
    /// - Returns: The data currently stored in the keychain for the provided key.
    internal static func object(forKey key: String, withPrompt userPrompt: String, options: [String : AnyHashable]) throws -> Data {
        var secItemQuery = options
        if !userPrompt.isEmpty {
            secItemQuery[kSecUseOperationPrompt as String] = userPrompt
        }
        
        return try Keychain.object(forKey: key, options: secItemQuery)
    }
    
    /// - Parameter key: The key to look up in the keychain.
    /// - Parameter options: A base query used to scope the calls in the keychain.
    /// - Returns: `true` if a value has been set for the given key, `false` otherwise.
    internal static func containsObject(forKey key: String, options: [String : AnyHashable]) -> Bool {
        var secItemQuery = options
        secItemQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

        switch Keychain.containsObject(forKey: key, options: secItemQuery) {
        case errSecSuccess,
             errSecInteractionNotAllowed:
            return true
        default:
            return false
        }
    }
    
    /// - Parameter string: A String value to be inserted into the keychain.
    /// - Parameter key: A Key that can be used to retrieve the `string` from the keychain.
    /// - Parameter options: A base query used to scope the calls in the keychain.
    internal static func set(string: String, forKey key: String, options: [String : AnyHashable]) throws {
        // Remove the key before trying to set it. This will prevent us from calling SecItemUpdate on an item stored on the Secure Enclave, which would cause iOS to prompt the user for authentication.
        try? Keychain.removeObject(forKey: key, options: options)
        
        try Keychain.set(string: string, forKey: key, options: options)
    }
    
    /// - Parameter key: A Key used to retrieve the desired object from the keychain.
    /// - Parameter userPrompt: The prompt displayed to the user in Apple's Face ID, Touch ID, or passcode entry UI.
    /// - Parameter options: A base query used to scope the calls in the keychain.
    /// - Returns: The string currently stored in the keychain for the provided key. Returns `nil` if no string exists in the keychain for the specified key, or if the keychain is inaccessible.
    internal static func string(forKey key: String, withPrompt userPrompt: String, options: [String : AnyHashable]) throws -> String {
        var secItemQuery = options
        if !userPrompt.isEmpty {
            secItemQuery[kSecUseOperationPrompt as String] = userPrompt
        }

        return try Keychain.string(forKey: key, options: secItemQuery)
    }
}
