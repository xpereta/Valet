//
//  SinglePromptSecureEnclaveValet.swift
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

#if os(iOS) || os(macOS)

import LocalAuthentication
import Foundation


/// Reads and writes keychain elements that are stored on the Secure Enclave using Accessibility attribute `.whenPasscodeSetThisDeviceOnly`. The first access of these keychain elements will require the user to confirm their presence via Touch ID, Face ID, or passcode entry. If no passcode is set on the device, accessing the keychain via a `SinglePromptSecureEnclaveValet` will fail. Data is removed from the Secure Enclave when the user removes a passcode from the device.
@available(macOS 10.11, *)
@objc(VALSinglePromptSecureEnclaveValet)
public final class SinglePromptSecureEnclaveValet: NSObject {

    // MARK: Public Class Methods

    /// - Parameter identifier: A non-empty string that uniquely identifies a SinglePromptSecureEnclaveValet.
    /// - Returns: A SinglePromptSecureEnclaveValet that reads/writes keychain elements with the desired flavor.
    public class func valet(with identifier: Identifier, accessControl: SecureEnclaveAccessControl) -> SinglePromptSecureEnclaveValet {
        let key = Service.standard(identifier, .singlePromptSecureEnclave(accessControl)).description as NSString
        if let existingValet = identifierToValetMap.object(forKey: key) {
            return existingValet

        } else {
            let valet = SinglePromptSecureEnclaveValet(identifier: identifier, accessControl: accessControl)
            identifierToValetMap.setObject(valet, forKey: key)
            return valet
        }
    }

    /// - Parameter identifier: A non-empty string that must correspond with the value for keychain-access-groups in your Entitlements file.
    /// - Returns: A SinglePromptSecureEnclaveValet that reads/writes keychain elements that can be shared across applications written by the same development team.
    public class func sharedAccessGroupValet(with identifier: Identifier, accessControl: SecureEnclaveAccessControl) -> SinglePromptSecureEnclaveValet {
        let key = Service.sharedAccessGroup(identifier, .singlePromptSecureEnclave(accessControl)).description as NSString
        if let existingValet = identifierToValetMap.object(forKey: key) {
            return existingValet

        } else {
            let valet = SinglePromptSecureEnclaveValet(sharedAccess: identifier, accessControl: accessControl)
            identifierToValetMap.setObject(valet, forKey: key)
            return valet
        }
    }

    // MARK: Equatable

    /// - Returns: `true` if lhs and rhs both read from and write to the same sandbox within the keychain.
    public static func ==(lhs: SinglePromptSecureEnclaveValet, rhs: SinglePromptSecureEnclaveValet) -> Bool {
        lhs.service == rhs.service
    }

    // MARK: Private Class Properties

    private static let identifierToValetMap = NSMapTable<NSString, SinglePromptSecureEnclaveValet>.strongToWeakObjects()

    // MARK: Initialization

    @available(*, unavailable)
    public override init() {
        fatalError("Use the class methods above to create usable SinglePromptSecureEnclaveValet objects")
    }

    private convenience init(identifier: Identifier, accessControl: SecureEnclaveAccessControl) {
        self.init(
            identifier: identifier,
            service: .standard(identifier, .singlePromptSecureEnclave(accessControl)),
            accessControl: accessControl)
    }

    private convenience init(sharedAccess identifier: Identifier, accessControl: SecureEnclaveAccessControl) {
        self.init(
            identifier: identifier,
            service: .sharedAccessGroup(identifier, .singlePromptSecureEnclave(accessControl)),
            accessControl: accessControl)
    }

    private init(identifier: Identifier, service: Service, accessControl: SecureEnclaveAccessControl) {
        self.identifier = identifier
        self.service = service
        self.accessControl = accessControl
        _baseKeychainQuery = try? service.generateBaseQuery()
    }

    // MARK: Hashable

    public override var hash: Int {
        service.description.hashValue
    }

    // MARK: Public Properties

    public let identifier: Identifier
    @objc
    public let accessControl: SecureEnclaveAccessControl

    // MARK: Public Methods

    /// - Returns: `true` if the keychain is accessible for reading and writing, `false` otherwise.
    /// - Note: Determined by writing a value to the keychain and then reading it back out. Will never prompt the user for Face ID, Touch ID, or password.
    @objc
    public func canAccessKeychain() -> Bool {
        SecureEnclave.canAccessKeychain(with: service, identifier: identifier)
    }

