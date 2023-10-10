// The Swift Programming Language
// https://docs.swift.org/swift-book
// 
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import Foundation

import Cocoa // For NSWorkspace

import Logging
#if os(OSX)
import LoggingOSLog
import LoggingFormatAndPipe
#elseif os(Linux)
import LoggingSyslog
#endif

import ArgumentParser
import Toml

let DEFAULT_CONFIG_NAME = "config.toml"
let APP_NAME = "dark-mode-notifier"
let SUBSYSTEM = "local.\(APP_NAME)"

struct Options: ParsableArguments {
    @Option(name: .shortAndLong, help: "Pass nondefault config file.")
    var config: String?
}

@main
struct Notifier: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "dark-mode-notifier",
        abstract: "Swift program to query and act when system UI mode changes.",
        version: "2.0.0",
        subcommands: [Query.self, Listen.self, Update.self, GenerateConfig.self],
        defaultSubcommand: Listen.self
    )
    
    @OptionGroup var options: Options
    
    struct Listen : ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Listen for UI mode changes and run notify tasks specified in config.toml")
        
        @OptionGroup var options: Options
        
        mutating func run() throws {
            let ctx = ProgramContext(config_path: options.config, log_type: LoggerType.OSLOG)
            ctx.parseUpdateItems()
            ctx.update()
            
            ctx.registerObservers()
            NSApplication.shared.run()
        }
    }
    
    struct Update : ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Force an update cycle from \(APP_NAME).")
        
        @OptionGroup var options: Options
        
        mutating func run() throws {
            let ctx = ProgramContext(config_path: options.config, log_type: LoggerType.STDOUT)
            ctx.parseUpdateItems()
            ctx.update()
        }
    }
    
    struct Query: ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Query the OS for the system UI color mode.")
        
        mutating func run() throws {
            print(ProgramContext.queryDarkMode())
        }
    }
    
    struct GenerateConfig: ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Write default config file to default path")
        
        @OptionGroup var options: Options
        
        mutating func run() throws {
            let ctx = ProgramContext(config_path: options.config, log_type: LoggerType.STDOUT)
            ctx.log.info("Writing config file to \(ctx.configURL).")
            if FileManager.default.fileExists(atPath: ctx.configURL.path) {
                ctx.log.error("Config file already exists!")
                throw "Runtime error"
            } else {
                try DEFAULT_CONFIG.data(using: .utf8)!.write(to: ctx.configURL)
            }
        }
    }
}

class ProgramContext {
    let log : Logger
    let configURL : URL
    var updateItems : [UpdateItem]?
    
    init(config_path: String?, log_type: LoggerType?) {
        log = try! setupLogging(type: log_type ?? LoggerType.OSLOG)
        configURL = getConfigURL(config_path: config_path)
        updateItems = nil
    }
    
    static func staticParseUpdateItems(config_url: URL) throws -> [UpdateItem] {
        let absPath = config_url.path
        
        var newUpdateItems : [UpdateItem] = []
        
        if !FileManager.default.fileExists(atPath: absPath) {
            throw "Config file (at \"\(absPath)\" not found! Try running `dark-mode-notifier generate-config`."
        }
        
        let toml = try Toml(contentsOfFile: absPath)
        if let itemTables : [Toml] = toml.array("item") {
            for itemTable in itemTables.filter({ $0.hasKey(key: ["type"]) }) {
                switch itemTable.string("type")! {
                case "File":
                    if let p = itemTable.string("path"),
                       let l = itemTable.string("light_string"),
                       let d = itemTable.string("dark_string")
                    {
                        newUpdateItems.append(UpdateItem.ConfigFile(
                            path: p, light_string: l, dark_string: d)
                        )
                    }
                case "Command":
                    if let c = itemTable.string("cmd"),
                       let args : [String] = itemTable.array("args")
                    {
                        newUpdateItems.append(UpdateItem.NotifyCmd(
                            cmd: c, args: args)
                        )
                    }
                case _:
                    continue;
                }
            }
        }
        
        return newUpdateItems
    }
    
    func parseUpdateItems() {
        updateItems = try! ProgramContext.staticParseUpdateItems(config_url: configURL)
    }
    
    static func queryDarkMode() -> Bool {
        #if os(OSX)
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        #elseif os(Linux)
        return false // TODO: Implement gsettings query
        #endif
    }
    
