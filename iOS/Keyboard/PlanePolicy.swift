/// Khi nào tự quay về plane CHỮ như stock iOS: đang ở plane 123/#+= mà đã gõ
/// ít nhất một ký tự, nhấn space → về chữ (feedback 26/09/2026: gõ "," xong
/// space vẫn kẹt ở 123). Ô số (keyboardType số) thì ở lại plane số.
enum PlanePolicy {
    static func returnToLettersOnSpace(inSymbolPlane: Bool, typedInPlane: Bool,
                                       numericField: Bool) -> Bool {
        inSymbolPlane && typedInPlane && !numericField
    }

    /// Chạm ABC (123/#+= → chữ): shift bật hay tắt. `autoShift` = viết hoa đầu câu
    /// đánh giá theo context LÚC CHẠM (nil = công tắc tắt / ô không viết hoa).
    /// Bug tester 1.2.x: gõ "." ở plane 123 + "Tự thêm dấu cách" → ". " rồi về ABC,
    /// code cũ ép shift = off vô điều kiện ⇒ chữ kế không viết hoa. Stock đánh giá lại.
    static func shiftOnReturnToLetters(autoShift: Bool?) -> Bool {
        autoShift ?? false
    }
}
