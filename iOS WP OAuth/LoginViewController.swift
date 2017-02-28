//
//  LoginViewController.swift
//  iOS WP OAuth
//
//  Created by wlc on 1/19/16.
//  Copyright © 2016 wLc Designs. All rights reserved.
//

import UIKit

class LoginViewController: UIViewController {

    @IBOutlet weak var userName: UITextField!
    @IBOutlet weak var passWord: UITextField!
    
    //Call the wpOauth struct
    let wpRunOauth = wpOauth()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    func onPropertyChanged(_ property: ObserverProperty) {
        
        print(property)
        
        if property == .Success{
            self.performSegue(withIdentifier: "ProfileController", sender: self)
        }else{
            wpRunOauth.OauthAlert(property.rawValue, vc: self)
        }
    }
    
    @IBAction func loginWP(_ sender: AnyObject) {
        
        if !userName.text!.isEmpty && !passWord.text!.isEmpty {
            
            wpRunOauth.login(userName.text!, password:passWord.text!)
            
            _ = wpRunOauth.propertyChanged.addHandler(self, handler: LoginViewController.onPropertyChanged)
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}
