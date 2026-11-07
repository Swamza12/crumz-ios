import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Dedicated Transaction History Screen replicating `HistoryScreen.kt` 1:1:
/// - Statement Summary Card (First Name + Last Name with NO title, Student Number, "<N> Purchases" badge)
/// - 3-Column Metrics: Allocated Credit (#10B981), Total Spent (#F87171), Available Balance (CrumzGold)
/// - Full-width "Download PDF Statement" button generating multi-page A4 PDF
/// - Filter Chips: All, Purchases, Credits
struct HistoryView: View {
    let onBackClick: () -> Void

    @State private var profile = StudentProfile()
    @State private var balance: Double = 0.0
    @State private var allocatedLimit: Double = 0.0
    @State private var bursaryName: String = ""
    @State private var createdAtMillis: Int64 = 0
    @State private var txns: [TxnRow] = []
    @State private var selectedFilter: String = "All"
    @State private var toastMessage: String? = nil

    @State private var userListener: ListenerRegistration?
    @State private var approvedListener: ListenerRegistration?
    @State private var txnsListener: ListenerRegistration?
    @State private var boundStudentNumber: String = ""

    private var fullName: String {
        [profile.firstName, profile.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var totalSpent: Double {
        txns.reduce(0.0) { $0 + $1.amount }
    }

    private var dateTimeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy • HH:mm"
        return f
    }

    private var dateOnlyFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top App Bar
            HStack(spacing: 12) {
                Button(action: onBackClick) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Text("Transaction History")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.crumzDarkBlue.ignoresSafeArea(edges: .top))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Summary Card
                    VStack(spacing: 0) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fullName.isEmpty ? "Student Statement" : fullName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                if !profile.studentNumber.isEmpty {
                                    Text(profile.studentNumber)
                                        .font(.system(size: 13))
                                        .foregroundColor(Color.white.opacity(0.7))
                                }
                            }

                            Spacer()

                            Text("\(txns.count) Purchase\(txns.count == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.crumzGold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.crumzGold.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Spacer().frame(height: 18)
                        Divider().background(Color.white.opacity(0.12))
                        Spacer().frame(height: 16)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allocated Credit")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Text(String(format: "R%.2f", allocatedLimit))
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundColor(Color(hex: 0x10B981))
                            }

                            Spacer()

