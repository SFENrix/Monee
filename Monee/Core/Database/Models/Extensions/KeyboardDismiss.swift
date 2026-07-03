//
//  View+DismissKeyboard.swift
//  Monee
//
//  Core/Extensions/View+DismissKeyboard.swift
//
//  Tiny reusable modifier — tap anywhere on the view to resign first responder.
//  Uses `simultaneousGesture` (not `.onTapGesture` directly) so it doesn't
//  swallow taps meant for buttons, list rows, or text fields underneath it.
//

import SwiftUI

extension View {
    /// Dismisses the keyboard when the user taps anywhere on this view.
    /// Safe to stack on top of ScrollView, Form, List, etc. — it observes
    /// the tap, it doesn't intercept it.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        )
    }
}
