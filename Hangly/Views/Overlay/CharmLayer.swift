//
//  CharmLayer.swift
//  Hangly
//
//  One charm as it should be drawn this frame.
//

/// A charm plus how far through a change it is.
///
/// Switching charms draws two layers for a moment: the outgoing one fading out and
/// the incoming one fading in and growing into place. Modelling it as a list means
/// the renderer has no idea a transition is happening; it just draws what it is given.
///
/// The artwork is built once when the layer is created, not once per frame. A
/// vector charm is dozens of `CGPath`s and building them 120 times a second was the
/// single largest avoidable cost in the render loop.
struct CharmLayer {
    let charm: any Charm

    /// Geometry, resolved once for the life of the layer.
    let artwork: CharmArtwork

    /// Zero to one.
    let opacity: Double

    /// Multiplier on the charm's radius, used for the settle-in pop.
    let scale: Double

    init(charm: any Charm, artwork: CharmArtwork? = nil, opacity: Double, scale: Double) {
        self.charm = charm
        self.artwork = artwork ?? charm.hangingArtwork()
        self.opacity = opacity
        self.scale = scale
    }
}
