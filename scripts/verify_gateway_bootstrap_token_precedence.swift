#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let gatewayClientPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Core")
    .appendingPathComponent("Gateway")
    .appendingPathComponent("GatewayClient.swift")

guard let source = try? String(contentsOf: gatewayClientPath, encoding: .utf8) else {
    fputs("FAIL: could not read \(gatewayClientPath.path)\n", stderr)
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    !source.contains("storedToken?.token ?? (authToken.isEmpty ? nil : authToken)"),
    "GatewayClient should not prefer a saved device token over the gateway bootstrap token."
)

require(
    source.contains("let signatureToken: String? = authToken.isEmpty ? nil : authToken"),
    "GatewayClient should sign connect requests with the gateway bootstrap token from openclaw.json."
)

require(
    source.contains("tokenStore.load(role: connectRole,") == false,
    "GatewayClient should not load device-auth.json while selecting the connect auth token."
)

print("Gateway bootstrap token precedence verification passed")
