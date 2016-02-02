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
 * Try prepending "www" if your-secure-domain.com doesn't work
 */

let serverTrustPolicies: [String: ServerTrustPolicy] = [
    "your-secure-domain.com": .PinCertificates(
        certificates: ServerTrustPolicy.certificatesInBundle(),
        validateCertificateChain: true,
        validateHost: true
    )
]

//Add certificate pinning to Alamofire
let manager = Manager(
    configuration: NSURLSessionConfiguration.defaultSessionConfiguration(),
    serverTrustPolicyManager: ServerTrustPolicyManager(policies: serverTrustPolicies)
)

//Site Url: this is a full link, not a domain
let siteUrl = "https://your-secure-domain.com/" //include forward slash at the end

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
    typealias PropertyType
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
    func login(username:String, password:String)
    
    //Run OAuth after successful login
    func runOAuth(json:JSON)
    
    //Fetch User data after successful retreival of OAuth tokens
    func getUserData(completionHandler:(String) -> ()) -> ()
    
    //Check if Access Token is still valid
    func checkOauth()
    
    /*
     * If Access Token is not valid, 
     * use the Refresh Token to fetch another Access Token
     */
    
    func refreshOAuth()
    
    //After token checks, update Display Name
    func updateDisplayName(name:String)
    
}

//Create struct based on wpOAuthProtocol protocol
struct wpOauth: wpOAuthProtocol, 🕵
{
    typealias PropertyType = ObserverProperty
    let propertyChanged = Event<ObserverProperty>()
    
    //We'll need to access NSUserDefaults
    let defaults = NSUserDefaults.standardUserDefaults()

    func login(username:String, password:String)
    {
        manager.request(.POST, siteUrl, parameters: [
            "ios_wp_login": 1,
            "ios_userlogin":username,
            "ios_userpassword":password
            ]).responseJSON { response in
                
                //Use for debugging
                print(response.request)  // original URL request
                print(response.response) // URL response
                //print(response.data)     // server data
                print(response.result)   // result of response serialization
                print(response.result.value)
                
                guard let data = response.result.value else{
                    //Alert it there is a problem connecting to the host
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                let json = JSON(data)
                
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
    
    func runOAuth(json:JSON)
    {
        manager.request(.POST, siteUrl, parameters: [
            "ios_wp_oauth": 1,
            "response_type": "code",
            ]).responseJSON { response in
                
                guard let data = response.result.value else{
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                let json = JSON(data)
                                
                guard let code = json["code"].int where code == 200 else{
                    //Alert it there is a problem connecting to the host
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                //Make sure we have successfully retrieved the tokens
                guard json["result"]["access_token"].isEmpty || json["result"]["refresh_token"].isEmpty else{
                    self.propertyChanged.raise(.OAuthError)
                    return
                }
                
                //Save tokens
                guard let ac = json["result"]["access_token"].string, let rt = json["result"]["refresh_token"].string else{
                    self.propertyChanged.raise(.SaveError)
                    return
                }
                
                self.saveTokens(self.defaults, accessToken: ac,refreshToken:rt)
                self.propertyChanged.raise(.Success)
        }
        
    }
    
    func getUserData(completionHandler: (String) -> ()) -> ()
    {
        ///get tokens function
        guard let accessToken = defaults.stringForKey("accessToken") else {
            return
        }
        
        manager.request(.POST, oauthLinks["me"]!, parameters: [
            "access_token": accessToken
            ]).responseJSON { response in
                
                guard let data = response.result.value else{
                    self.propertyChanged.raise(.NetworkError)
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
    
    func checkOauth()
    {
        guard let accessToken = defaults.stringForKey("accessToken") else {
            return
        }
        
        manager.request(.POST, oauthLinks["me"]!, parameters: [
            "access_token": accessToken
            ]).responseJSON { response in
                                
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
                
                self.refreshOAuth()
                
        }
    }
    
    func refreshOAuth()
    {
        guard let refreshToken = defaults.stringForKey("refreshToken") else {
            return
        }
        
        manager.request(.POST, oauthLinks["refresh"]!, parameters: [
            "ios_wp_oauth": 2,
            "grant_type":"refresh_token",
            "refresh_token":refreshToken
            ]).responseJSON { response in
                
                /*
                * Loose test for expired Refresh Token
                * This can also be a Network Error
                * Add checks accordingly
                */
                
                guard let data = response.result.value else{
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                let json = JSON(data)

                guard json["error"] != nil else{
                    
                    guard let accessToken = json["access_token"].string else{
                        self.propertyChanged.raise(.Fail)
                        
                        /*
                        * If Access token is not present or
                        * if there is an issue
                        * delete tokens for a fresh start
                        */
                        
                        self.removeTokens(self.defaults)
                        return
                    }
                    
                    //Set New Access Token
                    self.defaults.setObject(accessToken, forKey: "accessToken")
                    self.propertyChanged.raise(.Success)
                    return
                }
                
                /*
                * If there is a refresh error
                * delete tokens for a fresh start
                */
                
                self.removeTokens(self.defaults)
                self.propertyChanged.raise(.Fail)
                
        }
    }
    
    func updateDisplayName(name:String)
    {
        guard let accessToken = defaults.stringForKey("accessToken") else {
            return
        }
        
        manager.request(.POST, oauthLinks["update-me"]!, parameters: [
            "access_token": accessToken,
            "name":name
            ]).responseJSON { response in
                
                guard let data = response.result.value else{
                    self.propertyChanged.raise(.NetworkError)
                    return
                }
                
                let json = JSON(data)
                
                guard (json["error"].string != nil) else{
                    //Alert is Display name update was successful
                    self.propertyChanged.raise(.Updated)
                    return
                }
                
                self.propertyChanged.raise(.Fail)
                
        }
    }
}

/*
 * Needful Extensions
 * Add more as needed for your project
 */

extension wpOAuthProtocol
{
    func removeTokens(defaults:NSUserDefaults){
        defaults.removeObjectForKey("accessToken")
        defaults.removeObjectForKey("refreshToken")
    }
    
    func saveUser(defaults:NSUserDefaults, ID:Int){
        defaults.setObject(ID, forKey: "wp_id")
    }
    
    func saveTokens(defaults:NSUserDefaults, accessToken:String, refreshToken:String){
        defaults.setObject(accessToken, forKey: "accessToken")
        defaults.setObject(refreshToken, forKey: "refreshToken")
    }
    
    func OauthAlert(alertMessage: String, vc:AnyObject)
    {
        let loginAlert = UIAlertController(title: "Alert:", message: alertMessage, preferredStyle: UIAlertControllerStyle.Alert)
        
        let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default,handler: nil)
        
        loginAlert.addAction(okAction)
        
        vc.presentViewController(loginAlert, animated: true, completion: nil)
    }
}

