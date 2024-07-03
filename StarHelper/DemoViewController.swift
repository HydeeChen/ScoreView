//
//  DemoViewController.swift
//  StarHelper
//
//  Created by Hydee Chen on 2024/6/18.
//

import UIKit

class DemoViewController: UIViewController {

    @IBOutlet weak var score: UILabel!
    var scoreView: MyScoreView?
    override func viewDidLoad() {
        super.viewDidLoad()
        let input = MyScoreViewInput (numberOfButtons: 3,
                                      imageOfNormalButtons: "tiredCat",
                                      imageOfIsSelectedButtons: "orangeCat",
                                      sizeOfButtons: CGSize(width: 70, height: 70),
                                      spaceOfButtons: 16
        )
        
        
        scoreView = MyScoreView()
        scoreView?.setupView(input: input)
        scoreView?.frame = CGRect(x: 0, y: 200, width: (scoreView?.frame.width)!, height: (scoreView?.frame.height)!)
        view.addSubview(scoreView!)
        scoreView?.buttonCountHandler = { buttonCount in
            self.score.text = "\(buttonCount)"
        }
        
    }

    @IBAction func reset(_ sender: Any) {
        scoreView?.resetButtons()
    }
    
}
