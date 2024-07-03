//
//  MyScoreView.swift
//  StarHelper
//
//  Created by Hydee Chen on 2024/6/18.
//

import Foundation
import UIKit

public struct MyScoreViewInput {
    let numberOfButtons: Int
    let imageOfNormalButtons: String
    let imageOfIsSelectedButtons: String
    let sizeOfButtons: CGSize
    let spaceOfButtons: CGFloat
}

public class MyScoreView: UIView {
    public var input: MyScoreViewInput?
    public var numberOfButtons: Int = 0
    public var sizeOfButtons: CGSize = .zero
    public var sizeOfMyScoreView: CGSize = .zero
    public var buttonCountHandler: ((Int) -> Void)?
    private var buttonsArray: [UIButton] = []
    
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let gestureView = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(stackView)
        addSubview(gestureView)
        
    }
    
    // required' initializer 'init(coder:)' must be provided by subclass of 'UIView
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    public func setupView(input: MyScoreViewInput) {
        self.input = input
        
        // 設定stackView UI
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = input.spaceOfButtons
        
        // 設定手勢感應區gestureView的功能tap及pan
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        gestureView.addGestureRecognizer(panGestureRecognizer)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(gestureViewTapped(_:)))
        gestureView.addGestureRecognizer(tapGestureRecognizer)
        
        
        // 設定按鈕 UI
        numberOfButtons = input.numberOfButtons
        buttonsArray.removeAll()
        for index in 0 ..< numberOfButtons {
            let button = UIButton()
            button.tag = index
            // 將以上array裡面的按鈕做protocol的設定，包含未選中、選中
            let normalImage = UIImage(named: input.imageOfNormalButtons)
            let selectedImage = UIImage(named: input.imageOfIsSelectedButtons)

            button.setImage(normalImage, for: .normal)
            button.setImage(selectedImage, for: .selected)
            button.imageView?.contentMode = .scaleAspectFit
            
            // 設定buttons大小
            sizeOfButtons = input.sizeOfButtons
            button.frame.size = sizeOfButtons
            
            // 依據加進stackView裡面
            stackView.addArrangedSubview(button)
            buttonsArray.append(button)
        }
        
        stackView.frame = CGRect(x: 0, y: 0,
                                 width: (sizeOfButtons.width + input.spaceOfButtons) * CGFloat(numberOfButtons) - input.spaceOfButtons,
                                 height: sizeOfButtons.height)
        self.frame = stackView.frame
        gestureView.frame = stackView.frame
        
    }
    
    public func updateButtonCount(numberOfButtons: Int, selectedCount: Int) {
            // 移除舊的按鈕
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            buttonsArray.removeAll()
            
            // 設定新的按鈕數量
            self.numberOfButtons = numberOfButtons
            
            // 創建新的按鈕
            for index in 0 ..< numberOfButtons {
                let button = UIButton()
                button.tag = index
                
                let normalImage = UIImage(named: input?.imageOfNormalButtons ?? "")
                let selectedImage = UIImage(named: input?.imageOfIsSelectedButtons ?? "")
                
                button.setImage(normalImage, for: .normal)
                button.setImage(selectedImage, for: .selected)
                button.imageView?.contentMode = .scaleAspectFit
                
                // 設置按鈕的選中狀態
                button.isSelected = index < selectedCount
                button.frame.size = sizeOfButtons
                
                stackView.addArrangedSubview(button)
                buttonsArray.append(button)
            }
            
            // 更新 stackView 的框架
            stackView.frame = CGRect(x: 0, y: 0,
                                     width: (sizeOfButtons.width + (input?.spaceOfButtons ?? 0)) * CGFloat(numberOfButtons) - (input?.spaceOfButtons ?? 0),
                                     height: sizeOfButtons.height)
            self.frame = stackView.frame
            gestureView.frame = stackView.frame
        }
    
    @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        
        let location = gesture.location(in: gestureView)
        
        // 根據手勢狀態進行處理
        switch gesture.state {
        case .began, .changed, .ended:
            // 計算最近的星級數
            let buttonCount = calculateStarCount(for: location)
            
            // 更新星級狀態
            updateStarsBasedOnLocation(location)
            
            // 在 ended 狀態時，啟用 tap 手勢並回傳值
            if gesture.state == .ended {
                gesture.view?.gestureRecognizers?.forEach { recognizer in
                    if recognizer is UITapGestureRecognizer {
                        recognizer.isEnabled = true
                    }
                }
                buttonCountHandler?(buttonCount)
            } else if gesture.state == .began {
                // 避免與 tap 手勢衝突，在 pan 執行時關閉 tap 手勢
                gesture.view?.gestureRecognizers?.forEach { recognizer in
                    if recognizer is UITapGestureRecognizer {
                        recognizer.isEnabled = false
                    }
                }
            }
            
            // Debug 輸出手勢狀態和位置
            print("hydeeTest", gesture.state.rawValue, gesture.location(in: gestureView))
            buttonCountHandler?(buttonCount)
            
        default:
            let buttonCount = calculateStarCount(for: location)
            updateStarsBasedOnLocation(location)
            buttonCountHandler?(buttonCount)
        }
    }
    
    @objc func gestureViewTapped(_ gesture: UITapGestureRecognizer) {
        
        let location = gesture.location(in: gestureView)
        let buttonCount = calculateStarCount(for: location)
        buttonCountHandler?(buttonCount)
        updateStarsBasedOnLocation(location)
    }
    
    
    // 依據滑動的區間更新星星
    func updateStarsBasedOnLocation(_ location: CGPoint) {
        // 計算每個按鈕的寬度範圍
        let buttonWidth = gestureView.bounds.width / CGFloat(buttonsArray.count)
        
        // 計算觸控位置所在的按鈕索引
        let index = Int(location.x / buttonWidth)
        
        // 更新星星按鈕狀態
        for (i, button) in buttonsArray.enumerated() {
            button.isSelected = i <= index
        }
    }
    
    func calculateStarCount(for location: CGPoint) -> Int {
        // 確保在點擊星星按鈕之間的區域時，回傳最接近的星星數
        var closestButton: UIButton?
        var minimumDistance: CGFloat = CGFloat.greatestFiniteMagnitude
        
        for button in buttonsArray {
                let buttonFrame = button.frame
                let buttonCenter = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
                let distance = hypot(buttonCenter.x - location.x, buttonCenter.y - location.y)
                if distance < minimumDistance {
                    minimumDistance = distance
                    closestButton = button
                }
            }
        
        if let closestButton = closestButton, let index = buttonsArray.firstIndex(of: closestButton) {
            return index + 1
        }
        
        return 0
    }
    
    
    // 用於重新評分按鈕
    func resetButtons() {
        buttonsArray.forEach {
            $0.isSelected = false
        }
    }
}
