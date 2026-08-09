//
//  AmazonSupport.swift
//  Pantry Link IOS
//
//  Helpers for the Amazon-fulfillment flow: an in-app Safari sheet for viewing a listing without
//  leaving the app, link normalization/validation, and compact base64 encoding of the donor's
//  order-confirmation image (stored on the claim doc in Firestore, so no Firebase Storage needed).
//

import SwiftUI
import SafariServices
import UIKit

// MARK: - In-app Safari (view an Amazon listing without leaving the app)

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Color.pantryPrimary)
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - Amazon link normalization / validation

enum AmazonLink {
    /// Turn a user-entered string into a valid https URL. Accepts links pasted without a scheme
    /// (e.g. "amazon.com/dp/..." or "a.co/d/...") and rejects anything that isn't a real web URL.
    static func normalized(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https", u.host != nil {
            return u
        }
        if let u = URL(string: "https://\(s)"), u.host != nil, u.host?.contains(".") == true {
            return u
        }
        return nil
    }

    static func isValid(_ raw: String) -> Bool { normalized(raw) != nil }
}

// MARK: - Receipt image (compressed base64 JPEG, stored on the claim)

enum ReceiptImage {
    /// Downscale + JPEG-compress so the base64 payload stays well under Firestore's ~1 MB doc limit.
    static func encode(_ image: UIImage, maxDimension: CGFloat = 1000, quality: CGFloat = 0.5) -> String? {
        let scaled = downscale(image, maxDimension: maxDimension)
        guard var data = scaled.jpegData(compressionQuality: quality) else { return nil }
        // If it's still heavy, keep squeezing quality down to a floor.
        var q = quality
        while data.count > 650_000 && q > 0.15 {
            q -= 0.1
            guard let smaller = scaled.jpegData(compressionQuality: q) else { break }
            data = smaller
        }
        return data.base64EncodedString()
    }

    static func decode(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
