import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Student Profile Screen replicating `ProfileScreen.kt` 1:1:
/// - Circular 112x112 pt Gold-bordered avatar (`AsyncImage` + initials fallback)
/// - STRICT NO-FORMALITIES RULE: Displays ONLY `firstName + " " + lastName` and `studentNumber` (no Mr/Ms/Mrs)
/// - 270° Arc Credit Score Gauge (0-999)
/// - Personal Details Card (NO Title row)
/// - 5-Digit Security PIN Manager (`PinDialogOverlay`) supporting `returnToScanAfterPinSetup`
/// - Security, Support, Legal menu items + full-width red Log Out button
struct ProfileView: View {
    let onBackClick: () -> Void
    let onLogoutClick: () -> Void
    let onChangePasswordClick: () -> Void
    var autoOpenPinSetup: Bool = false
    var onPinSavedReturnToScan: (() -> Void)? = nil

    @State private var profile = StudentProfile()
    @State private var pinHash: String? = nil
    @State private var pinSalt: String = ""
    @State private var showPinDialog: Bool = false
    @State private var infoSheetContent: InfoSheetItem? = nil
    @State private var toastMessage: String? = nil

    @State private var userListener: ListenerRegistration?
    @State private var approvedListener: ListenerRegistration?
    @State private var boundStudentNumber: String = ""

