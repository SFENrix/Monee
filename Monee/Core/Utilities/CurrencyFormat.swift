//
//  CurrencyFormat.swift
//  Monee
//
//  Created by Rio Ferdinand on 03/07/26.
//

//
//  CurrencyFormat.swift
//  Monee
//
//  Core/Utilities/CurrencyFormat.swift
//
//  Centralizes IDR formatting so it's defined once, not scattered as literal "$" prefixes
//  across ~8 files. Rupiah is conventionally shown with NO decimal places (Rp150.000, not
//  Rp150.000,00) even though ISO 4217 technically defines 2 fraction digits for IDR —
//  .precision(.fractionLength(0)) overrides that. Locale pinned to id_ID explicitly so
//  formatting is consistent regardless of the test device's Region setting.
//

import Foundation

extension FloatingPointFormatStyle<Double>.Currency {
    /// Usage: `Text(amount, format: .idr)` or `TextField("Amount", value: $amount, format: .idr)`
    static var idr: Self {
        .currency(code: "IDR")
            .locale(Locale(identifier: "id_ID"))
            .precision(.fractionLength(0))
    }
}

extension Double {
    /// For plain-string contexts outside SwiftUI (PromptBuilder, AIChatViewModel's
    /// AI-context builder) — same formatting via string interpolation.
    var idrFormatted: String {
        self.formatted(.idr)
    }
}
