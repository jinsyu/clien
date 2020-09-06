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
import LaunchAtLogin
import SwiftyJSON

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
    
    var timer: Timer?
    var LOOP_TIME: Double = 1.0
    
    // password text field ENTER => get alarm list
    @IBAction func passwordEnterPressed(_ sender: Any) {
        getAlarmList()
    }
    
    @IBAction func exitButtonClicked(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    override func viewDidAppear() {
        print("viewDidAppear")
    }
    
    override func viewDidDisappear() {
        print("viewDidDisappear")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        logoutButton.isEnabled = false
        
        // get UserDefaults value
        if let id = UserDefaults.standard.string(forKey: "id") {
            idTextField.stringValue = id
        }
        
        if let password = UserDefaults.standard.string(forKey: "password") {
            passwordTextField.stringValue = password
        }
        
        // lanuchAtLogin Button value
        launchAtLoginButton.state = NSControl.StateValue.init(LaunchAtLogin.isEnabled ? 1 : 0)
        
        // authLogin Button value
        let autoLogin = UserDefaults.standard.bool(forKey: "autoLogin")
        autoLoginButton.state = NSControl.StateValue.init(autoLogin ? 1 : 0)
        autoLoginButton.action = #selector(onAutoLoginButtonClicked(_:))
        
        // autologin && saved id, password => get alarm list
        if autoLogin && idTextField.stringValue != "" && passwordTextField.stringValue != "" {
            getAlarmList()
        }
    }
    
    @IBAction func onLaunchAtLoginButtonClicked(_ sender: NSButton) {
        if sender.state.rawValue == 1 {
            LaunchAtLogin.isEnabled = true
        } else {
            LaunchAtLogin.isEnabled = false
        }
    }
    
    @objc func onAutoLoginButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(autoLoginButton.state.rawValue == 1 ? true : false, forKey: "autoLogin")
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func loginButtonClicked(_ sender: NSButton) {
        getAlarmList()
    }
    
    @IBAction func logoutButtonClicked(_ sender: Any) {
        self.enableButtons()
        
        timer?.invalidate()
        logOut()
    }
    
    func logOut() {
        // Get CSRF value of logout form
        AF.request("https://www.clien.net", method: .get).responseString { (response) in
            if (response.response?.statusCode != 200) {
                print("https://www.clien.net get error")
                return
            }
            
            guard let html = response.value else { return }
            do {
                let doc: Document = try SwiftSoup.parse(html)
                guard let inputCSRF = try doc.select("input[name=_csrf]").first() else { return }
                let _csrf = try inputCSRF.attr("value")
                
                // logout request
                AF.request("https://www.clien.net/service/logout", method: .post, parameters: ["_csrf": _csrf]).responseString { (response) in
                    if (response.response?.statusCode != 200) {
                        print("logout error")
                    }
                }
            } catch {
                print("gettting logout _csrf error")
            }
        }
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    func showNotification(title: String, subtitle: String, params: [Substring], csrf: String) {
        let notification = NSUserNotification()
        notification.hasReplyButton = true
        notification.responsePlaceholder = "댓글 작성(3글자 이상 입력하세요!!)"
        notification.title = title
        notification.subtitle = subtitle
        notification.userInfo = ["params": params]
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.delegate = self
        // need some time to accept notification request when it start at first
        Timer.scheduledTimer(withTimeInterval: 5, repeats: false, block: { (timer) in
            NSUserNotificationCenter.default.deliver(notification)
        })
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        //["sold", "15324455", "R10", "28681294", "117237529"]
        //bardCd, boardSn, alarmType, alarmSn, divFocus
        let params = notification.userInfo!["params"] as! [String]
        let boardName = params[0]
        let boardSn = params[1]
        let reCommentSn = params[4]
        
        switch (notification.activationType) {
        case .actionButtonClicked:
            print("action button clicked")
            break
        case .additionalActionClicked:
            print("additional action button clicked")
            break
        case .none:
            print("none clicked")
            break
        // Notification Contents Clicked
        case .contentsClicked:
            NSWorkspace.shared.open(URL(string: "https://www.clien.net/service/board/\(boardName)/\(boardSn)")!)
            print("contents clicked")
            break
        // Reply button clicked
        case .replied:
            // get csrf
            AF.request("https://www.clien.net/service/board/\(boardName)/\(boardSn)", method: .get).responseString { (response) in
                guard let html = response.value else { return }
                
                do {
                    let doc: Document = try SwiftSoup.parse(html)
                    guard let inputCSRF = try doc.select("input[name=_csrf]").first() else {
                        print("reply get csrf error")
                        return
                    }
                    let _csrf = try inputCSRF.attr("value")
                    
                    guard let replyString = notification.response?.string else { return }
                    
                    
                    AF.request(
                        "https://www.clien.net/service/api/board/\(boardName)/\(boardSn)/comment/regist/",
                        method: .post,
                        parameters: ["boardSn": boardSn, "param": "{\"comment\": \"\(replyString)\", \"images\": [], \"articleRegister\": \"\(notification.title!)\", \"reCommentSn\": \(reCommentSn)}"],
                        headers: ["X-CSRF-TOKEN": _csrf]).validate().responseJSON { (response) in
                            
                            switch response.result {
                            //Remove loader here either after parsing or on error
                            case .success(_):
                                print("replied", replyString, params)
                            case .failure(let error):
                                print(error)
                                if let responseData = response.data {
                                    do {
                                        let parsedResponseData = try JSON.init(data: responseData)
                                        self.showAlert(question: "댓글 작성 실패", text: parsedResponseData["message"].stringValue)
                                    } catch {
                                        print("json pared error")
                                    }
                                }
                            }
                    }
                    
                } catch {
                    print("replying get csrf error")
                }
            }
            break
        @unknown default:
            print("notification activated unknown")
            break
        }
    }
    
    func showAlert(question: String, text: String) {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.icon = NSImage(named: "clien")
        alert.alertStyle = NSAlert.Style.warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
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
    
    func disableButtons() {
        self.idTextField.isEnabled = false
        self.passwordTextField.isEnabled = false
        self.launchAtLoginButton.isEnabled = false
        self.autoLoginButton.isEnabled = false
        self.loginButton.isEnabled = false
        self.logoutButton.isEnabled = true
    }
    
    func enableButtons() {
        self.idTextField.isEnabled = true
        self.passwordTextField.isEnabled = true
        self.launchAtLoginButton.isEnabled = true
        self.autoLoginButton.isEnabled = true
        self.loginButton.isEnabled = true
        self.logoutButton.isEnabled = false
    }
    
    @objc func getAlarmList() {
        disableButtons()
        
        // DEV need to change
        self.timer = Timer.scheduledTimer(withTimeInterval: self.LOOP_TIME*60, repeats: true, block: { (timer) in
            
            AF.request("https://www.clien.net/service/auth/login", method: .get).responseString { (response) in
                if (response.response?.statusCode != 200) {
                    print("https://www.clien.net/service/auth/login get error", response.response!.statusCode)
                    return
                }
                
                guard let html = response.value else {
                    print("https://www.clien.net/service/auth/login response.value error")
                    return
                }
                
                do {
                    let doc: Document = try SwiftSoup.parse(html)
                    
                    let _csrf = try doc.select("input[name=_csrf]").first()!.attr("value")
                    
                    let id = self.idTextField.stringValue
                    let password = self.passwordTextField.stringValue
                    
                    AF.request("https://www.clien.net/service/login", method: .post, parameters: ["userId": id, "userPassword": password, "_csrf": _csrf]).responseString { (response) in
                        if (response.response?.statusCode != 200) {
                            print("https://www.clien.net/service/login get error")
                            return
                        }
                        
                        AF.request("https://www.clien.net", method: .get).responseString { (response) in
                            guard let html = response.value else {
                                print("https://www.clien.net get error")
                                return
                            }
                            
                            do {
                                let doc: Document = try SwiftSoup.parse(html)
                                
                                guard let _ = try doc.select("form.form_logout").first() else {
                                    self.showAlert(question: "로그인 실패", text: "아이디와 비밀번호를 다시 확인해주세요")
                                    self.timer?.invalidate()
                                    self.enableButtons()
                                    return
                                }
                                
                                guard let inputCSRF = try doc.select("input[name=_csrf]").first() else { return }
                                let _csrf = try inputCSRF.attr("value")
                                UserDefaults.standard.set(self.idTextField.stringValue, forKey: "id")
                                UserDefaults.standard.set(self.passwordTextField.stringValue, forKey: "password")
                                
                                for n in 0...2 {
                                    // get alarm list
                                    AF.request("https://www.clien.net/service/getAlarmList?po=\(n)", method: .get).responseString { (response) in
                                        do {
                                            let messageDoc: Document = try SwiftSoup.parse(response.value!)
                                            let messages: Elements = try messageDoc.select("div.list_item.unread")
                                            // DEV
//                                             let messages: Elements = try messageDoc.select("div.list_item")
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
                                                
                                                let _ = try message.select(".timestamp").text()
                                                
                                                print("replies", nickname, contents, params)
                                                self.showNotification(title: nickname, subtitle: contents, params: params, csrf: _csrf)
                                                // alarmRead/'+alarmType+'/'+alarmSn
                                                //["sold", "15324455", "R10", "28681294", "117237529"]
                                                //bardCd, boardSn, alarmType, alarmSn, divFocus
                                                // alarm read
                                                AF.request("https://www.clien.net/service/api/alarmRead/\(params[2])/\(params[3])", method: .post, headers: ["X-CSRF-TOKEN": _csrf]).responseString { (response) in
                                                    if (response.response?.statusCode != 200) {
                                                        print("alarm read error", "https://www.clien.net/service/api/alarmRead/\(params[2])/\(params[3])", params)
                                                        return
                                                    }
                                                    print("alarm read", params)
                                                }
                                                
                                            }
                                        } catch Exception.Error(let type, let message){
                                            print(type, message)
                                        } catch {
                                            print("swift souping error for getting alarm list")
                                        }
                                    }
                                }
                                
                                // alarm all read
                                //                                AF.request("https://www.clien.net/service/api/alarmAllRead", method: .post, headers: ["X-CSRF-TOKEN": _csrf]).responseJSON { (response) in
                                //                                    print("alarm all read", response)
                                //                                }
                                
                                //                                self.logOut()
                                
                                // get messages
                                //                                AF.request("https://www.clien.net/service/message/?type=", method: .get).responseString { (response) in
                                //                                    do {
                                //                                        let messageDoc: Document = try SwiftSoup.parse(response.value!)
                                //                                        let messages: Elements = try messageDoc.select("div.list_item.recieved.unread")
                                //                                        for message in messages {
                                //
                                //                                            var nickname = try message.select(".nickname").text()
                                //                                            if nickname == "" {
                                //                                                nickname = try message.select(".nickname").select("img").attr("alt")
                                //                                            }
                                //
                                //                                            let contents = try message.select(".list_contents").text()
                                //                                            if contents == "관리자 알림 확인하기" {
                                //                                                continue
                                //                                            }
                                //                                            let paramsRaw = try message.select(".list_contents").attr("onclick")
                                //                                            let params = self.getParams(paramsRaw: paramsRaw)
                                //
                                //                                            let timestamp = try message.select(".timestamp").text()
                                //
                                //                                            print("messages", nickname, contents, timestamp)
                                //                                            self.showNotification(title: nickname, subtitle: contents, params: params, csrf: _csrf)
                                //                                        }
                                //                                    } catch {
                                //                                        print("error get messages")
                                //                                    }
                                //                                }
                                
                            } catch {
                                print("https://www.clien.net swiftsoup error", error)
                            }
                        }
                    }
                } catch {
                    print("https://www.clien.net/service/auth/login swiftsoup error")
                }
            }
        })
        
        self.timer?.fire()
    }
    
}
