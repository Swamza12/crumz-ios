import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Authentication & Password Management ViewModel replicating `AuthViewModel.kt` 1:1.
final class AuthViewModel: ObservableObject {
    enum AuthStatus {
        case idle
        case loading
        case successForceChange
        case successReady
        case error(String)
    }

    enum ChangePasswordStatus {
        case idle
        case loading
        case success
        case error(String)
    }

    private let auth = Auth.auth()
    private let db = Firestore.firestore()

    func login(rawStudentNumber: String, password: String, onResult: @escaping (AuthStatus) -> Void) {
        let studentNumber = rawStudentNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if studentNumber.isEmpty || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onResult(.error("Please enter student number and password"))
            return
        }

        onResult(.loading)

        // 1. Check approved_students/{studentNumber} first
        db.collection("approved_students").document(studentNumber).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                onResult(.error("Network error: \(error.localizedDescription)"))
                return
            }
            guard let document = snapshot, document.exists else {
                onResult(.error("Student number not found in approved roster."))
                return
            }

            let data = document.data() ?? [:]
            let used = data["used"] as? Bool ?? false
            let tempPass = data["temp_password"] as? String
            let authEmail = (data["authEmail"] as? String) ?? "\(studentNumber)@crumz.app"

            if !used {
                // First-time login with temporary password
                if tempPass == password {
                    self.auth.createUser(withEmail: authEmail, password: password) { createResult, createErr in
                        if let newUid = createResult?.user.uid, createErr == nil {
                            // 1. Mark as used in approved_students
                            document.reference.updateData(["used": true])

                            // 2. Create user profile in users/{uid}
                            let initialBalance = (data["balance"] as? NSNumber)?.doubleValue ?? 500.0
                            let allocatedLimit = (data["allocatedLimit"] as? NSNumber)?.doubleValue ?? initialBalance
                            let userProfile: [String: Any] = [
                                "studentNumber": studentNumber,
                                "authEmail": authEmail,
                                "balance": initialBalance,
                                "allocatedLimit": allocatedLimit,
                                "firstName": data["firstName"] as? String ?? "",
                                "lastName": data["lastName"] as? String ?? "",
                                "email": data["email"] as? String ?? authEmail,
                                "phone": data["phone"] as? String ?? "",
                                "is_temporary_password": true
                            ]

                            self.db.collection("users").document(newUid).setData(userProfile) { setErr in
                                if let setErr = setErr {
                                    onResult(.error("Failed to create profile: \(setErr.localizedDescription)"))
                                } else {
                                    onResult(.successForceChange)
                                }
                            }
                        } else {
                            // Fallback if Auth account already exists (legacy/re-approved test user)
                            self.auth.signIn(withEmail: authEmail, password: password) { signInRes, signInErr in
                                if let user = signInRes?.user, signInErr == nil {
                                    document.reference.updateData(["used": true])
                                    self.checkDatabaseForTempFlag(uid: user.uid, onResult: onResult)
                                } else {
                                    onResult(.error("Failed to initialize account: \(createErr?.localizedDescription ?? "Unknown error")"))
                                }
                            }
                        }
                    }
                } else {
                    onResult(.error("Incorrect temporary password."))
                }
            } else {
                // Returning student login
                self.auth.signIn(withEmail: authEmail, password: password) { signInRes, signInErr in
                    if let user = signInRes?.user, signInErr == nil {
                        self.checkDatabaseForTempFlag(uid: user.uid, onResult: onResult)
                    } else {
                        onResult(.error("Invalid credentials."))
                    }
                }
            }
        }
    }

    private func checkDatabaseForTempFlag(uid: String, onResult: @escaping (AuthStatus) -> Void) {
        db.collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                onResult(.error(error.localizedDescription))
                return
            }
            if let doc = snapshot, doc.exists {
                let isTemp = doc.data()?["is_temporary_password"] as? Bool ?? false
                if isTemp {
                    onResult(.successForceChange)
                } else {
                    onResult(.successReady)
                }
            } else {
                onResult(.successReady)
            }
        }
    }

    func changePassword(newPassword: String, onResult: @escaping (ChangePasswordStatus) -> Void) {
        guard let user = auth.currentUser else {
            onResult(.error("Not logged in"))
            return
        }

        onResult(.loading)

        user.updatePassword(to: newPassword) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                onResult(.error(error.localizedDescription))
                return
            }

            self.db.collection("users").document(user.uid).updateData([
                "is_temporary_password": false
            ]) { dbErr in
                if let dbErr = dbErr {
                    onResult(.error("Password updated, but failed to clear security flag: \(dbErr.localizedDescription)"))
                } else {
                    onResult(.success)
                }
            }
        }
    }
}