    /// - Parameters:
    ///   - object: A Data value to be inserted into the keychain.
    ///   - key: A Key that can be used to retrieve the `object` from the keychain.
    /// - Note: Method will throw a `KeychainError` if an error occurs.
    @objc(setObject:forKey:error:)
    public func set(object: Data, forKey key: String) throws {
        try execute(in: lock) {
            try SecureEnclave.set(object: object, forKey: key, options: try baseKeychainQuery())
        }
    }

    /// - Parameters:
    ///   - key: A Key used to retrieve the desired object from the keychain.
    ///   - userPrompt: The prompt displayed to the user in Apple's Face ID, Touch ID, or passcode entry UI. If the `SinglePromptSecureEnclaveValet` has already been unlocked, no prompt will be shown.
    /// - Note: Method will throw a `KeychainError` if an error occurs.
    @objc(objectForKey:withPrompt:error:)
    public func object(forKey key: String, withPrompt userPrompt: String) throws -> Data {
        try execute(in: lock) {
            try SecureEnclave.object(forKey: key, withPrompt: userPrompt, options: try continuedAuthenticationKeychainQuery())
        }
    }

    /// - Parameter key: The key to look up in the keychain.
    /// - Returns: `true` if a value has been set for the given key, `false` otherwise.
    /// - Note: Will never prompt the user for Face ID, Touch ID, or password.
    @objc(containsObjectForKey:)
    public func containsObject(forKey key: String) -> Bool {
        return execute(in: lock) {
            guard let baseKeychainQuery = try? self.baseKeychainQuery() else {
                return false
            }
            return SecureEnclave.containsObject(forKey: key, options: baseKeychainQuery)
        }
    }

    /// - Parameters:
    ///   - string: A String value to be inserted into the keychain.
    ///   - key: A Key that can be used to retrieve the `string` from the keychain.
    /// - Note: Method will throw a `KeychainError` if an error occurs.
    @objc(setString:forKey:error:)
    public func set(string: String, forKey key: String) throws {
        try execute(in: lock) {
            try SecureEnclave.set(string: string, forKey: key, options: try baseKeychainQuery())
        }
    }

    /// - Parameters:
    ///   - key: A Key used to retrieve the desired object from the keychain.
    ///   - userPrompt: The prompt displayed to the user in Apple's Face ID, Touch ID, or passcode entry UI. If the `SinglePromptSecureEnclaveValet` has already been unlocked, no prompt will be shown.
    /// - Note: Method will throw a `KeychainError` if an error occurs.
    @objc(stringForKey:withPrompt:error:)
    public func string(forKey key: String, withPrompt userPrompt: String) throws -> String {
        try execute(in: lock) {
            try SecureEnclave.string(forKey: key, withPrompt: userPrompt, options: try continuedAuthenticationKeychainQuery())
        }
    }

    /// Forces a prompt for Face ID, Touch ID, or passcode entry on the next data retrieval from the Secure Enclave.
    @objc
    public func requirePromptOnNextAccess() {
        execute(in: lock) {
            localAuthenticationContext.invalidate()
            localAuthenticationContext = LAContext()
        }
    }

    /// - Parameter userPrompt: The prompt displayed to the user in Apple's Face ID, Touch ID, or passcode entry UI. If the `SinglePromptSecureEnclaveValet` has already been unlocked, no prompt will be shown. If no items are found, will return an empty set.
    /// - Returns: The set of all (String) keys currently stored in this Valet instance.
    @objc(allKeysWithUserPrompt:error:)
    public func allKeys(userPrompt: String) throws -> Set<String> {
        try execute(in: lock) {
            var secItemQuery = try continuedAuthenticationKeychainQuery()
            if !userPrompt.isEmpty {
                secItemQuery[kSecUseOperationPrompt as String] = userPrompt
            }

            return try Keychain.allKeys(options: secItemQuery)
        }
    }

    /// Removes a key/object pair from the keychain.
    @objc(removeObjectForKey:error:)
    public func removeObject(forKey key: String) throws {
        try execute(in: lock) {
            try Keychain.removeObject(forKey: key, options: try baseKeychainQuery())
        }
    }

    /// Removes all key/object pairs accessible by this Valet instance from the keychain.
    @objc
    public func removeAllObjects() throws {
        try execute(in: lock) {
            try Keychain.removeAllObjects(matching: try baseKeychainQuery())
        }
    }

