#!/usr/bin/env swift
// Based on 
//https://github.com/mnewt/dotemacs/blob/master/bin/dark-mode-notifier.swift
// Compile with:
// swiftc dark-mode-notifier.swift -o dark-mode-notifier

import Cocoa
import Foundation
import os.log

/* Takes three arguments:
 * [0]: path to executable (as usual)
 * [1]: target config file
 * [2]: path to light colorscheme
 * [3]: path to dark colorscheme
 * [4]: path to wezterm config file
 * [5]: command to tell neovim to update colors
 */

let ARGUMENTS = CommandLine.arguments
let CONFIG_PATH = ARGUMENTS[1]
let LIGHT_SOURCE = ARGUMENTS[2]
let DARK_SOURCE = ARGUMENTS[3]
let WEZTERM_PATH = ARGUMENTS[4]
let NEOVIM_NOTIFY = ARGUMENTS[5]

let mainLog = Logger(
    subsystem:"local.dark-mode-notifier",
    category:"event_update"
)

func writeConfigFile(isDark: Bool) throws {
    let path = URL(fileURLWithPath: CONFIG_PATH)
    let wez_path = URL(fileURLWithPath: WEZTERM_PATH)
    
    let target_colors: String
    if isDark {
        target_colors = DARK_SOURCE
    } else {
        target_colors = LIGHT_SOURCE
    }

    let configString = """
    import:
        - \(target_colors)
    """
    
    let weztermString = """
        -- return true if dark mode
        return \( String(isDark) ) 
    """
    
    if let configStringData = configString.data(using: .utf8) {
        try? configStringData.write(to: path)
    }

    if let weztermStringData = weztermString.data(using: .utf8) {
        try? weztermStringData.write(to: wez_path)
    }
}

func updateAlacrittyTheme() {
    let isDark = 
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    try? writeConfigFile(isDark: isDark) 
    mainLog.info("Updated terminal colorschemes")
}

func notifyNeovim() {
    let notify_url = URL(fileURLWithPath: NEOVIM_NOTIFY)
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError  = pipe
    task.standardInput  = nil
    task.executableURL = notify_url

    try? task.run()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!

    mainLog.info("Notified neovim, received msg: \(output, privacy: .public)")
}

updateAlacrittyTheme() // Call once so that theme updates when system logs in.
notifyNeovim()

// Listen for when the colorscheme changes
let themeObserver = DistributedNotificationCenter.default.addObserver(
    forName: Notification.Name("AppleInterfaceThemeChangedNotification"), 
    object: nil,
    queue: nil, 
    using: { 
        (Notification) -> Void in
            updateAlacrittyTheme()
            notifyNeovim()
    }
)

NSApplication.shared.run()
