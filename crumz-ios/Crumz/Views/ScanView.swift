import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

/// 5-Bubble PIN Pad & QR Code Scanner Screen replicating `ScanScreen.kt` 1:1:
/// - SHA-256 PIN hashing matching Android byte-for-byte
/// - 5 minimalist circular bubbles (○ ○ ○ ○ ○ -> ● ● ● ● ●) + 3x4 circular keypad
/// - Inline 2-step 5-bubble PIN creation if no PIN exists yet
/// - Instant camera QR scanner launch on the 5th bubble (zero extra button taps)
/// - Parses both self-contained offline JSON (`CRUMZ_OFFLINE:{...}`) & online (`CRUMZ_CHARGE:CHG-xxx`) QR codes
/// - Live vendor till bills countdown + manual code fallback
/// - Read-only bill confirmation modal with R15.00 emergency buffer check & atomic Firestore transaction
struct ScanView: View {
    let onBack: () -> Void
    var onNavigateToProfile: () -> Void = {}

    @State private var isLoadingProfile: Bool = true
    @State private var studentNumber: String = ""
    @State private var studentName: String = ""
    @State private var balance: Double = 0.0
    @State private var isActive: Bool = true
    @State private var pinHash: String? = nil
    @State private var pinSalt: String = ""

    // PIN Gate State
    @State private var isScannerUnlocked: Bool = false
    @State private var unlockPinInput: String = ""
    @State private var unlockPinError: String? = nil

    // Inline PIN Creation State
    @State private var createStep: Int = 1
    @State private var newPinInput: String = ""
    @State private var confirmPinInput: String = ""
    @State private var createPinError: String? = nil
    @State private var isSavingNewPin: Bool = false

