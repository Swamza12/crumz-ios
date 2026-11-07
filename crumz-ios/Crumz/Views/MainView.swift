import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Student Home Dashboard replicating `MainScreen.kt` 1:1:
/// - Dynamic time-of-day greeting ("Good morning,", "Good afternoon,", "Good evening,") + FIRST NAME ONLY
/// - Responsive top-right circular Logout button
/// - Overlapping CrumzGold credit card with pulsing green dot, full-to-empty progress bar, R15.00 buffer
/// - Quick Actions: Scan & Pay, Vendors, History (-> HistoryView)
/// - Recent Transactions: STRICTLY MAX 2 ITEMS + "More →" button + "View all transactions (N) →"
/// - 4-tab Bottom Navigation Bar: Home, Pay, Stores, Profile
struct MainView: View {
    let onItemClick: (NavRouteKey) -> Void
    let onLogoutClick: () -> Void

    @State private var studentNumber: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var balance: Double = 0.0
    @State private var allocatedLimit: Double = 0.0
    @State private var isActive: Bool = true
    @State private var bursaryName: String = ""
    @State private var createdAtMillis: Int64 = 0
    @State private var txns: [TxnRow] = []

    @State private var userListener: ListenerRegistration?
    @State private var approvedListener: ListenerRegistration?
    @State private var txnsListener: ListenerRegistration?
    @State private var boundStudentNumber: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TopHeroSectionView(
                        firstName: firstName,
                        studentNumber: studentNumber,
                        balance: balance,
                        allocatedLimit: allocatedLimit,
                        isActive: isActive,
                        onLogout: {
                            removeListeners()
                            try? Auth.auth().signOut()
                            onLogoutClick()
                        }
                    )

                    QuickActionsRowView(
                        onScanClick: { onItemClick(.scanQR) },
                        onVendorsClick: { onItemClick(.vendorsMap) },
                        onHistoryClick: { onItemClick(.history) }
                    )

