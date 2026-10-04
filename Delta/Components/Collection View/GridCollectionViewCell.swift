//
//  GridCollectionViewCell.swift
//  Delta
//
//  Created by Riley Testut on 10/21/15.
//  Copyright © 2015 Riley Testut. All rights reserved.
//

import UIKit

class GridCollectionViewCell: UICollectionViewCell
{
    let imageView = RoundedImageView()
    let textLabel = UILabel()
    
    @available(iOS 26.0, *)
    var isImageViewGlassEnabled: Bool {
        get { !self.glassView.isHidden }
        set { self.glassView.isHidden = !newValue }
    }
    
    var isInSelectionMode: Bool = false {
        didSet {
            self.updateSelectionIndicator()
        }
    }

    override var isSelected: Bool {
        didSet {
            self.updateSelectionIndicator()
        }
    }
    
    var isImageViewVibrancyEnabled = true {
        didSet {
            if self.isImageViewVibrancyEnabled
            {
                self.vibrancyView.contentView.addSubview(self.imageView)
            }
            else
            {
                self.contentView.addSubview(self.imageView)
            }

            self.contentView.bringSubviewToFront(self.selectionIndicatorView)
        }
    }
    
    var isTextLabelVibrancyEnabled = true {
        didSet {
            if self.isTextLabelVibrancyEnabled
            {
                self.labelVibrancyView.contentView.addSubview(self.textLabel)
            }
            else
            {
                self.contentView.addSubview(self.textLabel)
            }

            self.contentView.bringSubviewToFront(self.selectionIndicatorView)
        }
    }
    
    var maximumImageSize: CGSize = CGSize(width: 100, height: 100) {
        didSet {
            self.updateMaximumImageSize()
        }
    }
    
