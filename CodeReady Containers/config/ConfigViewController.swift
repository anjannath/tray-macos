//
//  ConfigViewController.swift
//  CodeReady Containers
//
//  Created by Anjan Nath on 01/07/20.
//  Copyright © 2020 Red Hat. All rights reserved.
//

import Cocoa

struct configResult: Decodable {
    let Error: String
    let Properties: [String]?
}

class ConfigViewController: NSViewController {
    // preferences->properties controls
    @IBOutlet weak var pullSecretFilePathTextField: NSTextField!
    @IBOutlet weak var cpuSlider: NSSlider!
    @IBOutlet weak var cpusLabel: NSTextField!
    @IBOutlet weak var memorySlider: NSSlider!
    @IBOutlet weak var memoryLabel: NSTextField!
    @IBOutlet weak var diskSizeTextField: NSTextField!
    @IBOutlet weak var diskSizeStepper: NSStepper!
    @IBOutlet weak var enableTelemetrySwitch: NSButton!
    @IBOutlet weak var nameservers: NSTextField!
    
    // proxy configuration
    @IBOutlet weak var httpProxy: NSTextField!
    @IBOutlet weak var httpsProxy: NSTextField!
    @IBOutlet weak var noProxy: NSTextField!
    @IBOutlet weak var proxyCaFile: NSTextField!
    @IBOutlet weak var proxyCAFileButton: NSButton!
    @IBOutlet weak var autostartAtLoginButton: NSButton!
    
    @IBOutlet weak var newVersionDownloadButton: NSButton!
    
    // constants
    let minimumMemory: Double = 9216
    let minimumCpus: Double = 4
    let minimumDiskSize: Double = 31
    
    var centered: Bool = false
    
