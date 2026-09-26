// Từ điển cá nhân: xem/tìm/xoá từ bàn phím đã học, thêm tay tên riêng/thuật ngữ.
//
// Dữ liệu: bàn phím ghi userlm.plist vào App Group (UserLangModel). iOS chỉ cho extension
// GHI App Group khi có "Cho phép Toàn quyền" — không có thì bàn phím vẫn học trong phiên
// nhưng không lưu được, màn này trống (hiện nhắc). App mở cùng file bằng UserLangModel
// (Keyboard/UserLangModel.swift biên dịch chung vào app), sửa, ghi đồng bộ, rồi đổi mốc
// "userlmResetAt" trong App Group — lần hiện kế tiếp bàn phím thấy mốc đổi thì bỏ bảng
// trong RAM (không ghi đè bản app vừa sửa) và nạp lại file.
import SwiftUI

enum UserDictStore {
    static let group = UserDefaults(suiteName: "group.com.viettelex")

    static func signalKeyboard() {
        group?.set(Date().timeIntervalSince1970, forKey: "userlmResetAt")
    }

    static func eraseAll() {
        if let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("userlm.plist"))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("userlm.json"))
        }
        signalKeyboard()
    }
}

struct UserDictView: View {
    @State private var model = UserLangModel.openSharedForEditing()
    @State private var entries: [UserLangModel.Entry] = []
    @State private var total = 0
    @State private var query = ""
    @State private var newWord = ""
    @State private var notice: String?
    @State private var confirmErase = false

    private var fullAccess: Bool { UserDictStore.group?.bool(forKey: "kbFullAccess") == true }

    private func reload() {
        entries = model?.entries(query: query) ?? []
        total = model?.entries().count ?? 0
    }

    private func commit() {
        model?.saveSync()
        UserDictStore.signalKeyboard()
        reload()
    }

    var body: some View {
        List {
            if !fullAccess {
                Section {
                    Text("Bàn phím chỉ lưu được từ đã học khi bật \"Cho phép Toàn quyền\" (Cài đặt → Chung → Bàn phím → Bàn phím → VietTelex). Từ thêm tay ở đây vẫn dùng được.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    TextField("VD: Kubernetes", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Thêm từ") } footer: {
                Text(notice ?? "Tên riêng, thuật ngữ… (một từ, chỉ chữ cái). Từ thêm tay được gợi ý ngay khi gõ vài chữ đầu.")
            }

            Section {
                ForEach(entries, id: \.word) { e in
                    HStack {
                        Text(e.word)
                        Spacer()
                        Text(e.manual ? "thêm tay" : "\(e.count)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    for i in idx { model?.removeWord(entries[i].word) }
                    commit()
                }
                if entries.isEmpty {
                    Text(query.isEmpty ? "Chưa có từ nào — gõ bằng VietTelex để bàn phím học." : "Không có từ khớp.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(query.isEmpty ? "Từ đã học (\(total))" : "Kết quả (\(entries.count))")
            } footer: {
                Text("Vuốt trái để xoá — xoá một từ cũng xoá các cặp/bộ ba từ đi kèm nó. Mọi dữ liệu chỉ nằm trên máy.")
            }

            Section {
                Button(confirmErase ? "Chạm lần nữa để xoá tất cả" : "Xoá tất cả từ đã học", role: .destructive) {
                    guard confirmErase else { confirmErase = true; return }
                    confirmErase = false
                    UserDictStore.eraseAll()
                    model = UserLangModel.openSharedForEditing()
                    reload()
                }
            }
        }
        .searchable(text: $query, prompt: "Tìm từ")
        .onChange(of: query) { _ in reload() }
        .navigationTitle("Từ điển cá nhân")
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarScrollMargin()
        .onAppear(perform: reload)
    }

    private func add() {
        let w = newWord
        guard let m = model else { notice = "Không mở được dữ liệu (App Group)."; return }
        if m.addWord(w) {
            notice = "Đã thêm “\(w.trimmingCharacters(in: .whitespaces))”."
            newWord = ""
            commit()
        } else {
            notice = "Chỉ nhận một từ gồm chữ cái (tối đa \(UserLangModel.manualMaxLen) ký tự)."
        }
    }
}
