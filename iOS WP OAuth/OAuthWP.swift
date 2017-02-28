//
//  OAuthWP.swift
//  iOS WP OAuth
//
//  Created by wlc on 1/28/16.
//  Copyright © 2016 wLc Designs. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

/*
 * Define "Certificate Pinning" constant
 * Try prepending "www" if wlcdesigns.com doesn't work
 */


//Site Url: this is a full link, not a domain
let url = "https://your-domain.com"
let siteUrl = url+"/" //include forward slash at the end

//OAuth Links
let oauthLinks:[String:String] = [
    "authorize":siteUrl+"oauth/authorize",
    "refresh":siteUrl+"oauth/token",
    "me":siteUrl+"oauth/me",
    "update-me":siteUrl+"oauth/update-me"
]

/*
 * Set OAuth Observer protocol to keep track of changes inside closures
 * This protocol utilizes the EventHandler.swift
 * This is an alternative to using the Notification Center
 */

protocol 🕵 {
    associatedtype PropertyType
    var propertyChanged: Event<PropertyType> { get }
}

//Set enum to define OAuth events

enum ObserverProperty: String {
    case Fail
    case Success
    case OAuthError = "Authentication Error"
    case NetworkError = "Network Error"
    case SaveError = "Save Error"
    case Updated = "Update Successful!"
    case NotUpdated = "Update Failed. Please Try Again!"
    case UserNameInvalid = "Invalid User Name"
    case PasswordInvalid = "Incorrect Password"
    case RefreshInvalid = "Refresh token has expired"
}

/*
 * Define the protocol that will be used to login 
 * and handle OAuth with the host
 */

protocol wpOAuthProtocol
{
    //Login to your self hosted WordPress installation
    func login(_ username:String, password:String)
    
    //Run OAuth after successful login
    func runOAuth(_ json:JSON)
    
    //Fetch User data after successful retreival of OAuth tokens
    //func getUserData(completionHandler:(String) -> ()) -> ()
    func getUserData(completionHandler: @escaping (String) -> ()) -> ()
    
    //Check if Access Token is still valid
    func checkOauth()
    
    /*
     * If Access Token is not valid, 
     * use the Refresh Token to fetch another Access Token
     */
    
    func refreshOAuth()
    
    //After token checks, update Display Name
    func updateDisplayName(_ name:String)
    
}

/*
 * Prevents the SessionaManager from getting deallocated 
 * before certificate check
 */
class Session {
    static let sharedInstance = Session()
    
    private var manager : SessionManager?
    
    func ApiManager()->SessionManager{
        if let m = self.manager{
            return m
        }else{
            
            let configuration = URLSessionConfiguration.default
            
            //Define "Certificate Pinning" constant
            let serverTrustPolicies: [String: ServerTrustPolicy] = [
                url: .pinCertificates(
                    certificates: ServerTrustPolicy.certificates(),
                    validateCertificateChain: true,
                    validateHost: true
                ),
                "localhost": .disableEvaluation
            ]
            
            //Add certificate pinning to Session Manager
            let tempmanager = Alamofire.SessionManager(configuration: configuration,serverTrustPolicyManager: ServerTrustPolicyManager(policies: serverTrustPolicies))
            
            self.manager = tempmanager
            
            return self.manager!
        }
    }
}


//Create struct based on wpOAuthProtocol protocol
struct wpOauth: wpOAuthProtocol, 🕵
{

    internal func getUserData(completionHandler: @escaping (String) -> ()) {
        ///get tokens function
        guard let accessToken = defaults.string(forKey: "accessToken") else {
            return
        }
        
        print("getUserData")
        Session.sharedInstance.ApiManager().request(oauthLinks["me"]!, method: .post, parameters: [
            "access_token": accessToken
            ]).validate().responseJSON { response in
                
            guard let data = response.result.value else{
                //self.refreshOAuth()
                //self.propertyChanged.raise(.NetworkError)
                return
            }
                
            let json = JSON(data)
                
            guard (json["error"].string != nil) else{

                //Get username to be displayed in input field
                guard let displayName = json["display_name"].string else{
                    return
                }

                completionHandler(displayName)

                return
            }
        }
    }

    typealias PropertyType = ObserverProperty
    let propertyChanged = Event<ObserverProperty>()
    
    //We'll need to access NSUserDefaults
    let defaults = UserDefaults.standard

