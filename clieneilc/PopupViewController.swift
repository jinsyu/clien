//
//  PopupViewController.swift
//  clieneilc
//
//  Created by jinsyu on 2020/09/02.
//  Copyright © 2020 jinsyu. All rights reserved.
//

import Cocoa
import SwiftSoup
import Alamofire
import UserNotifications

extension PopupViewController {
    
    static func freshController() -> PopupViewController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let identifier = NSStoryboard.SceneIdentifier("PopupViewController")
        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? PopupViewController else {
            fatalError("can't find popupviewcontroller")
        }
        return viewcontroller
    }
}

class PopupViewController: NSViewController, NSUserNotificationCenterDelegate {
    
    @IBOutlet weak var idTextField: NSTextField!
    @IBOutlet weak var passwordTextField: NSSecureTextField!
    @IBOutlet weak var launchAtLoginButton: NSButton!
    @IBOutlet weak var autoLoginButton: NSButton!
    @IBOutlet weak var loginButton: NSButton!
    @IBOutlet weak var logoutButton: NSButton!
    @IBOutlet weak var notiTimeTextField: NSTextField!
    @IBOutlet weak var notiTimeStepper: NSStepper!
    
    var timer: Timer?
    var LOOP_TIME: Double?
    
    @IBAction func passwordEnterPressed(_ sender: Any) {
        getAlarmList()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UNUserNotificationCenter.current().requestAuthorization(options: .badge) { (granted, error) in
            if error != nil {
                
            }
        }
        
        if let id = UserDefaults.standard.string(forKey: "id") {
            idTextField.stringValue = id
        }
        
        if let password = UserDefaults.standard.string(forKey: "password") {
            passwordTextField.stringValue = password
        }
        
        let notiTime = UserDefaults.standard.double(forKey: "notiTime")
        if notiTime != 0.0 {
            notiTimeTextField.stringValue = "\(Int(notiTime))분 마다 알림"
            notiTimeStepper.integerValue = Int(notiTime)
            LOOP_TIME = Double(notiTime)
        } else {
            notiTimeTextField.stringValue = "5분 마다 알림"
            LOOP_TIME = 5.0
        }
        
        let autoLogin = UserDefaults.standard.bool(forKey: "autoLogin")
        autoLoginButton.state = NSControl.StateValue.init(autoLogin ? 1 : 0)
        
        if autoLogin && idTextField.stringValue != "" && passwordTextField.stringValue != "" {
            getAlarmList()
        }
        
        notiTimeStepper.action = #selector(onNotiTimeStepperChanged(_:))
        
        autoLoginButton.action = #selector(onAutoLoginButtonClicked(_:))
        
        logoutButton.isEnabled = false
        
        // Do any additional setup after loading the view.
    }
    
    @objc func onNotiTimeStepperChanged(_ sender: NSStepper) {
        LOOP_TIME = Double(sender.integerValue)
        notiTimeTextField.stringValue = "\(String(describing: sender.integerValue))분 마다 알림"
        UserDefaults.standard.set(LOOP_TIME, forKey: "notiTime")
    }
    
    @objc func onAutoLoginButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(autoLoginButton.state.rawValue == 1 ? true : false, forKey: "autoLogin")
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func launchAtLoginButtonClicked(_ sender: Any) {
        UserDefaults.standard.set(launchAtLoginButton.state.rawValue, forKey: "launchAtLogin")
    }
    
    @IBAction func loginButtonClicked(_ sender: NSButton) {
        getAlarmList()
    }
    
    @IBAction func logoutButtonClicked(_ sender: Any) {
        self.idTextField.isEnabled = true
        self.passwordTextField.isEnabled = true
        self.launchAtLoginButton.isEnabled = true
        self.autoLoginButton.isEnabled = true
        self.loginButton.isEnabled = true
        self.logoutButton.isEnabled = false
        
        
        timer?.invalidate()
        
        // Get CSRF value of logout form
        AF.request("https://www.clien.net", method: .get).responseString { (response) in
            guard let html = response.value else { return }
            do {
                let doc: Document = try SwiftSoup.parse(html)
                guard let logoutForm: Element = try doc.select(".form_logout").first() else {
                    print("logoutform not fond")
                    return
                }
                let _csrf = try logoutForm.select("input").first()!.attr("value")
                
                // logout request
                AF.request("https://www.clien.net/service/logout", method: .post, parameters: ["_csrf": _csrf]).responseString { (response) in
                    if let error = response.error {
                        print("logout error", error)
                    }
                }
                
            } catch {
                print("gettting logout _csrf error")
            }
        }
    }
    