    private var glassView = UIVisualEffectView(effect: nil)
    private let selectionIndicatorView = UIImageView()
    private let vibrancyView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: UIBlurEffect(style: .dark)))
    private let labelVibrancyView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: UIBlurEffect(style: .dark)))
    
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    
    private var textLabelBottomAnchorConstraint: NSLayoutConstraint!
    
    private var textLabelVerticalSpacingConstraint: NSLayoutConstraint!
    private var textLabelFocusedVerticalSpacingConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.configureSubviews()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        self.configureSubviews()
    }
    
    private func configureSubviews()
    {
        // Fix super annoying Unsatisfiable Constraints message in debugger by setting autoresizingMask
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.clipsToBounds = false
        self.contentView.clipsToBounds = false
        
        self.glassView.isHidden = true
        self.glassView.translatesAutoresizingMaskIntoConstraints = false
        self.glassView.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.glassView)
        
        // Selection Indicator (for multi-select mode)
        self.selectionIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        self.selectionIndicatorView.image = UIImage(systemName: "circle")
        self.selectionIndicatorView.tintColor = .white
        self.selectionIndicatorView.isHidden = true
        self.selectionIndicatorView.contentMode = .scaleAspectFit

        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        self.selectionIndicatorView.preferredSymbolConfiguration = config

        self.vibrancyView.translatesAutoresizingMaskIntoConstraints = false
        self.vibrancyView.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.vibrancyView)
        
        self.labelVibrancyView.translatesAutoresizingMaskIntoConstraints = false
        self.labelVibrancyView.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.labelVibrancyView)
        
        self.imageView.contentMode = .scaleAspectFit
        #if os(tvOS)
            self.imageView.adjustsImageWhenAncestorFocused = true
        #endif
        self.contentView.addSubview(self.imageView)
        
        self.textLabel.font = UIFont.boldSystemFont(ofSize: 12)
        self.textLabel.textAlignment = .center
        self.textLabel.numberOfLines = 0
        self.contentView.addSubview(self.textLabel)

        // Add selection indicator last so it renders above the vibrancy layers and imageView.
        self.contentView.addSubview(self.selectionIndicatorView)
        
        if #available(iOS 26, *)
        {
            self.glassView.effect = UIGlassEffect(style: .clear)
            self.glassView.cornerConfiguration = .corners(radius: 5)
        }
        
        /* Auto Layout */
        
        // Glass View
        self.glassView.contentView.topAnchor.constraint(equalTo: self.glassView.topAnchor).isActive = true
        self.glassView.contentView.bottomAnchor.constraint(equalTo: self.glassView.bottomAnchor).isActive = true
        self.glassView.contentView.leadingAnchor.constraint(equalTo: self.glassView.leadingAnchor).isActive = true
        self.glassView.contentView.trailingAnchor.constraint(equalTo: self.glassView.trailingAnchor).isActive = true
        
        self.glassView.topAnchor.constraint(equalTo: self.imageView.topAnchor).isActive = true
        self.glassView.bottomAnchor.constraint(equalTo: self.imageView.bottomAnchor).isActive = true
        self.glassView.leadingAnchor.constraint(equalTo: self.imageView.leadingAnchor).isActive = true
        self.glassView.trailingAnchor.constraint(equalTo: self.imageView.trailingAnchor).isActive = true
        
        // Vibrancy View
        // Need to add explicit constraints for vibrancyView + vibrancyView.contentView or else Auto Layout won't calculate correct size 🙄
        self.vibrancyView.topAnchor.constraint(equalTo: self.contentView.topAnchor).isActive = true
        self.vibrancyView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor).isActive = true
        self.vibrancyView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor).isActive = true
        self.vibrancyView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor).isActive = true
        
        self.vibrancyView.contentView.topAnchor.constraint(equalTo: self.vibrancyView.topAnchor).isActive = true
        self.vibrancyView.contentView.bottomAnchor.constraint(equalTo: self.vibrancyView.bottomAnchor).isActive = true
        self.vibrancyView.contentView.leadingAnchor.constraint(equalTo: self.vibrancyView.leadingAnchor).isActive = true
        self.vibrancyView.contentView.trailingAnchor.constraint(equalTo: self.vibrancyView.trailingAnchor).isActive = true
        
        self.labelVibrancyView.topAnchor.constraint(equalTo: self.contentView.topAnchor).isActive = true
        self.labelVibrancyView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor).isActive = true
        self.labelVibrancyView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor).isActive = true
        self.labelVibrancyView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor).isActive = true
        
        self.labelVibrancyView.contentView.topAnchor.constraint(equalTo: self.labelVibrancyView.topAnchor).isActive = true
        self.labelVibrancyView.contentView.bottomAnchor.constraint(equalTo: self.labelVibrancyView.bottomAnchor).isActive = true
        self.labelVibrancyView.contentView.leadingAnchor.constraint(equalTo: self.labelVibrancyView.leadingAnchor).isActive = true
        self.labelVibrancyView.contentView.trailingAnchor.constraint(equalTo: self.labelVibrancyView.trailingAnchor).isActive = true
        
        // Selection Indicator
        self.selectionIndicatorView.topAnchor.constraint(equalTo: self.imageView.topAnchor, constant: 4).isActive = true
        self.selectionIndicatorView.trailingAnchor.constraint(equalTo: self.imageView.trailingAnchor, constant: -4).isActive = true
        self.selectionIndicatorView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        self.selectionIndicatorView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Image View
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        
        self.imageView.topAnchor.constraint(equalTo: self.contentView.topAnchor).isActive = true
        self.imageView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor).isActive = true
        
        self.imageViewWidthConstraint = self.imageView.widthAnchor.constraint(equalToConstant: self.maximumImageSize.width)
        self.imageViewWidthConstraint.isActive = true
        
        self.imageViewHeightConstraint = self.imageView.heightAnchor.constraint(equalToConstant: self.maximumImageSize.height)
        self.imageViewHeightConstraint.priority = UILayoutPriority(999) // Fixes "Unable to simultaneously satisfy constraints" runtime error when inserting new grid row.
        self.imageViewHeightConstraint.isActive = true
        
        
        // Text Label
        self.textLabel.translatesAutoresizingMaskIntoConstraints = false
        
        self.textLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor).isActive = true
        self.textLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor).isActive = true
        
        self.textLabelBottomAnchorConstraint = self.textLabel.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)
        self.textLabelBottomAnchorConstraint.isActive = true
        
        self.textLabelVerticalSpacingConstraint = self.textLabel.topAnchor.constraint(equalTo: self.imageView.bottomAnchor)
        self.textLabelVerticalSpacingConstraint.isActive = true
        
        
        #if os(tvOS)
            self.textLabelVerticalSpacingConstraint.active = false
            
            self.textLabelFocusedVerticalSpacingConstraint = self.textLabel.topAnchor.constraintEqualToAnchor(self.imageView.focusedFrameGuide.bottomAnchor, constant: 0)
            self.textLabelFocusedVerticalSpacingConstraint?.active = true
        #else
            self.textLabelVerticalSpacingConstraint.isActive = true
        #endif
        
        
        self.updateMaximumImageSize()
    }
    
    override func prepareForReuse()
    {
        super.prepareForReuse()
        self.isInSelectionMode = false
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator)
    {
        super.didUpdateFocus(in: context, with: coordinator)
        
        coordinator.addCoordinatedAnimations({
            
            if context.nextFocusedView == self
            {
                self.textLabelBottomAnchorConstraint?.isActive = false
                self.textLabelVerticalSpacingConstraint.isActive = false
                
                self.textLabelFocusedVerticalSpacingConstraint?.isActive = true
                
                self.textLabel.textColor = UIColor.white
                
            }
            else
            {
                self.textLabelFocusedVerticalSpacingConstraint?.isActive = false
                
                self.textLabelBottomAnchorConstraint?.isActive = true
                self.textLabelVerticalSpacingConstraint.isActive = true
                
                self.textLabel.textColor = UIColor.black
            }
            
            self.layoutIfNeeded()
            
            }, completion: nil)
    }
}

private extension GridCollectionViewCell
{
    func updateMaximumImageSize()
    {
        self.imageViewWidthConstraint.constant = self.maximumImageSize.width
        self.imageViewHeightConstraint.constant = self.maximumImageSize.height

        self.textLabelVerticalSpacingConstraint.constant = 8
        self.textLabelFocusedVerticalSpacingConstraint?.constant = self.maximumImageSize.height / 10.0
    }

    func updateSelectionIndicator()
    {
        guard self.isInSelectionMode else {
            self.selectionIndicatorView.isHidden = true
            return
        }

        if self.isSelected
        {
            self.selectionIndicatorView.image = UIImage(systemName: "checkmark.circle.fill")
            self.selectionIndicatorView.tintColor = .deltaPurple
        }
        else
        {
            self.selectionIndicatorView.image = UIImage(systemName: "circle")
            self.selectionIndicatorView.tintColor = .white
        }

        self.selectionIndicatorView.isHidden = false
    }
}