    func login(_ username:String, password:String)
    {
        print("Login")
        
         Session.sharedInstance.ApiManager().request(siteUrl, method: .post, parameters: [
            "wpoauth_login": 1,
            "user_login":username,
            "user_password":password
            ]).validate().responseJSON { response in
                
//                //Use for debugging
//                print(response)
//                print(response.request ?? "no request")  // original URL request
//                print(response.response ?? "no response") // HTTP URL response
//                print(response.data ?? "no data")     // server data
//                print(response.result)
                
                guard let data = response.result.value else{
                    //Alert it there is a problem connecting to the host
                    print("Login")
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                let json = JSON(data)

                print("login")
                print(json)
                
               //Alert if there is a server-side login error
                guard let err = json["error"].string else{
                    self.runOAuth(json)

                    /*
                     * Save user ID in the event you want
                     * to use the WP REST API instead of
                     * the WP OAUTH2 server "me" endpoint
                     * to retrieve additional user data
                     */

                    guard let id = json["ID"].int else{
                        //Alert it ID can't be retrieved
                        self.propertyChanged.raise(.SaveError)
                        return
                    }
                    
                    self.saveUser(self.defaults, ID: id)
                    
                    return
                }
                
                self.propertyChanged.raise(ObserverProperty(rawValue: err)!)
        }
    }
    
    func runOAuth(_ json:JSON)
    {
        print("runOauth")
        
        Session.sharedInstance.ApiManager().request(siteUrl, method: .post, parameters: [
            "ios_wp_oauth": 1,
            "response_type":"code"
            ]).validate().responseJSON { response in
                
                guard let data = response.result.value else{
                     print("runOauth")
                    self.propertyChanged.raise(.NetworkError)
                    return
                }

                let json = JSON(data)
                
                //print("runOAuth")
                //print(json)
                
                //Make sure we have successfully retrieved the tokens
                guard !json["access_token"].isEmpty || !json["refresh_token"].isEmpty else{
                    self.propertyChanged.raise(.OAuthError)
                    return
                }

                //Save tokens
                guard let ac = json["access_token"].string, let rt = json["refresh_token"].string else{
                    self.propertyChanged.raise(.SaveError)
                    return
                }
                
                self.saveTokens(self.defaults, accessToken: ac,refreshToken:rt)
                self.propertyChanged.raise(.Success)
        }
    }
    
    func checkOauth()
    {
        print("Check OAuth")
        
        guard let accessToken = defaults.string(forKey: "accessToken") else {
            return
        }
        
        Session.sharedInstance.ApiManager().request(oauthLinks["me"]!, method: .post, parameters: [
            "access_token": accessToken
            ]).validate().responseJSON { response in

                switch response.result {
                case .success:
                    print("Validation Successful")
                    print(response)
                case .failure(let error):
                    print(error)
                    self.refreshOAuth()
                }
                
                guard let data = response.result.value else{
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                let json = JSON(data)
                
                //If Access Token is invalid, refresh
                guard json["error"] != nil else{
                    self.propertyChanged.raise(.Success)
                    return
                }
        }
    }
    
    func refreshOAuth()
    {
        print("Refreshing")
        
        guard let refreshToken = defaults.string(forKey: "refreshToken") else {
            return
        }
        
        Session.sharedInstance.ApiManager().request(oauthLinks["refresh"]!, method: .post, parameters: [
            "ios_wp_oauth": 2,
            "grant_type":"refresh_token",
            "refresh_token":refreshToken
            ]).validate().responseJSON { response in
                
            /*
            * Loose test for expired Refresh Token
            * This can also be a Network Error
            * Add checks accordingly
            */
                
            switch response.result {
            case .success(let value):

                let json = JSON(value)

                //print("Refresh JSON") //debug
                //print(json)

                 guard json["error"] != nil else{

                    guard let ac = json["access_token"].string, let rt = json["refresh_token"].string else{
                        self.propertyChanged.raise(.SaveError)
                        return
                    }
                    
                    self.saveTokens(self.defaults, accessToken: ac,refreshToken:rt)
                    self.propertyChanged.raise(.Success)
                    
                    return
                }
                
                /*
                * If Access token is not present or
                * if there is an issue
                * delete tokens for a fresh start
                */

                self.removeTokens(self.defaults)
                self.propertyChanged.raise(.Fail)
                
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func updateDisplayName(_ name:String)
    {
        print("Update Display Name")
        
        guard let accessToken = defaults.string(forKey: "accessToken") else {
            return
        }
        
        Session.sharedInstance.ApiManager().request(oauthLinks["update-me"]!, method: .post, parameters: [
            "access_token": accessToken,
            "name":name
            ]).responseJSON { response in
                
                switch response.result {
                case .success:
                    self.propertyChanged.raise(.Updated)
                    return
                case .failure:
                    self.propertyChanged.raise(.Fail)
                }
        
        }
    }
}

/*
 * Needful Extensions
 * Add more as needed for your project
 */

extension wpOAuthProtocol
{
    func removeTokens(_ defaults:UserDefaults){
        defaults.removeObject(forKey: "accessToken")
        defaults.removeObject(forKey: "refreshToken")
    }
    
    func saveUser(_ defaults:UserDefaults, ID:Int){
        defaults.set(ID, forKey: "wp_id")
    }
    
    func saveTokens(_ defaults:UserDefaults, accessToken:String, refreshToken:String){
        defaults.set(accessToken, forKey: "accessToken")
        defaults.set(refreshToken, forKey: "refreshToken")
    }
    
    func OauthAlert(_ alertMessage: String, vc:UIViewController)
    {
        let loginAlert = UIAlertController(title: "Alert:", message: alertMessage, preferredStyle: UIAlertControllerStyle.alert)
        
        let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default,handler: nil)
        
        loginAlert.addAction(okAction)
        
        if(vc.presentedViewController == nil){
            vc.present(loginAlert, animated: true, completion: nil)
        }
        
    }
}