    // change trackers
    var textFiedlChangeTracker: [NSTextField : NSTextField]? = [:]
    var changedConfigs: CrcConfigs?
    var configsNeedingUnset: [String] = []
    var consentTelemetry: String = ""
    var autostart: Bool?
    var numCpus: Int?
    var memory: Int?
    var diskSize: Int?
    var needsUnset: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.height)
        
        // adjust memory and cpu sliders
        self.cpuSlider?.minValue = self.minimumCpus
        self.cpuSlider?.maxValue = Double(ProcessInfo().processorCount)
        self.cpuSlider?.numberOfTickMarks = ProcessInfo().processorCount - Int(minimumCpus) + 1
        self.memorySlider?.minValue = self.minimumMemory
        self.memorySlider?.maxValue = Double(ProcessInfo().physicalMemory/1048576)
        
        // disk size stepper adjustments
        self.diskSizeStepper?.minValue = self.minimumDiskSize
        self.diskSizeStepper?.maxValue = self.minimumDiskSize + 30
        self.diskSizeStepper?.increment = 1
        
        self.newVersionDownloadButton?.keyEquivalent = "\r"
        self.newVersionDownloadButton?.isHighlighted = true
        self.LoadConfigs()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.level = .floating
        if let v = view.identifier {
            print(v.rawValue)
            if v.rawValue != "advancedTab" && !centered {
                view.window?.center()
                self.centered = true
            }
        }
        self.parent?.view.window?.title = self.title!
    }
    
    func LoadConfigs() {
        var configs: CrcConfigs? = nil
        DispatchQueue.global(qos: .background).async {
            do{
                if (try GetAllConfigFromDaemon()) != nil {
                    configs = try GetAllConfigFromDaemon()!
                }
            }
            catch DaemonError.noResponse {
                DispatchQueue.main.async {
                    showAlertFailedAndCheckLogs(message: "Did not receive any response from the daemon", informativeMsg: "Ensure the CRC daemon is running, for more information please check the logs")
                }
            }
            catch {
                DispatchQueue.main.async {
                    showAlertFailedAndCheckLogs(message: "Bad response", informativeMsg: "Undefined error")
                }
            }
            
            DispatchQueue.main.async {
                // Load config property values
                self.cpusLabel?.intValue = Int32((configs?.cpus ?? 0))
                self.cpuSlider?.intValue = Int32((configs?.cpus ?? 0))
                
                self.httpProxy?.stringValue = configs?.httpProxy ?? "Unset"
                self.httpsProxy?.stringValue = configs?.httpsProxy ?? "Unset"
                self.proxyCaFile?.stringValue = configs?.proxyCaFile ?? "Unset"
                self.noProxy?.stringValue = configs?.noProxy ?? "Unset"
                
                self.memorySlider?.doubleValue = Float64(configs?.memory ?? 0)
                self.memoryLabel?.doubleValue = Float64(configs?.memory ?? 0)
                self.nameservers?.stringValue = configs?.nameserver ?? "Unset"
                self.diskSizeTextField?.doubleValue = Float64(configs?.diskSize ?? 0)
                self.diskSizeStepper?.intValue = Int32(configs?.diskSize ?? 0)
                self.pullSecretFilePathTextField?.stringValue = configs?.pullSecretFile ?? "Unset"

                if configs?.consentTelemetry == "" {
                    self.enableTelemetrySwitch?.state = .off
                } else {
                    self.enableTelemetrySwitch?.state = (configs?.consentTelemetry?.lowercased()) == "yes" ? .on : .off
                }
                guard let autoStartValue = configs?.autostartTray else { return }
                self.autostartAtLoginButton?.state = (autoStartValue) ? .on : .off
                
                self.view.display()
            }
        }
    }
    
    @IBAction func pullSecretFileButtonClicked(_ sender: Any) {
        showFilePicker(msg: "Select the Pull Secret file", txtField: self.pullSecretFilePathTextField, fileTypes: [])
        self.textFiedlChangeTracker?[self.pullSecretFilePathTextField] = self.pullSecretFilePathTextField
    }
    
    @IBAction func proxyCaFileButtonClicked(_ sender: Any) {
        showFilePicker(msg: "Select CA file for your proxy", txtField: self.proxyCaFile, fileTypes: [])
        self.textFiedlChangeTracker?[self.proxyCaFile] = self.proxyCaFile
    }
    
    @IBAction func propertiesApplyClicked(_ sender: Any) {
        changedConfigs = CrcConfigs()
        guard let ct = self.textFiedlChangeTracker else { return }
        for textField in ct.values {
            switch textField {
            case self.pullSecretFilePathTextField:
                if textField.stringValue == "" {
                    needsUnset = true
                    configsNeedingUnset.append(contentsOf: ["pull-secret-file"])
                } else {
                    self.changedConfigs?.pullSecretFile = textField.stringValue
                }
            case self.nameservers:
                if textField.stringValue == "" {
                    needsUnset = true
                    configsNeedingUnset.append(contentsOf: ["nameserver"])
                } else {
                    self.changedConfigs?.nameserver = textField.stringValue
                }
            default:
                print("Should not reach here: TextField")
            }
        }
        if self.consentTelemetry != ""{
            self.changedConfigs?.consentTelemetry = self.consentTelemetry
        }
        if (self.memory != nil) {
            self.changedConfigs?.memory = self.memory
        }
        if (self.numCpus != nil) {
            self.changedConfigs?.cpus = self.numCpus
        }
        if (self.diskSize != nil) {
            self.changedConfigs?.diskSize = self.diskSize
        }
        
        // present action sheet alert and ask for confirmation
        ShowActionSheetAndApplyConfig()
    }
    
    @IBAction func AdvancedTabApplyButtonClicked(_ sender: Any) {
        changedConfigs = CrcConfigs()
        guard let ct = self.textFiedlChangeTracker else { return }
        for textField in ct.values {
            switch textField {
            case self.httpProxy:
                if textField.stringValue == "" {
                    needsUnset = true
                    configsNeedingUnset.append(contentsOf: ["http-proxy"])
                } else {
                    self.changedConfigs?.httpProxy = textField.stringValue
                }
            case self.httpsProxy:
                if textField.stringValue == "" {
                    needsUnset = true
                    configsNeedingUnset.append(contentsOf: ["https-proxy"])
                } else {
                    self.changedConfigs?.httpsProxy = textField.stringValue
                }
            case self.noProxy:
                if textField.stringValue == "" {
                    needsUnset = true
                    configsNeedingUnset.append(contentsOf: ["no-proxy"])
                } else {
                    self.changedConfigs?.noProxy = textField.stringValue
                }
            case self.proxyCaFile:
                if textField.stringValue == "" {
                    needsUnset = true
                    configsNeedingUnset.append(contentsOf: ["proxy-ca-file"])
                } else {
                    self.changedConfigs?.proxyCaFile = textField.stringValue
                }
            default:
                print("Should not reach here")
            }
        }
        
        if self.autostart != nil {
            self.changedConfigs?.autostartTray = self.autostart
        }
        
        ShowActionSheetAndApplyConfig()
    }
    
    func ShowActionSheetAndApplyConfig() {
        let alert = NSAlert()
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.messageText = "Are you sure you want to apply these changes?"
        alert.informativeText = "After clicking Apply all your config changes will be applied"
        alert.beginSheetModal(for: self.view.window!) { (response) in
            if response == .alertFirstButtonReturn {
                // encode the json for configset and send it to the daemon
                let configsJson = configset(properties: self.changedConfigs ?? CrcConfigs())
                guard let res = SendCommandToDaemon(command: ConfigsetRequest(command: "setconfig", args: configsJson)) else { return }
                do {
                    let result = try JSONDecoder().decode(configResult.self, from: res)
                    if !result.Error.isEmpty {
                        let alert = NSAlert()
                        alert.informativeText = "\(result.Error)"
                        alert.messageText = "Error"
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                } catch let jsonErr {
                    print(jsonErr)
                }
                if self.configsNeedingUnset.count > 0 {
                    print(self.configsNeedingUnset)
                    guard let res = SendCommandToDaemon(command: ConfigunsetRequest(command: "unsetconfig", args: configunset(properties: self.configsNeedingUnset))) else { return }
                    print(String(data: res, encoding: .utf8) ?? "Nothing")
                    self.configsNeedingUnset = []
                }
                self.LoadConfigs()
                self.clearChangeTrackers()
            }
        }
    }
    
    @IBAction func consentTelemetryClicked(_ sender: Any) {
        let s = sender as? NSButton
        if s?.state == .on {
            self.consentTelemetry = "yes"
        }
        if s?.state == .off {
            self.consentTelemetry = "no"
        }
    }
    
    @IBAction func autostartSwitchClicked(_ sender: Any) {
        let s = sender as? NSButton
        self.autostart = (s?.state == .on) ? true : false
    }
    
    @IBAction func cpuSliderChanged(_ sender: NSSlider) {
        self.cpusLabel.intValue = sender.intValue
        self.numCpus = Int(sender.intValue)
    }
    
    @IBAction func memorySliderChanged(_ sender: NSSlider) {
        self.memoryLabel.intValue = sender.intValue
        self.memory = Int(sender.intValue)
        
    }
    @IBAction func diskSizeStepperClicked(_ sender: NSStepper) {
        print(sender.intValue)
        self.diskSize = Int(sender.intValue)
        self.diskSizeTextField.intValue = sender.intValue
    }
    
    func clearChangeTrackers() {
        self.consentTelemetry = ""
        self.autostart = nil
        self.textFiedlChangeTracker = [:]
        self.changedConfigs = CrcConfigs()
    }
}

extension ConfigViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object else { print("False notification, nothing changed"); return }
        print((textField as! NSTextField).stringValue)
        self.textFiedlChangeTracker?[textField as! NSTextField] = textField as? NSTextField
    }
}
