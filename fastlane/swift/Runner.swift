//
//  Runner.swift
//  FastlaneSwiftRunner
//
//  Created by Joshua Liebowitz on 8/26/17.
//  Copyright © 2017 Joshua Liebowitz. All rights reserved.
//

import Foundation

let logger: Logger = {
    return Logger()
}()

let runner: Runner = {
    return Runner()
}()

class Runner {
    fileprivate var thread: Thread!
    fileprivate var socketClient: SocketClient!
    fileprivate let dispatchGroup: DispatchGroup = DispatchGroup()
    fileprivate var returnValue: String? // lol, so safe
    fileprivate var shouldLeaveDispatchGroupDuringDisconnect = false

    func executeCommand(_ command: RubyCommandable) -> String {
        self.dispatchGroup.enter()
        socketClient.send(rubyCommand: command)

        let secondsToWait = DispatchTimeInterval.seconds(SocketClient.connectTimeoutSeconds)
        let connectTimeout = DispatchTime.now() + secondsToWait
        let timeoutResult = self.dispatchGroup.wait(timeout: connectTimeout)
        let failureMessage = "command didn't execute in: \(SocketClient.connectTimeoutSeconds) seconds"
        let success = testDispatchTimeoutResult(timeoutResult, failureMessage: failureMessage, timeToWait: secondsToWait)
        guard success else {
            log(message: "command timeout")
            fatalError()
        }

        if let returnValue = self.returnValue {
            return returnValue
        } else {
            return ""
        }
    }
}

// Handle threading stuff
extension Runner {
    func startSocketThread() {
        let secondsToWait = DispatchTimeInterval.seconds(SocketClient.connectTimeoutSeconds)

        self.dispatchGroup.enter()

        self.socketClient = SocketClient(socketDelegate: self)
        self.thread = Thread(target: self, selector: #selector(startSocketComs), object: nil)
        self.thread!.name = "socket thread"
        self.thread!.start()

        let connectTimeout = DispatchTime.now() + secondsToWait
        let timeoutResult = self.dispatchGroup.wait(timeout: connectTimeout)

        let failureMessage = "command start socket thread in: \(SocketClient.connectTimeoutSeconds) seconds"
        let success = testDispatchTimeoutResult(timeoutResult, failureMessage: failureMessage, timeToWait: secondsToWait)
        guard success else {
            log(message: "socket thread timeout")
            fatalError()
        }
    }

    func disconnectFromFastlaneProcess() {
        self.shouldLeaveDispatchGroupDuringDisconnect = true
        self.dispatchGroup.enter()
        socketClient.sendComplete()

        let connectTimeout = DispatchTime.now() + 2
        _ = self.dispatchGroup.wait(timeout: connectTimeout)
    }

    @objc func startSocketComs() {
        guard let socketClient = self.socketClient else {
            return
        }

        socketClient.connectAndOpenStreams()
        self.dispatchGroup.leave()
    }

    fileprivate func testDispatchTimeoutResult(_ timeoutResult: DispatchTimeoutResult, failureMessage: String, timeToWait: DispatchTimeInterval) -> Bool {
        switch timeoutResult {
        case .success:
            return true
        case .timedOut:
            log(message: "timeout: \(failureMessage)")
            return false
        }
    }
}

extension Runner : SocketClientDelegateProtocol {
    func commandExecuted(serverResponse: SocketClientResponse) {
        switch serverResponse {
        case .success(let returnedObject):
            verbose(message: "command executed")
            self.returnValue = returnedObject

        case .alreadyClosedSockets, .connectionFailure, .malformedRequest, .malformedResponse, .serverError:
            log(message: "error encountered while executing command:\n\(serverResponse)")

        case .commandTimeout(let timeout):
            log(message: "Runner timed out after \(timeout) second(s)")
        }

        self.dispatchGroup.leave()
    }

    func connectionsOpened() {
        DispatchQueue.main.async {
            verbose(message: "connected!")
        }
    }

    func connectionsClosed() {
        DispatchQueue.main.async {
            self.thread?.cancel()
            self.thread = nil
            self.socketClient = nil
            verbose(message: "connection closed!")
            if self.shouldLeaveDispatchGroupDuringDisconnect {
                self.dispatchGroup.leave()
            }
        }
    }
}

class Logger {
    enum LogMode {
        init(logMode: String) {
            switch logMode {
            case "normal", "default":
                self = .normal
            case "verbose":
                self = .verbose
            default:
                logger.log(message: "unrecognized log mode: \(logMode), defaulting to 'normal'")
                self = .normal
            }
        }
        case normal
        case verbose
    }

    public static var logMode: LogMode = .normal

    func log(message: String) {
        let timestamp = NSDate().timeIntervalSince1970
        print("[\(timestamp)]: \(message)")
    }

    func verbose(message: String) {
        if Logger.logMode == .verbose {
            let timestamp = NSDate().timeIntervalSince1970
            print("[\(timestamp)]: \(message)")
        }
    }
}

func log(message: String) {
    logger.log(message: message)
}

func verbose(message: String) {
    logger.verbose(message: message)
}