import SwiftUI
import UIKit

/// Fondo del teclado (color, degradado o foto) dibujado con UIKit debajo de todo. Así las teclas,
/// que van encima en UIKit, no tienen que atravesar SwiftUI para verse ni para tocarse.
final class KeyboardBackgroundView: UIView {
    private let gradient = CAGradientLayer()
    private let imageView = UIImageView()
    private let dimView = UIView()
    private var appliedKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.actions = ["colors": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer.addSublayer(gradient)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        addSubview(dimView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        imageView.frame = bounds
        dimView.frame = bounds
    }

    /// Igual que el fondo que antes dibujaba SwiftUI: foto con velo, degradado o color liso.
    func apply(palette: KeyboardPalette, photo: UIImage?, dim: Double) {
        if let photo {
            let key = "photo-\(ObjectIdentifier(photo).hashValue)-\(dim)"
            guard key != appliedKey else { return }
            appliedKey = key
            backgroundColor = .clear
            gradient.isHidden = true
            imageView.image = photo
            imageView.isHidden = false
            dimView.isHidden = false
            dimView.backgroundColor = UIColor.black.withAlphaComponent(dim)
        } else if let colors = palette.gradient {
            let cgColors = colors.map { UIColor($0).cgColor }
            backgroundColor = .clear
            imageView.isHidden = true
            imageView.image = nil
            dimView.isHidden = true
            gradient.isHidden = false
            gradient.colors = cgColors
            appliedKey = ""
        } else {
            imageView.isHidden = true
            imageView.image = nil
            dimView.isHidden = true
            gradient.isHidden = true
            backgroundColor = UIColor(palette.background)
            appliedKey = ""
        }
    }
}