    func showNotification(title: String, subtitle: String, soundName: String=NSUserNotificationDefaultSoundName) {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        notification.soundName = soundName
        NSUserNotificationCenter.default.delegate = self
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    func isLoggedIn( completion: @escaping(Bool) -> ()) {
        AF.request("https://www.clien.net", method: .get).responseString { (response) in
            guard let html = response.value else { completion(false);return; }
            do {
                let doc: Document = try SwiftSoup.parse(html)
                guard let _: Element = try doc.select(".form_logout").first() else { completion(false);return; }
                completion(true);
            } catch {
                print("isloggedin error", error)
                completion(false)
            }
        }
    }
    
    func getParams(paramsRaw: String) -> Array<Substring> {
        var paramsRaw = paramsRaw.replacingOccurrences(of: "app.commentAlarmLink(", with: "")
        paramsRaw = paramsRaw.replacingOccurrences(of: "'", with: "")
        paramsRaw = paramsRaw.replacingOccurrences(of: " ", with: "")
        paramsRaw = paramsRaw.replacingOccurrences(of: ")", with: "")
        let params = paramsRaw.split(separator: ",")
        return params
    }
    
    @objc func getAlarmList() {
        if loginButton.title == "로그아웃" {
            
            return
        }
        // Get CSRF value
        AF.request("https://www.clien.net/service/auth/login", method: .get).responseString { (response) in
            if let error = response.error {
                print("request for getting _csrf error", error)
                return
            }
            
            guard let html = response.value else { return }
            
            do {
                let doc: Document = try SwiftSoup.parse(html)
                guard let loginForm: Element = try doc.select("#loginForm").first() else {
                    print("loginform not found")
                    return
                }
                let _csrf = try loginForm.select("input").first()!.attr("value")
                let id = self.idTextField.stringValue
                let password = self.passwordTextField.stringValue
                
                AF.request("https://www.clien.net/service/login", method: .post, parameters: ["userId": id, "userPassword": password, "_csrf": _csrf]).responseString { (_) in
                    if let error = response.error {
                        print("login error", error)
                        return
                    }
                    
                    self.isLoggedIn { (isLoggedIn) in
                        if isLoggedIn {
                            self.idTextField.isEnabled = false
                            self.passwordTextField.isEnabled = false
                            self.launchAtLoginButton.isEnabled = false
                            self.autoLoginButton.isEnabled = false
                            self.loginButton.isEnabled = false
                            self.logoutButton.isEnabled = true
                            
                            UserDefaults.standard.set(self.idTextField.stringValue, forKey: "id")
                            UserDefaults.standard.set(self.passwordTextField.stringValue, forKey: "password")
                            
                            self.timer = Timer.scheduledTimer(withTimeInterval: self.LOOP_TIME!*60, repeats: true, block: { (timer) in
                                // get alarm list
                                AF.request("https://www.clien.net/service/getAlarmList", method: .get).responseString { (response) in
                                    do {
                                        let messageDoc: Document = try SwiftSoup.parse(response.value!)
                                        let messages: Elements = try messageDoc.select("div.list_item.unread")
                                        for message in messages {
                                            
                                            var nickname = try message.select(".nickname").text()
                                            if nickname == "" {
                                                nickname = try message.select(".nickname").select("img").attr("alt")
                                            }

                                            let contents = try message.select(".list_contents").text()
                                            if contents == "관리자 알림 확인하기" {
                                                continue
                                            }
                                            let paramsRaw = try message.select(".list_contents").attr("onclick")
                                            let params = self.getParams(paramsRaw: paramsRaw)
                        
                                            let timestamp = try message.select(".timestamp").text()
                                            self.showNotification(title: "clien", subtitle: "contents")
                                            print("replies", nickname, contents, timestamp, params)
                                        }
                                        
                                    } catch Exception.Error(let type, let message){
                                        print(type, message)
                                    } catch {
                                        print("swift souping error for getting alarm list")
                                    }
                                }
                                
                                // get messages
                                AF.request("https://www.clien.net/service/message/?type=", method: .get).responseString { (response) in
                                    do {
                                        let messageDoc: Document = try SwiftSoup.parse(response.value!)
                                        let messages: Elements = try messageDoc.select("div.list_item.recieved.unread")
                                        for message in messages {
                                            
                                            var nickname = try message.select(".nickname").text()
                                            if nickname == "" {
                                                nickname = try message.select(".nickname").select("img").attr("alt")
                                            }

                                            let contents = try message.select(".list_contents").text()
                                            if contents == "관리자 알림 확인하기" {
                                                continue
                                            }
                                            
                                            
                                            let timestamp = try message.select(".timestamp").text()
                                            self.showNotification(title: "clien", subtitle: "contents")
                                            print("messages", nickname, contents, timestamp)
                                        }
                                    } catch {
                                        print("error get messages")
                                    }
                                }
                            })
                            self.timer?.fire()
                        } else {
                            print("can't log in")
                        }
                    }
                    
                    
                }
                
            } catch Exception.Error(let type, let message){
                print(type, message)
            } catch {
                print("swift souping error for getting _csrf")
            }
        }
    }
}