                    RecentTransactionsSectionView(
                        txns: txns,
                        allocatedLimit: allocatedLimit,
                        bursaryName: bursaryName,
                        createdAtMillis: createdAtMillis,
                        onMoreClick: { onItemClick(.history) }
                    )
                }
            }
            .ignoresSafeArea(edges: .top)

            CrumzBottomNavigationBar(
                onPayClick: { onItemClick(.scanQR) },
                onStoresClick: { onItemClick(.vendorsMap) },
                onProfileClick: { onItemClick(.profile) }
            )
        }
        .background(Color.crumzSurface.ignoresSafeArea())
        .onAppear(perform: attachListeners)
        .onDisappear(perform: removeListeners)
    }

    private func attachListeners() {
        removeListeners()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        userListener = db.collection("users").document(uid).addSnapshotListener { snap, _ in
            guard let snap = snap, snap.exists, let data = snap.data() else { return }
            let sn = data["studentNumber"] as? String ?? ""
            studentNumber = sn
            if let fn = data["firstName"] as? String, !fn.isEmpty { firstName = fn }
            if let ln = data["lastName"] as? String, !ln.isEmpty { lastName = ln }
            let uBal = (data["balance"] as? NSNumber)?.doubleValue
            let uAlloc = (data["allocatedLimit"] as? NSNumber)?.doubleValue
            if let uBal = uBal, balance == 0.0 {
                balance = uBal
            }

            if !sn.isEmpty && sn != boundStudentNumber {
                boundStudentNumber = sn
                approvedListener?.remove()
                txnsListener?.remove()

                approvedListener = db.collection("approved_students").document(sn).addSnapshotListener { aSnap, _ in
                    guard let aSnap = aSnap, aSnap.exists, let aData = aSnap.data() else { return }
                    if let fn = aData["firstName"] as? String { firstName = fn }
                    if let ln = aData["lastName"] as? String { lastName = ln }
                    let aBal = (aData["balance"] as? NSNumber)?.doubleValue ?? uBal ?? 0.0
                    balance = aBal
                    allocatedLimit = (aData["allocatedLimit"] as? NSNumber)?.doubleValue ?? uAlloc ?? aBal
                    isActive = aData["isActive"] as? Bool ?? true
                    bursaryName = aData["bursaryName"] as? String ?? ""
                    if let ts = aData["created_at"] as? Timestamp {
                        createdAtMillis = Int64(ts.dateValue().timeIntervalSince1970 * 1000.0)
                    }
                }

                txnsListener = db.collection("transactions")
                    .whereField("studentNumber", isEqualTo: sn)
                    .addSnapshotListener { tSnap, _ in
                        let rows: [TxnRow] = tSnap?.documents.map { d in
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
                        txns = rows
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

// MARK: - Top Hero & Overlapping Gold Credit Card
private struct TopHeroSectionView: View {
    let firstName: String
    let studentNumber: String
    let balance: Double
    let allocatedLimit: Double
    let isActive: Bool
    let onLogout: () -> Void

    @State private var currentHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var pulseDot: Bool = false

    private let clockTimer = Timer.publish(every: 30.0, on: .main, in: .common).autoconnect()

    private var greeting: String {
        switch currentHour {
        case 0...11: return "Good morning,"
        case 12...17: return "Good afternoon,"
        default: return "Good evening,"
        }
    }

    /// Strict First-Name-Only rule (never last name or title)
    private var displayName: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !studentNumber.isEmpty { return studentNumber }
        return "Student"
    }

    private var limit: Double {
        allocatedLimit > 0.0 ? allocatedLimit : balance
    }

    private var spent: Double {
        max(0.0, limit - balance)
    }

    /// Full (1.0) when unspent (balance == limit), decreases toward 0.0 as money is spent
    private var remainingFraction: CGFloat {
        guard limit > 0.0 else { return 1.0 }
        return CGFloat(min(max(balance / limit, 0.0), 1.0))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Top Dark Blue Background Area
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Color.crumzDarkBlueLight
                        .clipShape(SelectiveRoundedCorner(radius: 32, corners: [.bottomLeft, .bottomRight]))

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.8))
                            Text(displayName)
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        // Responsive Circular Logout Button
                        Button(action: onLogout) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Logout")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 62)
                }
                .frame(height: 256)

                Spacer().frame(height: 84)
            }

            // Overlapping CrumzGold Credit Card
            VStack(alignment: .leading, spacing: 0) {
                // Status Dot + Label
                HStack(spacing: 8) {
                    Circle()
                        .fill(isActive ? Color(hex: 0x10B981).opacity(pulseDot ? 1.0 : 0.3) : Color.gray)
                        .frame(width: 10, height: 10)

                    Text("AVAILABLE CRUMZ CREDIT")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(Color.white.opacity(0.9))
                }

                Spacer()

                // Large Balance Display (supports negative buffer display e.g. -R2.00)
                HStack(alignment: .bottom, spacing: 0) {
                    let isNegative = balance < 0
                    let absBal = abs(balance)
                    let wholeInt = Int(floor(absBal + 1e-9))
                    let centsInt = Int(((absBal - Double(wholeInt)) * 100.0).rounded()) % 100

                    Text(isNegative ? "-R" : "R")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 6)
                        .padding(.trailing, 2)

                    Text("\(wholeInt)")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundColor(.white)

                    Text(String(format: ".%02d", centsInt))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 6)
                }

                Spacer()

                // Full-to-Empty Progress Bar
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 6)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, geo.size.width * remainingFraction), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(String(format: "Spent: R%.2f", spent))
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.9))
                        Spacer()
                        Text(String(format: "Allocated: R%.2f", limit))
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.9))
                    }
                }

                Spacer()

                // 3-Column Footer Details Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buffer limit")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.8))
                        Text("R15.00")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bursary / Scheme")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.8))
                        Text(limit > 0 ? "Monthly Cycle" : "Pending")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.8))
                        HStack(spacing: 4) {
                            Image(systemName: isActive ? "checkmark" : "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isActive ? Color(hex: 0x10B981) : Color(hex: 0xEF4444))
                            Text(isActive ? "Active" : "Deactivated")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isActive ? Color(hex: 0x10B981) : Color(hex: 0xEF4444))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(height: 185)
            .background(Color.crumzGold)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.crumzGold.opacity(0.45), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 24)
        }
        .onAppear {
            currentHour = Calendar.current.component(.hour, from: Date())
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseDot = true
            }
        }
        .onReceive(clockTimer) { now in
            currentHour = Calendar.current.component(.hour, from: now)
        }
    }
}

