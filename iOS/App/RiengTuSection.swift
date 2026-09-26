import SwiftUI

/// Tab Tính Năng → "Riêng tư": Lịch sử clipboard + Chế độ ẩn danh. Bàn phím đọc
/// cùng key qua App Group (ClipboardFeature.historyKey / incognitoKey).
struct RiengTuSection: View {
    @AppStorage("clipboardHistory", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var clipboardHistory = false
    @AppStorage("incognitoMode", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var incognitoMode = false

    var body: some View {
        Section {
            toggle("Lịch sử clipboard",
                   "Nút clipboard trên thanh gợi ý mở danh sách tối đa 20 mục vừa copy: chạm để dán, ghim để giữ lâu. Mục không ghim tự xoá sau 1 giờ (nội dung giống mật khẩu/OTP: 2 phút). Lưu chỉ trên máy, không gửi đi đâu. Nội dung vừa copy có số tài khoản / SĐT / OTP → thanh gợi ý hiện chip \"Dán STK…\".",
                   isOn: $clipboardHistory)
            if clipboardHistory {
                FullAccessNotice(reason: "Lịch sử clipboard")
                Text("Giới hạn iOS: bàn phím chỉ đọc được clipboard khi đang hiện và có Toàn quyền. Muốn tự ghi mục mới mà không bị hỏi mỗi lần: Cài đặt → VietTelex → Dán từ ứng dụng khác → Cho phép. Nếu không, mục chỉ được ghi khi bạn chạm Dán. Bỏ qua ô mật khẩu và nội dung trình quản lý mật khẩu đánh dấu ẩn.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            toggle("Chế độ ẩn danh",
                   "Khi bật: bàn phím không học từ bạn gõ và không lưu clipboard. Biểu tượng mắt gạch chéo hiện trên phím cách.",
                   isOn: $incognitoMode)
        } header: { Text("Riêng tư") } footer: {
            Text("Tắt Lịch sử clipboard sẽ xoá toàn bộ mục đã lưu ở lần mở bàn phím kế tiếp.")
        }
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