                            VStack(alignment: .center, spacing: 2) {
                                Text("Total Spent")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Text(String(format: "R%.2f", totalSpent))
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundColor(Color(hex: 0xF87171))
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Available Balance")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Text(balance < 0
                                     ? String(format: "-R%.2f", abs(balance))
                                     : String(format: "R%.2f", balance))
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundColor(.crumzGold)
                            }
                        }

                        Spacer().frame(height: 18)

                        Button(action: {
                            PDFStatementGenerator.generateAndPresent(
                                profile: profile,
                                fullName: fullName,
                                txns: txns
                            ) { msg in
                                toastMessage = msg
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Download PDF Statement")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.crumzGold)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(Color.crumzDarkBlueLight)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)

                    Spacer().frame(height: 20)

                    // Filter Chips
                    HStack(spacing: 10) {
                        ForEach(["All", "Purchases", "Credits"], id: \.self) { tab in
                            let selected = (selectedFilter == tab)
                            Button(action: { selectedFilter = tab }) {
                                Text(tab)
                                    .font(.system(size: 13, weight: selected ? .bold : .medium))
                                    .foregroundColor(selected ? .white : .crumzDarkBlue)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(selected ? Color.crumzDarkBlue : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(selected ? Color.clear : Color(hex: 0xCBD5E1), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    Spacer().frame(height: 14)

                    // Chronological Transactions List
                    let showPurchases = (selectedFilter == "All" || selectedFilter == "Purchases")
                    let showCredits = (selectedFilter == "All" || selectedFilter == "Credits") && allocatedLimit > 0.0

                    if showPurchases {
                        ForEach(txns) { t in
                            let dateStr = t.timeMillis > 0
                                ? dateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(t.timeMillis) / 1000.0))
                                : "Recent"
                            CrumzTransactionCard(
                                title: t.vendorName,
                                subtitle: "\(dateStr) • \(t.category)",
                                amount: String(format: "-R%.2f", t.amount),
                                amountColor: Color(hex: 0xEF4444),
                                systemIcon: crumzCategoryIcon(for: t.category)
                            )
                            Spacer().frame(height: 12)
                        }
                    }

                    if showCredits {
                        let allocDate = createdAtMillis > 0
                            ? dateOnlyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAtMillis) / 1000.0))
                            : "Approved Allocation"
                        let scheme = bursaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Crumz Allocation"
                            : bursaryName

                        CrumzTransactionCard(
                            title: "Credit Loaded",
                            subtitle: "\(allocDate) • \(scheme)",
                            amount: String(format: "+R%.2f", allocatedLimit),
                            amountColor: Color(hex: 0x10B981),
                            systemIcon: "creditcard.fill"
                        )
                        Spacer().frame(height: 12)
                    }

                    if (selectedFilter == "Purchases" && txns.isEmpty) ||
                       (selectedFilter == "Credits" && allocatedLimit <= 0.0) ||
                       (selectedFilter == "All" && txns.isEmpty && allocatedLimit <= 0.0) {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: 0xF1F5F9))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray)
                            }

                            Spacer().frame(height: 12)

                            Text(selectedFilter == "Purchases" ? "No store purchases made yet." : "No transactions recorded yet.")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.crumzDarkBlue)

                            Spacer().frame(height: 4)

                            Text("Every QR payment you make at a campus vendor will appear here immediately.")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    }

                    Spacer().frame(height: 24)
                }
                .padding(20)
            }
        }
        .background(Color.crumzSurface.ignoresSafeArea())
        .crumzToast($toastMessage)
        .onAppear(perform: attachListeners)
        .onDisappear(perform: removeListeners)
    }

    private func attachListeners() {
        removeListeners()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        userListener = db.collection("users").document(uid).addSnapshotListener { snap, _ in
            guard let snap = snap, snap.exists, let u = snap.data() else { return }
            let sn = u["studentNumber"] as? String ?? ""
            guard !sn.isEmpty else { return }

            let uBal = (u["balance"] as? NSNumber)?.doubleValue
            let uAlloc = (u["allocatedLimit"] as? NSNumber)?.doubleValue
            if let uBal = uBal, balance == 0.0 {
                balance = uBal
            }

            profile.studentNumber = sn
            if let fn = u["firstName"] as? String { profile.firstName = fn }
            if let ln = u["lastName"] as? String { profile.lastName = ln }

            if sn != boundStudentNumber {
                boundStudentNumber = sn
                approvedListener?.remove()
                txnsListener?.remove()

                approvedListener = db.collection("approved_students").document(sn).addSnapshotListener { aSnap, _ in
                    guard let aSnap = aSnap, aSnap.exists, let a = aSnap.data() else { return }
                    let aBal = (a["balance"] as? NSNumber)?.doubleValue ?? uBal ?? 0.0
                    balance = aBal
                    allocatedLimit = (a["allocatedLimit"] as? NSNumber)?.doubleValue ?? uAlloc ?? aBal
                    bursaryName = a["bursaryName"] as? String ?? ""
                    if let ts = a["created_at"] as? Timestamp {
                        createdAtMillis = Int64(ts.dateValue().timeIntervalSince1970 * 1000.0)
                    }
                    profile = StudentProfile(
                        studentNumber: sn,
                        firstName: a["firstName"] as? String ?? "",
                        lastName: a["lastName"] as? String ?? "",
                        title: "",
                        idNumber: a["idNumber"] as? String ?? "",
                        dateOfBirth: a["dateOfBirth"] as? String ?? "",
                        homeLanguage: a["homeLanguage"] as? String ?? "",
                        nationality: a["nationality"] as? String ?? "",
                        institution: a["institutionName"] as? String ?? "",
                        address: a["address"] as? String ?? "",
                        photoUrl: a["profileImgUrl"] as? String ?? "",
                        creditScore: (a["creditScore"] as? NSNumber)?.intValue,
                        isActive: a["isActive"] as? Bool ?? true
                    )
                }

                txnsListener = db.collection("transactions")
                    .whereField("studentNumber", isEqualTo: sn)
                    .addSnapshotListener { tSnap, _ in
                        txns = tSnap?.documents.map { d in
                            let td = d.data()
                            let tsMillis: Int64
                            if let ts = td["createdAt"] as? Timestamp {
                                tsMillis = Int64(ts.dateValue().timeIntervalSince1970 * 1000.0)
                            } else {
                                tsMillis = 0
                            }
                            return TxnRow(
                                id: d.documentID,
                                vendorName: td["vendorName"] as? String ?? "Vendor",
                                category: td["category"] as? String ?? "General",
                                amount: (td["amount"] as? NSNumber)?.doubleValue ?? 0.0,
                                timeMillis: tsMillis
                            )
                        }.sorted(by: { $0.timeMillis > $1.timeMillis }) ?? []
                    }
            }
        }
    }

    private func removeListeners() {
        userListener?.remove()
        approvedListener?.remove()
        txnsListener?.remove()
        userListener = nil
        approvedListener = nil
        txnsListener = nil
        boundStudentNumber = ""
    }
}