// MARK: - Quick Actions Row (Scan & Pay, Vendors, History)
private struct QuickActionsRowView: View {
    let onScanClick: () -> Void
    let onVendorsClick: () -> Void
    let onHistoryClick: () -> Void

    var body: some View {
        HStack {
            QuickActionCard(title: "Scan & Pay", systemIcon: "qrcode.viewfinder", isPrimary: true, action: onScanClick)
            Spacer()
            QuickActionCard(title: "Vendors", systemIcon: "storefront.fill", isPrimary: false, action: onVendorsClick)
            Spacer()
            QuickActionCard(title: "History", systemIcon: "doc.text.fill", isPrimary: false, action: onHistoryClick)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }
}

private struct QuickActionCard: View {
    let title: String
    let systemIcon: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(isPrimary ? .white : .crumzDarkBlue)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isPrimary ? .white : .crumzDarkBlue)
            }
            .frame(width: 100, height: 100)
            .background(isPrimary ? Color.crumzGold : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: isPrimary ? Color.crumzGold.opacity(0.35) : Color.black.opacity(0.06),
                radius: isPrimary ? 8 : 3,
                x: 0,
                y: isPrimary ? 4 : 2
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Transactions Section (STRICT MAX 2 ITEMS + "More →")
private struct RecentTransactionsSectionView: View {
    let txns: [TxnRow]
    let allocatedLimit: Double
    let bursaryName: String
    let createdAtMillis: Int64
    let onMoreClick: () -> Void

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
        VStack(alignment: .leading, spacing: 0) {
            // Header Row: "RECENT TRANSACTIONS" + clickable "More →"
            HStack {
                Text("RECENT TRANSACTIONS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(Color.crumzDarkBlue.opacity(0.7))

                Spacer()

                Button(action: onMoreClick) {
                    HStack(spacing: 3) {
                        Text("More")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.crumzGold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.crumzGold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            if txns.isEmpty && allocatedLimit <= 0.0 {
                Text("No recent transactions yet.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            } else {
                // Strictly cap at max 2 items total on homepage
                let purchasesToShow = Array(txns.prefix(2))
                ForEach(purchasesToShow) { t in
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

                // Only show Credit Loaded if purchasesToShow.count < 2
                let remainingSlots = 2 - purchasesToShow.count
                if remainingSlots > 0 && allocatedLimit > 0.0 {
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

                let totalCount = txns.count + (allocatedLimit > 0.0 ? 1 : 0)
                if totalCount > 2 {
                    Button(action: onMoreClick) {
                        Text("View all transactions (\(totalCount)) →")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.crumzDarkBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                } else if txns.isEmpty {
                    Text("No store purchases made yet.")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
            }

            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - 4-Tab Bottom Navigation Bar
private struct CrumzBottomNavigationBar: View {
    let onPayClick: () -> Void
    let onStoresClick: () -> Void
    let onProfileClick: () -> Void

    var body: some View {
        HStack {
            BottomNavTabItem(title: "Home", systemIcon: "house.fill", isSelected: true, action: {})
            BottomNavTabItem(title: "Pay", systemIcon: "qrcode.viewfinder", isSelected: false, action: onPayClick)
            BottomNavTabItem(title: "Stores", systemIcon: "storefront.fill", isSelected: false, action: onStoresClick)
            BottomNavTabItem(title: "Profile", systemIcon: "person.fill", isSelected: false, action: onProfileClick)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct BottomNavTabItem: View {
    let title: String
    let systemIcon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.crumzGold.opacity(0.12))
                            .frame(width: 56, height: 30)
                    }
                    Image(systemName: systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .crumzGold : .gray)
                }
                .frame(height: 30)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .crumzGold : .gray)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