    /// Strict No-Formalities Rule: First Name + Last Name ONLY (never title)
    private var fullName: String {
        [profile.firstName, profile.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var initials: String {
        let f = profile.firstName.trimmingCharacters(in: .whitespaces).prefix(1)
        let l = profile.lastName.trimmingCharacters(in: .whitespaces).prefix(1)
        let combined = "\(f)\(l)".uppercased()
        return combined.isEmpty ? "S" : combined
    }

    var body: some View {
        ZStack {
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

                    Text("My Profile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.crumzDarkBlue.ignoresSafeArea(edges: .top))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 24)

                        // Profile Photo (loaded from portal URL; initials fallback)
                        ZStack {
                            Circle()
                                .fill(Color.crumzDarkBlue)
                                .frame(width: 112, height: 112)

                            if let url = URL(string: profile.photoUrl), !profile.photoUrl.trimmingCharacters(in: .whitespaces).isEmpty {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 112, height: 112)
                                            .clipShape(Circle())
                                    default:
                                        Text(initials)
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            } else {
                                Text(initials)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 112, height: 112)
                        .overlay(
                            Circle().stroke(Color.crumzGold, lineWidth: 3)
                        )

                        Spacer().frame(height: 12)

                        // Name & Student Number ONLY (no Mr/Ms formalities)
                        Text(fullName.isEmpty ? profile.studentNumber : fullName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.crumzDarkBlue)

                        Text(profile.studentNumber)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)

                        Spacer().frame(height: 16)

                        CreditScoreGaugeView(score: profile.creditScore)

                        Spacer().frame(height: 20)

                        // Personal Details Card (without Title row)
                        ProfileSectionCard(title: "Personal Details") {
                            ProfileDetailRow(label: "Full name", value: fullName)
                            ProfileDetailRow(label: "Student number", value: profile.studentNumber)
                            ProfileDetailRow(label: "ID number", value: profile.idNumber)
                            ProfileDetailRow(label: "Date of birth", value: profile.dateOfBirth)
                            ProfileDetailRow(label: "Home language", value: profile.homeLanguage)
                            ProfileDetailRow(label: "Nationality", value: profile.nationality)
                            ProfileDetailRow(label: "Institution", value: profile.institution)

                            HStack {
                                Text("Account status")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(profile.isActive ? "Active" : "Deactivated")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(profile.isActive ? Color(hex: 0x16A34A) : Color(hex: 0xEF4444))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(profile.isActive ? Color(hex: 0xDCFCE7) : Color(hex: 0xFEE2E2))
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 6)
                        }

                        Spacer().frame(height: 16)

                        // Security PIN Card
                        ProfileSectionCard(title: "Security PIN") {
                            Text("A 5-digit PIN protects the QR scanner before you pay at a vendor.")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer().frame(height: 10)

                            HStack(spacing: 8) {
                                let hasPin = (pinHash != nil && !(pinHash?.isEmpty ?? true))
                                Image(systemName: hasPin ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(hasPin ? Color(hex: 0x16A34A) : .crumzGold)

                                Text(hasPin ? "PIN is set" : "PIN not set yet")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.crumzDarkBlue)

                                Spacer()

                                Button(action: { showPinDialog = true }) {
                                    Text(hasPin ? "Change PIN" : "Set PIN")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 9)
                                        .background(Color.crumzDarkBlue)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer().frame(height: 24)

                        // Settings Menu Sections
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Security")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                            Spacer().frame(height: 8)
                            ProfileMenuRow(icon: "lock.fill", title: "Change Password", action: onChangePasswordClick)

                            Spacer().frame(height: 24)

                            Text("Support")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                            Spacer().frame(height: 8)
                            ProfileMenuRow(icon: "questionmark.circle", title: "Contact Crumz Support") {
                                infoSheetContent = InfoSheetItem(
                                    title: "Crumz Student Support",
                                    bodyText: "Need help with your Crumz wallet, campus vendor payments, or account status?\n\n• Email: support@crumz.co.za\n• Hours: Monday – Friday, 08:00 – 17:00 SAST\n• Quote your Student Number (\(profile.studentNumber.isEmpty ? "on profile" : profile.studentNumber)) for priority assistance."
                                )
                            }

                            Spacer().frame(height: 24)

                            Text("Legal")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                            Spacer().frame(height: 8)
                            ProfileMenuRow(icon: "doc.text", title: "Terms of Service") {
                                infoSheetContent = InfoSheetItem(
                                    title: "Terms of Service",
                                    bodyText: "Crumz provides a closed-loop student meal & campus essentials credit facility regulated under the National Credit Act (NCR Registered Credit Provider).\n\n• Credit allocations may only be redeemed at verified Crumz Campus Partner Vendors.\n• An emergency R15.00 buffer is available and is automatically reconciled on your next monthly cycle load.\n• Keep your password and 5-digit QR PIN confidential."
                                )
                            }
                            Spacer().frame(height: 8)
                            ProfileMenuRow(icon: "hand.raised.fill", title: "Privacy Policy") {
                                infoSheetContent = InfoSheetItem(
                                    title: "Privacy Policy (POPIA)",
                                    bodyText: "Crumz processes your student profile and transaction records strictly in accordance with the Protection of Personal Information Act (POPIA) to administer your student wallet, verify eligibility, and settle campus vendor transactions."
                                )
                            }
                        }

                        Spacer().frame(height: 32)

                        // Red Log Out Button
                        Button(action: {
                            removeListeners()
                            try? Auth.auth().signOut()
                            onLogoutClick()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Log Out")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(hex: 0xEF4444))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(Color.crumzSurface.ignoresSafeArea())

            if showPinDialog, let uid = Auth.auth().currentUser?.uid {
                let hasExisting = (pinHash != nil && !(pinHash?.isEmpty ?? true))
                PinDialogOverlay(
                    hasExisting: hasExisting,
                    verifyCurrent: { entered in
                        !hasExisting || CrumzCrypto.hashPin(pin: entered, salt: pinSalt) == pinHash
                    },
                    onDismiss: { showPinDialog = false },
                    onSave: { newPin in
                        let salt = UUID().uuidString
                        let hashed = CrumzCrypto.hashPin(pin: newPin, salt: salt)
                        let db = Firestore.firestore()
                        db.collection("users").document(uid)
                            .setData(["pinHash": hashed, "pinSalt": salt], merge: true) { err in
                                if let err = err {
                                    toastMessage = "Could not save PIN: \(err.localizedDescription)"
                                } else {
                                    if !profile.studentNumber.isEmpty {
                                        db.collection("approved_students").document(profile.studentNumber)
                                            .setData(["pinSet": true], merge: true)
                                    }
                                    pinHash = hashed
                                    pinSalt = salt
                                    toastMessage = "5-digit PIN saved"
                                    showPinDialog = false
                                    onPinSavedReturnToScan?()
                                }
                            }
                    }
                )
            }
        }
        .crumzToast($toastMessage)
        .sheet(item: $infoSheetContent) { item in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.crumzDarkBlue)
                    Spacer()
                    Button("Close") { infoSheetContent = nil }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.crumzGold)
                }
                Divider()
                Text(item.bodyText)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x334155))
                    .lineSpacing(4)
                Spacer()
            }
            .padding(24)
            .presentationDetents([.medium])
        }
        .onAppear {
            if autoOpenPinSetup {
                showPinDialog = true
            }
            attachListeners()
        }
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

            pinHash = u["pinHash"] as? String
            pinSalt = u["pinSalt"] as? String ?? ""
            profile.studentNumber = sn
            if let fn = u["firstName"] as? String { profile.firstName = fn }
            if let ln = u["lastName"] as? String { profile.lastName = ln }

