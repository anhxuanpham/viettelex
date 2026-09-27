import SwiftUI

/// Tính Năng → "Riêng tư & clipboard": Lịch sử clipboard + Chế độ ẩn danh. Bàn phím đọc
/// cùng key qua App Group (ClipboardFeature.historyKey / incognitoKey).
struct RiengTuSection: View {
    @AppStorage("clipboardHistory", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var clipboardHistory = false
    @AppStorage("incognitoMode", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var incognitoMode = false

    var body: some View {
        Section {
            toggle("Lịch sử clipboard",
                   "Nút clipboard trên thanh gợi ý mở 20 mục vừa copy; ghim để giữ lâu. Mục không ghim tự xoá sau 1 giờ (mật khẩu/OTP: 2 phút). Chỉ lưu trên máy.",
                   isOn: $clipboardHistory)
            if clipboardHistory {
                FullAccessNotice(reason: "Lịch sử clipboard")
                Text("iOS chỉ cho bàn phím đọc clipboard khi đang hiện và có Toàn quyền. Để tự ghi mục mới mà không bị hỏi: Cài đặt → VietTelex → Dán từ ứng dụng khác → Cho phép. Bỏ qua ô mật khẩu.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("Clipboard") } footer: {
            Text("Tắt Lịch sử clipboard sẽ xoá toàn bộ mục đã lưu ở lần mở bàn phím kế tiếp.")
        }
        Section {
            toggle("Chế độ ẩn danh",
                   "Bàn phím không học từ bạn gõ và không lưu clipboard.",
                   isOn: $incognitoMode)
        } header: { Text("Riêng tư") }
    }

    private func toggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .tint(.green)
    }
}