    /// Migrates objects matching the input query into the receiving SinglePromptSecureEnclaveValet instance.
    /// - Parameters:
    ///   - query: The query with which to retrieve existing keychain data via a call to SecItemCopyMatching.
    ///   - removeOnCompletion: If `true`, the migrated data will be removed from the keychain if the migration succeeds.
    /// - Note: The keychain is not modified if an error is thrown. Method will throw a `KeychainError` or `MigrationError` if an error occurs.
    @objc(migrateObjectsMatchingQuery:removeOnCompletion:error:)
    public func migrateObjects(matching query: [String : AnyHashable], removeOnCompletion: Bool) throws {
        try execute(in: lock) {
            try Keychain.migrateObjects(matching: query, into: try baseKeychainQuery(), removeOnCompletion: removeOnCompletion)
        }
    }

    /// Migrates objects matching the vended keychain query into the receiving SinglePromptSecureEnclaveValet instance.
    /// - Parameters:
    ///   - keychain: An objects whose vended keychain query is used to retrieve existing keychain data via a call to SecItemCopyMatching.
    ///   - removeOnCompletion: If `true`, the migrated data will be removed from the keychfain if the migration succeeds.
    /// - Note: The keychain is not modified if an error is thrown. Method will throw a `KeychainError` or `MigrationError` if an error occurs.
    @objc(migrateObjectsFromValet:removeOnCompletion:error:)
    public func migrateObjects(from valet: Valet, removeOnCompletion: Bool) throws {
        try migrateObjects(matching: try valet.keychainQuery(), removeOnCompletion: removeOnCompletion)
    }

    // MARK: Internal Properties

    internal let service: Service

    // MARK: Private Properties

    private let lock = NSLock()
    private var localAuthenticationContext = LAContext()
    private var _baseKeychainQuery: [String : AnyHashable]?

    // MARK: Private Methods

    private func baseKeychainQuery() throws -> [String : AnyHashable] {
        if let baseKeychainQuery = _baseKeychainQuery {
            return baseKeychainQuery
        } else {
            let baseKeychainQuery = try service.generateBaseQuery()
            _baseKeychainQuery = baseKeychainQuery
            return baseKeychainQuery
        }
    }

    /// A keychain query dictionary that allows for continued read access to the Secure Enclave after the a single unlock event.
    /// This query should be used when retrieving keychain data, but should not be used for keychain writes or `containsObject` checks.
    /// Using this query in a `containsObject` check can cause a false positive in the case where an element has been removed from
    /// the keychain by the operating system due to a face, fingerprint, or password change.
    private func continuedAuthenticationKeychainQuery() throws -> [String : AnyHashable] {
        var keychainQuery = try baseKeychainQuery()
        keychainQuery[kSecUseAuthenticationContext as String] = localAuthenticationContext
        return keychainQuery
    }

}


// MARK: - Objective-C Compatibility


@available(macOS 10.11, *)
extension SinglePromptSecureEnclaveValet {

    // MARK: Public Class Methods

    /// - Parameter identifier: A non-empty string that uniquely identifies a SinglePromptSecureEnclaveValet.
    /// - Returns: A SinglePromptSecureEnclaveValet that reads/writes keychain elements with the desired flavor.
    @objc(valetWithIdentifier:accessControl:)
    public class func 🚫swift_valet(with identifier: String, accessControl: SecureEnclaveAccessControl) -> SinglePromptSecureEnclaveValet? {
        guard let identifier = Identifier(nonEmpty: identifier) else {
            return nil
        }

        return valet(with: identifier, accessControl: accessControl)
    }

    /// - Parameter identifier: A non-empty string that must correspond with the value for keychain-access-groups in your Entitlements file.
    /// - Returns: A SinglePromptSecureEnclaveValet that reads/writes keychain elements that can be shared across applications written by the same development team.
    @objc(sharedAccessGroupValetWithIdentifier:accessControl:)
    public class func 🚫swift_sharedAccessGroupValet(with identifier: String, accessControl: SecureEnclaveAccessControl) -> SinglePromptSecureEnclaveValet? {
        guard let identifier = Identifier(nonEmpty: identifier) else {
            return nil
        }
        return sharedAccessGroupValet(with: identifier, accessControl: accessControl)
    }
}

#endif