    func notifyProc(cmd: String, args: [String]) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError  = pipe
        task.standardInput  = nil
        task.launchPath = cmd
        task.arguments  = args
        
        log.info("Running notify command \"\(cmd)\" with arguments \"\(args)\".")
        try? task.run()
        
        let data : Data?
        if #available(macOS 10.15.4, *) {
            data = try? pipe.fileHandleForReading.readToEnd()
        } else {
            #if os(Linux) || os(Windows)
            data = try? pipe.fileHandleForReading.readToEnd()
            #else // Here we are using an old version of macOS
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            #endif
        }
        let res  = String(data: data!, encoding: .utf8)
        if let res {
            let empty = data?.isEmpty ?? true
            log.info("Notified process \"\(cmd)\", received msg (empty: \(empty)):\n\(res)")
        } else {
            log.error("Notified process \"\(cmd)\", but could not parse a response (no message was received?)!")
        }
    }
    
    func writeToFile(path: String, dark_mode: Bool, light_string: String, dark_string: String) {
        let file = URL(fileURLWithPath: path)
        
        if dark_mode {
            do {
                try dark_string.data(using: .utf8)?.write(to: file)
                log.info("Updated config \"\(path)\" to dark mode.")
            } catch {
                log.error("Failed to adjust config \"\(path)\" to dark mode! Received error:\n\(error.localizedDescription)")
            }
        } else {
            do {
                try light_string.data(using: .utf8)?.write(to: file)
                log.info("Updated config \"\(path)\" to light mode.")
            } catch {
                log.error("Failed to adjust config \"\(path)\" to light mode! Received error:\n\(error.localizedDescription)")
            }
        }
    }
    
    func update() {
        let isDark = ProgramContext.queryDarkMode()
        for item in self.updateItems ?? [] {
            switch item {
            case .ConfigFile(let path, let light_string, let dark_string):
                self.writeToFile(
                    path: path,
                    dark_mode: isDark,
                    light_string: light_string,
                    dark_string: dark_string
                )
            case .NotifyCmd(let cmd, let args):
                self.notifyProc(cmd: cmd, args: args)
            }
        }
    }
    
    // TODO: Add GNOME GObject::Notify listeners for Linux
    func registerObservers() {
        let _ = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: nil,
            using: {
                (Notification) -> Void in
                self.log.info("\(SUBSYSTEM) detected theme change.")
                self.update()
            })
        let _ = DistributedNotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil,
            using: {
                (Notification) -> Void in
                self.log.info("\(SUBSYSTEM) detected theme change.")
                self.update()
            })
        
    }
}

enum UpdateItem {
    case ConfigFile(path: String, light_string: String, dark_string: String)
    case NotifyCmd(cmd: String, args: [String])
}

enum LoggerType {
    case OSLOG, STDOUT, SYSLOG
}

func setupLogging(type: LoggerType) throws -> Logger {
    #if os(OSX)
    switch type {
    case .OSLOG:
        LoggingSystem.bootstrap(LoggingOSLog.init);
        return Logger(label: SUBSYSTEM);
    case .STDOUT:
        return Logger(label: SUBSYSTEM) { _ in
            return LoggingFormatAndPipe.Handler(
                formatter: BasicFormatter.apple,
                pipe: LoggerTextOutputStreamPipe.standardOutput
            )
        }
    case .SYSLOG:
        throw "syslog is not supported on macOS."
    }
    
    #elseif os(Linux)
    LoggingSystem.bootstrap(SyslogLogHandler.init)
    #endif
}

func getConfigURL(config_path: String?) -> URL {
    let xdg_config_home = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "~/.config/"
    let p = config_path ?? "\(xdg_config_home)/\(APP_NAME)/\(DEFAULT_CONFIG_NAME)"
    return URL(
        fileURLWithPath: NSString(string: p).expandingTildeInPath
    )
}

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

let DEFAULT_CONFIG = """
## dark-mode-notifier default config
#
# All entries belong to the [[item]] array
# any malformed entries will be ignored.
#
# [[item]]
# type = "Command"
# cmd = "path to command"
# args = ["any", "args", "as", "string", "array"]
#
# [[item]]
# type = "File"
# path = "absolute path to file"
# light_string = "File contents for light mode"
# dark_string = "File contents for dark mode"
"""
