//
//  CGSize+Hangly.swift
//  Hangly
//

import CoreGraphics

extension CGSize {
    /// Returns the size multiplied by `factor`, rounded to whole points so the
    /// overlay never lands on a half-pixel boundary.
    func scaled(by factor: Double) -> CGSize {
        CGSize(
            width: (width * factor).rounded(),
            height: (height * factor).rounded()
        )
    }
}
