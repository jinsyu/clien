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
    @IBOutlet weak var loginButton: NSButton!
    @IBOutlet weak var logoutButton: NSButton!
    
    var timer: Timer?
    
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
        
        logoutButton.isEnabled = false
        
        // Do any additional setup after loading the view.
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
                            self.loginButton.isEnabled = false
                            self.logoutButton.isEnabled = true
                            
                            UserDefaults.standard.set(self.idTextField.stringValue, forKey: "id")
                            UserDefaults.standard.set(self.passwordTextField.stringValue, forKey: "password")
                            
                            self.timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { (timer) in
                                
                                AF.request("https://www.clien.net/service/getAlarmList", method: .get).responseString { (response) in
                                    do {
                                        let messageDoc: Document = try SwiftSoup.parse(response.value!)
                                        let messages: Elements = try messageDoc.select(".list_item")
                                        for message in messages {
                                            let nickname = try message.select(".nickname").text()
                                            let contents = try message.select(".list_contents").text()
                                            let timestamp = try message.select(".timestamp").text()
                                            self.showNotification(title: contents, subtitle: contents)
                                            print(nickname, contents, timestamp)

                                        }
                                
                                    } catch Exception.Error(let type, let message){
                                        print(type, message)
                                    } catch {
                                        print("swift souping error for getting alarm list")
                                    }
                                    
                                }
                            })
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