    // Live Pending Bills & Clock
    @State private var pendingBills: [PendingBill] = []
    @State private var nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)

    // Selected / Scanned Bill & Payment State
    @State private var activeBill: PendingBill? = nil
    @State private var billError: String? = nil
    @State private var isProcessingPayment: Bool = false
    @State private var paidReceipt: PendingBill? = nil

    // Camera Scanner Modal & Manual Code Fallback
    @State private var showCameraScanner: Bool = false
    @State private var manualCode: String = ""
    @State private var toastMessage: String? = nil

    // Scan Line Animation
    @State private var scanLineAtBottom: Bool = false

    // Firestore Listeners
    @State private var userListener: ListenerRegistration?
    @State private var approvedListener: ListenerRegistration?
    @State private var billsListener: ListenerRegistration?
    @State private var boundStudentNumber: String = ""

    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var validPendingBills: [PendingBill] {
        pendingBills.filter { $0.expiresAtMillis > nowMillis }
    }

    var body: some View {
        ZStack {
            Color.crumzDarkBlue.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)

                    // Top Header Bar + Balance Pill
                    headerBar

                    Spacer().frame(height: 24)

                    if isLoadingProfile {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .crumzGold))
                                .scaleEffect(1.3)
                            Spacer()
                        }
                        .padding(48)
                    } else if pinHash == nil || (pinHash?.trimmingCharacters(in: .whitespaces).isEmpty == true) {
                        // STEP 1A: Student has NOT set up a 5-digit PIN yet
                        inlineCreatePinPadView
                    } else if !isScannerUnlocked {
                        // STEP 1B: Student ALREADY has a 5-digit PIN -> Fill 5 bubbles & immediately scan
                        unlockPinPadView
                    } else if let receipt = paidReceipt {
                        // STEP 4: Green Payment Confirmed Receipt Card
                        paymentReceiptCard(receipt)
                    } else {
                        // STEP 2: Unlocked QR Viewfinder + Live Bills + Manual Code Fallback
                        unlockedScannerContent
                    }
                }
                .padding(24)
            }

            // STEP 3: Read-Only Bill Confirmation Dialog Overlay
            if let bill = activeBill {
                billConfirmationDialog(bill)
            }
        }
        .crumzToast($toastMessage)
        .fullScreenCover(isPresented: $showCameraScanner) {
            QRCodeScannerModalView(
                onCodeScanned: { raw in
                    showCameraScanner = false
                    loadBillByCode(raw)
                },
                onUnavailable: { reason in
                    showCameraScanner = false
                    toastMessage = reason
                },
                onCancel: {
                    showCameraScanner = false
                }
            )
        }
        .onReceive(secondTimer) { now in
            nowMillis = Int64(now.timeIntervalSince1970 * 1000.0)
        }
        .onAppear(perform: attachListeners)
        .onDisappear(perform: removeListeners)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            HStack(spacing: 16) {
                Button(action: onBack) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan Vendor QR")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.white)
                    Text("Protected by your 5-digit PIN")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.65))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Available")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.6))
                Text(balance < 0
                     ? String(format: "-R%.2f", abs(balance))
                     : String(format: "R%.2f", balance))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(balance < 0 ? Color(hex: 0xF87171) : Color(hex: 0x4ADE80))
                Text("+R15 buffer")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.crumzGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Step 1A: Inline 5-Bubble PIN Creation
    private var inlineCreatePinPadView: some View {
        let activeDigits = (createStep == 1) ? newPinInput : confirmPinInput

        return CrumzBubblePinPad(
            title: createStep == 1 ? "Create 5-Digit Code" : "Confirm 5-Digit Code",
            subtitle: createStep == 1
                ? "Fill the 5 bubbles to secure your QR scanner"
                : "Re-enter the same 5 digits to open the scanner",
            enteredLength: activeDigits.count,
            errorMessage: createPinError,
            isBusy: isSavingNewPin,
            onDigitTap: { digit in
                guard !isSavingNewPin else { return }
                createPinError = nil
                if createStep == 1 {
                    if newPinInput.count < 5 {
                        let next = newPinInput + digit
                        newPinInput = next
                        if next.count == 5 {
                            createStep = 2
                        }
                    }
                } else {
                    if confirmPinInput.count < 5 {
                        let next = confirmPinInput + digit
                        confirmPinInput = next
                        if next.count == 5 {
                            if next != newPinInput {
                                createPinError = "Codes didn't match — try confirming again"
                                scheduleCreatePinReset()
                            } else if let uid = Auth.auth().currentUser?.uid {
                                isSavingNewPin = true
                                let salt = UUID().uuidString
                                let hashed = CrumzCrypto.hashPin(pin: next, salt: salt)
                                let db = Firestore.firestore()
                                db.collection("users").document(uid).setData([
                                    "pinHash": hashed,
                                    "pinSalt": salt
                                ], merge: true) { err in
                                    if let err = err {
                                        isSavingNewPin = false
                                        createPinError = "Could not save: \(err.localizedDescription)"
                                        scheduleCreatePinReset()
                                    } else {
                                        if !studentNumber.isEmpty {
                                            db.collection("approved_students").document(studentNumber)
                                                .setData(["pinSet": true], merge: true)
                                        }
                                        isSavingNewPin = false
                                        pinHash = hashed
                                        pinSalt = salt
                                        isScannerUnlocked = true
                                        launchCameraScanner()
                                    }
                                }
                            }
                        }
                    }
                }
            },
            onBackspace: {
                createPinError = nil
                if createStep == 2 {
                    if !confirmPinInput.isEmpty {
                        confirmPinInput.removeLast()
                    } else {
                        createStep = 1
                        newPinInput = ""
                    }
                } else if !newPinInput.isEmpty {
                    newPinInput.removeLast()
                }
            },
            onClear: {
                createPinError = nil
                if createStep == 2 {
                    confirmPinInput = ""
                } else {
                    newPinInput = ""
                }
            },
            footerContent: {
                VStack(spacing: 4) {
                    if createStep == 2 {
                        Button(action: {
                            createStep = 1
                            newPinInput = ""
                            confirmPinInput = ""
                            createPinError = nil
                        }) {
                            Text("Start over")
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.7))
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onNavigateToProfile) {
                        Text("Or set up in Profile")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.crumzGold)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }

    // MARK: - Step 1B: 5-Bubble Scanner Unlock
    private var unlockPinPadView: some View {
        CrumzBubblePinPad(
            title: "Unlock QR Scanner",
            subtitle: "Fill the 5 bubbles to scan immediately",
            enteredLength: unlockPinInput.count,
            errorMessage: unlockPinError,
            isBusy: false,
            onDigitTap: { digit in
                if unlockPinInput.count < 5 {
                    unlockPinError = nil
                    let next = unlockPinInput + digit
                    unlockPinInput = next
                    if next.count == 5 {
                        if CrumzCrypto.hashPin(pin: next, salt: pinSalt) == pinHash {
                            isScannerUnlocked = true
                            launchCameraScanner()
                        } else {
                            unlockPinError = "Incorrect 5-digit code"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                                unlockPinInput = ""
                            }
                        }
                    }
                }
            },
            onBackspace: {
                unlockPinError = nil
                if !unlockPinInput.isEmpty {
                    unlockPinInput.removeLast()
                }
            },
            onClear: {
                unlockPinError = nil
                unlockPinInput = ""
            }
        )
    }

    // MARK: - Step 2: Unlocked Viewfinder + Live Bills + Manual Code
    private var unlockedScannerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Viewfinder Box
            Button(action: launchCameraScanner) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 230)

                    // 4 Gold Corners
                    VStack {
                        HStack {
                            ViewfinderCorner(corners: [.topLeft])
                            Spacer()
                            ViewfinderCorner(corners: [.topRight])
                        }
                        Spacer()
                        HStack {
                            ViewfinderCorner(corners: [.bottomLeft])
                            Spacer()
                            ViewfinderCorner(corners: [.bottomRight])
                        }
                    }
                    .padding(20)
                    .frame(height: 230)

                    // Center Icon & Text
                    VStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.85))
                        Spacer().frame(height: 2)
                        Text("PIN Verified • Tap to Scan Vendor QR")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: 0x4ADE80))
                        Text("Works with both online & offline vendor QR codes")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 230)

                    // Animated Horizontal Gold Scan Line
                    LinearGradient(
                        colors: [.clear, .crumzGold, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 3)
                    .offset(y: scanLineAtBottom ? 210 : 16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .onAppear {
                scanLineAtBottom = false
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: true)) {
                    scanLineAtBottom = true
                }
            }

            Spacer().frame(height: 16)

            // Primary Camera Scan Button
            Button(action: launchCameraScanner) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("Scan Vendor QR with Camera")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.crumzGold)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 20)

            // Live Active Vendor Till Bills
            Text("ACTIVE VENDOR TILL BILLS (LIVE)")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(Color.white.opacity(0.7))

            Spacer().frame(height: 8)

            if validPendingBills.isEmpty {
                VStack(spacing: 4) {
                    Text("Waiting for vendor to create a bill...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.8))
                    Text("Scan the vendor's QR code with your camera, or tap a live bill when it appears here.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(validPendingBills) { bill in
                    let secsLeft = max(0, (bill.expiresAtMillis - nowMillis) / 1000)
                    Button(action: {
                        activeBill = bill
                        billError = nil
                    }) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.crumzGold.opacity(0.25))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.crumzGold)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(bill.vendorName) — \(String(format: "R%.2f", bill.amount))")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(bill.description) • Expires in \(secsLeft)s")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 6)

                            Text("Pay")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(hex: 0x10B981))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }

            Spacer().frame(height: 12)

            // Manual Charge Code Fallback
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $manualCode,
                    prompt: Text("Or enter code (e.g. CHG-123456)")
                        .foregroundColor(Color.white.opacity(0.4))
                        .font(.system(size: 12))
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .tint(.crumzGold)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
                )

                Button(action: {
                    let trimmed = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        loadBillByCode(trimmed)
                    }
                }) {
                    Text("Load")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 3: Read-Only Bill Confirmation Dialog
    private func billConfirmationDialog(_ bill: PendingBill) -> some View {
        let willUseBuffer = balance < bill.amount && (balance - bill.amount) >= -15.0001
        let bufferAmountNeeded = willUseBuffer ? (bill.amount - max(0.0, balance)) : 0.0

        return ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isProcessingPayment {
                        activeBill = nil
                        billError = nil
                    }
                }

            VStack(spacing: 0) {
                Text("CONFIRM VENDOR PAYMENT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(Color(hex: 0x64748B))

                Spacer().frame(height: 6)

                Text("Pay \(bill.vendorName) – \(String(format: "R%.2f", bill.amount))?")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.crumzDarkBlue)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 16)

                // Read-Only Price & Item Box
                VStack(spacing: 4) {
                    Text(String(format: "R%.2f", bill.amount))
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundColor(.crumzDarkBlue)
                    Text("\(bill.description) (\(bill.category))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: 0x475569))
                        .multilineTextAlignment(.center)
                    Spacer().frame(height: 2)
                    Text("Price set by vendor • Read-only • 5-Digit PIN Verified")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: 0x16A34A))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(Color.crumzSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if willUseBuffer {
                    Spacer().frame(height: 10)
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0xD97706))
                        Text("Uses \(String(format: "R%.2f", bufferAmountNeeded)) of your R15.00 buffer (automatically deducted on your next load).")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: 0x92400E))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFEF3C7))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let err = billError {
                    Spacer().frame(height: 10)
                    Text(err)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: 0xDC2626))
                        .multilineTextAlignment(.center)
                }

                Spacer().frame(height: 18)

                Button(action: { confirmAndPay(bill) }) {
                    HStack(spacing: 6) {
                        if isProcessingPayment {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Processing...")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text("Confirm & Pay \(String(format: "R%.2f", bill.amount))")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: 0x16A34A))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isProcessingPayment)
                .buttonStyle(.plain)

                Spacer().frame(height: 8)

                Button(action: {
                    if !isProcessingPayment {
                        activeBill = nil
                        billError = nil
                    }
                }) {
                    Text("Decline / Cancel")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0x64748B))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 4: Payment Confirmed Receipt Card
    private func paymentReceiptCard(_ receipt: PendingBill) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: 0x4ADE80))

            Spacer().frame(height: 12)

            Text("PAYMENT CONFIRMED")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1)
                .foregroundColor(Color(hex: 0xA7F3D0))

            Spacer().frame(height: 4)

            Text(String(format: "R%.2f", receipt.amount))
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.white)

            Spacer().frame(height: 8)

            Text(receipt.vendorName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("\(receipt.description) • \(receipt.id)")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.8))

            Spacer().frame(height: 16)
            Divider().background(Color.white.opacity(0.2))
            Spacer().frame(height: 12)

            let newBalStr = balance < 0
                ? String(format: "-R%.2f (Buffer Used)", abs(balance))
                : String(format: "R%.2f", balance)

            Text("New Balance: \(newBalStr)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            Spacer().frame(height: 20)

            Button(action: {
                paidReceipt = nil
                onBack()
            }) {
                Text("Done")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(Color(hex: 0x065F46))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0x065F46))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Actions & Firestore Logic
    private func scheduleCreatePinReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if createStep == 2 {
                confirmPinInput = ""
            } else {
                newPinInput = ""
            }
        }
    }

    private func launchCameraScanner() {
        showCameraScanner = true
    }

    /// Supports both self-contained Offline/Online JSON (`CRUMZ_OFFLINE:{...}`) and Charge ID (`CRUMZ_CHARGE:CHG-xxx`)
    private func loadBillByCode(_ rawCode: String) {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let db = Firestore.firestore()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        // 1. Check self-contained JSON QR payload
        if trimmed.lowercased().hasPrefix("crumz_offline:") || trimmed.hasPrefix("{") {
            let jsonPart: String
            if trimmed.hasPrefix("{") {
                jsonPart = trimmed
            } else if let colonIdx = trimmed.firstIndex(of: ":") {
                jsonPart = String(trimmed[trimmed.index(after: colonIdx)...])
            } else {
                jsonPart = trimmed
            }

            if let data = jsonPart.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let rawId = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let chargeId = rawId.isEmpty ? "CHG-\(Int.random(in: 100000...999999))" : rawId
                let vId = obj["vId"] as? String ?? "VEN001"
                let vName = obj["vName"] as? String ?? "Campus Partner"
                let cat = obj["cat"] as? String ?? "Food & Meals"
                let desc = obj["desc"] as? String ?? "Store Purchase"
                let amt = (obj["amt"] as? NSNumber)?.doubleValue ?? 0.0
                let exp = (obj["exp"] as? NSNumber)?.int64Value ?? (nowMs + 120_000)

                if amt <= 0.0 {
                    toastMessage = "Invalid QR charge amount."
                    return
                }
                if exp > 0 && nowMs > exp {
                    toastMessage = "This QR code expired (2-min limit). Ask vendor for a new one."
                    return
                }

                db.collection("payment_requests").document(chargeId).getDocument { snap, _ in
                    if let snap = snap, snap.exists {
                        let st = snap.data()?["status"] as? String ?? "pending"
                        if st != "pending" {
                            toastMessage = "This QR code has already been \(st)."
                            return
                        }
                    }
                    activeBill = PendingBill(
                        id: chargeId,
                        vendorId: vId,
                        vendorName: vName,
                        category: cat,
                        description: desc,
                        amount: amt,
                        status: "pending",
                        expiresAtMillis: exp
                    )
                    billError = nil
                }
                return
            }
        }

        // 2. Standard Charge ID lookup ("CRUMZ_CHARGE:CHG-xxxxxx" or "CHG-xxxxxx")
        var cleaned = trimmed
        if cleaned.lowercased().hasPrefix("crumz_charge:") {
            cleaned = String(cleaned.dropFirst("crumz_charge:".count))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let chargeId = cleaned.hasPrefix("CHG-") ? cleaned : "CHG-\(cleaned)"

        db.collection("payment_requests").document(chargeId).getDocument { snap, err in
            if let err = err {
                toastMessage = "Could not verify QR code: \(err.localizedDescription)"
                return
            }
            guard let snap = snap, snap.exists, let d = snap.data() else {
                toastMessage = "Invalid or unknown QR charge (\(chargeId))"
                return
            }
            let st = d["status"] as? String ?? "pending"
            let exp = (d["expiresAtMillis"] as? NSNumber)?.int64Value ?? 0
            if st != "pending" {
                toastMessage = "This QR code has already been \(st)."
                return
            }
            if exp > 0 && Int64(Date().timeIntervalSince1970 * 1000.0) > exp {
                toastMessage = "This QR code expired (2-min limit). Ask vendor for a new one."
                return
            }
            activeBill = PendingBill(
                id: snap.documentID,
                vendorId: d["vendorId"] as? String ?? "VEN001",
                vendorName: d["vendorName"] as? String ?? "Campus Vendor",
                category: d["category"] as? String ?? "Food & Meals",
                description: d["description"] as? String ?? "Store Purchase",
                amount: (d["amount"] as? NSNumber)?.doubleValue ?? 0.0,
                status: st,
                expiresAtMillis: exp
            )
            billError = nil
        }
    }

    /// Atomic Firestore payment transaction with R15.00 emergency buffer check
    private func confirmAndPay(_ bill: PendingBill) {
        if !isActive {
            billError = "Your account is currently deactivated. Contact Crumz Support."
            return
        }
        if balance - bill.amount < -15.0001 {
            let maxSpendable = max(0.0, balance + 15.0)
            billError = String(format: "Insufficient funds (even with R15.00 buffer). Max spendable right now: R%.2f.", maxSpendable)
            return
        }

        isProcessingPayment = true
        billError = nil

        let db = Firestore.firestore()
        let uid = Auth.auth().currentUser?.uid
        let studentRef = db.collection("approved_students").document(studentNumber)
        let chargeRef = db.collection("payment_requests").document(bill.id)
        let newTxnRef = db.collection("transactions").document()

        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

            // 1. Check payment_requests/{bill.id}
            let chargeSnap: DocumentSnapshot
            do {
                chargeSnap = try transaction.getDocument(chargeRef)
            } catch let fetchErr as NSError {
                errorPointer?.pointee = fetchErr
                return nil
            }

            if chargeSnap.exists, let cData = chargeSnap.data() {
                let currentStatus = cData["status"] as? String ?? "pending"
                if currentStatus != "pending" {
                    errorPointer?.pointee = NSError(
                        domain: "CrumzPay",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "This QR code was already \(currentStatus)."]
                    )
                    return nil
                }
                let exp = (cData["expiresAtMillis"] as? NSNumber)?.int64Value ?? bill.expiresAtMillis
                if exp > 0 && nowMs > exp {
                    errorPointer?.pointee = NSError(
                        domain: "CrumzPay",
                        code: 410,
                        userInfo: [NSLocalizedDescriptionKey: "This QR code expired (2-minute limit)."]
                    )
                    return nil
                }
            } else {
                if bill.expiresAtMillis > 0 && nowMs > bill.expiresAtMillis {
                    errorPointer?.pointee = NSError(
                        domain: "CrumzPay",
                        code: 410,
                        userInfo: [NSLocalizedDescriptionKey: "This offline QR code expired (2-minute limit)."]
                    )
                    return nil
                }
            }

            // 2. Check approved_students/{studentNumber}
            let studentSnap: DocumentSnapshot
            do {
                studentSnap = try transaction.getDocument(studentRef)
            } catch let fetchErr as NSError {
                errorPointer?.pointee = fetchErr
                return nil
            }

            let sData = studentSnap.data() ?? [:]
            let activeFlag = sData["isActive"] as? Bool ?? true
            if !activeFlag {
                errorPointer?.pointee = NSError(
                    domain: "CrumzPay",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Student account is deactivated."]
                )
                return nil
            }

            let currentBal = (sData["balance"] as? NSNumber)?.doubleValue ?? balance
            let newBal = currentBal - bill.amount
            if newBal < -15.0001 {
                errorPointer?.pointee = NSError(
                    domain: "CrumzPay",
                    code: 402,
                    userInfo: [NSLocalizedDescriptionKey: "Insufficient balance (exceeds R15.00 emergency buffer)."]
                )
                return nil
            }

            // 3. Deduct balance from approved_students & users
            transaction.updateData(["balance": newBal], forDocument: studentRef)
            if let uid = uid, !uid.isEmpty {
                let userRef = db.collection("users").document(uid)
                transaction.setData(["balance": newBal], forDocument: userRef, merge: true)
            }

            // 4. Mark payment_requests/{chargeId} as paid (merge: true supports offline vendor QR codes)
            transaction.setData([
                "vendorId": bill.vendorId,
                "vendorName": bill.vendorName,
                "category": bill.category,
                "description": bill.description,
                "amount": bill.amount,
                "expiresAtMillis": bill.expiresAtMillis,
                "status": "paid",
                "studentNumber": studentNumber,
                "studentName": studentName,
                "paidAt": FieldValue.serverTimestamp()
            ], forDocument: chargeRef, merge: true)

            // 5. Append record to transactions collection
            transaction.setData([
                "studentNumber": studentNumber,
                "studentName": studentName,
                "vendorId": bill.vendorId,
                "vendorName": bill.vendorName,
                "category": bill.category,
                "description": bill.description,
                "amount": bill.amount,
                "chargeId": bill.id,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: newTxnRef)

            return newBal
        }) { result, error in
            isProcessingPayment = false
            if let error = error {
                billError = error.localizedDescription
            } else {
                if let updatedBal = result as? Double {
                    balance = updatedBal
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                paidReceipt = bill
                activeBill = nil
            }
        }
    }

    private func attachListeners() {
        removeListeners()
        let db = Firestore.firestore()

        if let uid = Auth.auth().currentUser?.uid {
            userListener = db.collection("users").document(uid).addSnapshotListener { snap, _ in
                guard let snap = snap, snap.exists, let data = snap.data() else {
                    isLoadingProfile = false
                    return
                }
                let sn = data["studentNumber"] as? String ?? ""
                studentNumber = sn
                pinHash = data["pinHash"] as? String
                pinSalt = data["pinSalt"] as? String ?? ""
                let fn = data["firstName"] as? String ?? ""
                let ln = data["lastName"] as? String ?? ""
                let combined = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
                studentName = combined.isEmpty ? sn : combined
                if let uBal = (data["balance"] as? NSNumber)?.doubleValue {
                    balance = uBal
                }

                if !sn.isEmpty && sn != boundStudentNumber {
                    boundStudentNumber = sn
                    approvedListener?.remove()
                    approvedListener = db.collection("approved_students").document(sn).addSnapshotListener { aSnap, _ in
                        if let aSnap = aSnap, aSnap.exists, let aData = aSnap.data() {
                            let afn = aData["firstName"] as? String ?? fn
                            let aln = aData["lastName"] as? String ?? ln
                            let full = "\(afn) \(aln)".trimmingCharacters(in: .whitespaces)
                            studentName = full.isEmpty ? sn : full
                            if let aBal = (aData["balance"] as? NSNumber)?.doubleValue {
                                balance = aBal
                            }
                            isActive = aData["isActive"] as? Bool ?? true
                        }
                        isLoadingProfile = false
                    }
                } else if sn.isEmpty {
                    isLoadingProfile = false
                }
            }
        } else {
            isLoadingProfile = false
        }

        billsListener = db.collection("payment_requests")
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { snap, _ in
                guard let snap = snap else { return }
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
                let list: [PendingBill] = snap.documents.compactMap { doc in
                    let d = doc.data()
                    guard let amt = (d["amount"] as? NSNumber)?.doubleValue else { return nil }
                    let exp = (d["expiresAtMillis"] as? NSNumber)?.int64Value ?? (nowMs + 120_000)
                    return PendingBill(
                        id: doc.documentID,
                        vendorId: d["vendorId"] as? String ?? "VEN001",
                        vendorName: d["vendorName"] as? String ?? "Campus Vendor",
                        category: d["category"] as? String ?? "Food & Meals",
                        description: d["description"] as? String ?? "Store Purchase",
                        amount: amt,
                        status: d["status"] as? String ?? "pending",
                        expiresAtMillis: exp
                    )
                }.sorted(by: { $0.expiresAtMillis > $1.expiresAtMillis })
                pendingBills = list
            }
    }

    private func removeListeners() {
        userListener?.remove()
        approvedListener?.remove()
        billsListener?.remove()
        userListener = nil
        approvedListener = nil
        billsListener = nil
        boundStudentNumber = ""
    }
}