            if sn != boundStudentNumber {
                boundStudentNumber = sn
                approvedListener?.remove()
                approvedListener = db.collection("approved_students").document(sn).addSnapshotListener { aSnap, _ in
                    guard let aSnap = aSnap, aSnap.exists, let a = aSnap.data() else { return }
                    profile = StudentProfile(
                        studentNumber: sn,
                        firstName: a["firstName"] as? String ?? "",
                        lastName: a["lastName"] as? String ?? "",
                        title: a["title"] as? String ?? "", // Stored only; NEVER rendered in UI
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
            }
        }
    }

    private func removeListeners() {
        userListener?.remove()
        approvedListener?.remove()
        userListener = nil
        approvedListener = nil
        boundStudentNumber = ""
    }
}

private struct InfoSheetItem: Identifiable {
    let id = UUID()
    let title: String
    let bodyText: String
}

// MARK: - 270° Arc Credit Score Gauge (0-999)
private struct CreditScoreGaugeView: View {
    let score: Int?

    private var fraction: Double {
        min(max(Double(score ?? 0) / 999.0, 0.0), 1.0)
    }

    private var rating: (String, Color) {
        guard let s = score else { return ("Not yet rated", .gray) }
        if s >= 700 { return ("Excellent", Color(hex: 0x16A34A)) }
        if s >= 600 { return ("Good", Color(hex: 0x65A30D)) }
        if s >= 500 { return ("Fair", .crumzGold) }
        return ("Needs work", Color(hex: 0xEF4444))
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
                let radius = (min(size.width, size.height) - 20.0) / 2.0
                let stroke = StrokeStyle(lineWidth: 14, lineCap: .round)

                let bgArc = crumzScreenArcPath(
                    center: center,
                    radius: radius,
                    startDegrees: 135.0,
                    sweepDegrees: 270.0
                )
                context.stroke(bgArc, with: .color(Color(hex: 0xE2E8F0)), style: stroke)

                if fraction > 0.0 {
                    let fgArc = crumzScreenArcPath(
                        center: center,
                        radius: radius,
                        startDegrees: 135.0,
                        sweepDegrees: 270.0 * fraction
                    )
                    context.stroke(fgArc, with: .color(rating.1), style: stroke)
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 1) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.crumzDarkBlue)
                Text("Credit score")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Text(rating.0)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(rating.1)
            }
        }
        .frame(width: 150, height: 150)
    }
}

// MARK: - Profile Card & Row Helpers
private struct ProfileSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.crumzDarkBlue)
            Spacer().frame(height: 10)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

private struct ProfileDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Spacer(minLength: 16)
            Text(value.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.crumzDarkBlue)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }
}

private struct ProfileMenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.crumzDarkBlue)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: 0x334155))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: 0xCBD5E1))
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 5-Digit PIN Setup / Change Dialog (`PinDialog` in ProfileScreen.kt)
private struct PinDialogOverlay: View {
    let hasExisting: Bool
    let verifyCurrent: (String) -> Bool
    let onDismiss: () -> Void
    let onSave: (String) -> Void

    @State private var currentPin: String = ""
    @State private var newPin: String = ""
    @State private var confirmPin: String = ""
    @State private var error: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 12) {
                Text(hasExisting ? "Change PIN" : "Set your PIN")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.crumzDarkBlue)

                if hasExisting {
                    pinInputField(label: "Current PIN", value: $currentPin)
                }
                pinInputField(label: "New 5-digit PIN", value: $newPin)
                pinInputField(label: "Confirm new PIN", value: $confirmPin)

                if let error = error {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: 0xEF4444))
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if hasExisting && !verifyCurrent(currentPin) {
                            error = "Current PIN is incorrect"
                        } else if newPin.count != 5 {
                            error = "PIN must be exactly 5 digits"
                        } else if newPin != confirmPin {
                            error = "PINs do not match"
                        } else {
                            error = nil
                            onSave(newPin)
                        }
                    }) {
                        Text("Save")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.crumzDarkBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 6)
            .padding(.horizontal, 28)
        }
    }

    private func pinInputField(label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: 0x64748B))

            SecureField("", text: Binding(
                get: { value.wrappedValue },
                set: { updated in
                    let digitsOnly = updated.filter(\.isNumber)
                    value.wrappedValue = String(digitsOnly.prefix(5))
                    error = nil
                }
            ))
            .keyboardType(.numberPad)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.crumzDarkBlue)
            .tint(.crumzGold)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.crumzSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0x94A3B8), lineWidth: 1.2)
            )
        }
    }
}
