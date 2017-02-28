//
//  ProfileViewController.swift
//  iOS WP OAuth
//
//  Created by wlc on 1/12/16.
//  Copyright © 2016 wLc Designs. All rights reserved.
//

import UIKit
import Alamofire
import SwiftyJSON
import Spring

class ProfileViewController: UIViewController {
    
    //Display Name text field
    @IBOutlet weak var displayName: UITextField!
    
    //Call the wpOauth struct
    let wpRunOauth = wpOauth()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //RUN OAuth check
        wpRunOauth.checkOauth()
        
        wpRunOauth.getUserData(completionHandler: {
            name in
            
            print(name)
            
            self.displayName.text = name
        })
        
        //Handle events from check
        _ = wpRunOauth.propertyChanged.addHandler(self, handler: ProfileViewController.onPropertyChanged)
    }
    
    func onPropertyChanged(_ property: ObserverProperty) {
        
        switch(property){
        case .Success:
            
            wpRunOauth.getUserData(completionHandler: {
                name in
                
                self.displayName.text = name
            })
        break
            
        case .Fail:
            self.performSegue(withIdentifier: "LoginController", sender: self)
        break
            
        case .Updated:
            wpRunOauth.OauthAlert(property.rawValue, vc: self)
        break
            
        default:
            print("")
        }
    }
    
    @IBAction func updateDisplayName(_ sender: AnyObject) {
        
        if !displayName.text!.isEmpty { //Update Display Name
             wpRunOauth.updateDisplayName(displayName.text!)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