// MARK: - Viewfinder Corner Helper
private struct ViewfinderCorner: View {
    let corners: UIRectCorner

    var body: some View {
        SelectiveRoundedCorner(radius: 14, corners: corners)
            .stroke(Color.crumzGold, lineWidth: 4)
            .frame(width: 40, height: 40)
    }
}

// MARK: - 5-Bubble PIN Pad Component (`CrumzBubblePinPad`)
private struct CrumzBubblePinPad<Footer: View>: View {
    let title: String
    let subtitle: String
    let enteredLength: Int
    let errorMessage: String?
    var isBusy: Bool = false
    let onDigitTap: (String) -> Void
    let onBackspace: () -> Void
    let onClear: () -> Void
    var footerContent: () -> Footer

    init(
        title: String,
        subtitle: String,
        enteredLength: Int,
        errorMessage: String?,
        isBusy: Bool = false,
        onDigitTap: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onClear: @escaping () -> Void,
        @ViewBuilder footerContent: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.enteredLength = enteredLength
        self.errorMessage = errorMessage
        self.isBusy = isBusy
        self.onDigitTap = onDigitTap
        self.onBackspace = onBackspace
        self.onClear = onClear
        self.footerContent = footerContent
    }

    private var hasError: Bool {
        errorMessage != nil
    }

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["CLR", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Subtle glowing QR lock badge
            ZStack {
                Circle()
                    .fill(Color.crumzGold.opacity(0.14))
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Color.crumzGold.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.crumzGold)
            }

            Spacer().frame(height: 16)

            Text(title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 6)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.68))
                .multilineTextAlignment(.center)

            Spacer().frame(height: 28)

            // 5 Minimalist Animated Bubbles (○ ○ ○ ○ ○ -> ● ● ● ● ●)
            HStack(spacing: 20) {
                ForEach(0..<5, id: \.self) { i in
                    let isFilled = i < enteredLength
                    let targetSize: CGFloat = isFilled ? 24 : 20
                    let fillColor: Color = hasError
                        ? Color(hex: 0xEF4444)
                        : (isFilled ? .crumzGold : .clear)
                    let borderColor: Color = hasError
                        ? Color(hex: 0xEF4444)
                        : (isFilled ? .crumzGold : Color.white.opacity(0.55))

                    ZStack {
                        if isFilled && !hasError {
                            Circle()
                                .fill(Color.crumzGold.opacity(0.22))
                                .frame(width: 28, height: 28)
                        }

                        Circle()
                            .fill(fillColor)
                            .frame(width: targetSize, height: targetSize)
                            .overlay(
                                Circle()
                                    .stroke(borderColor, lineWidth: 2)
                            )
                            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isFilled)
                    }
                    .frame(width: 28, height: 28)
                }
            }

            Spacer().frame(height: 18)

            // Fixed-height status / error feedback row
            ZStack {
                if isBusy {
                    Text("Unlocking scanner...")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.crumzGold)
                } else if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: 0xF87171))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)

            Spacer().frame(height: 18)

            // Sleek 3x4 Circular Keypad
            VStack(spacing: 14) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { key in
                            let isActionKey = (key == "CLR" || key == "⌫")
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                switch key {
                                case "CLR": onClear()
                                case "⌫": onBackspace()
                                default: onDigitTap(key)
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(isActionKey ? Color.white.opacity(0.04) : Color.white.opacity(0.09))
                                        .frame(width: 72, height: 72)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    isActionKey ? Color.white.opacity(0.12) : Color.crumzGold.opacity(0.32),
                                                    lineWidth: 1
                                                )
                                        )

                                    Text(key)
                                        .font(.system(size: key == "CLR" ? 13 : 24, weight: key == "CLR" ? .bold : .heavy))
                                        .foregroundColor(
                                            key == "CLR"
                                                ? Color.white.opacity(0.65)
                                                : (key == "⌫" ? .crumzGold : .white)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer().frame(height: 12)
            footerContent()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
