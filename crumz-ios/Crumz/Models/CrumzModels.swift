import Foundation
import CoreLocation

// MARK: - Navigation Keys (Matches NavigationKeys.kt 1:1)
enum NavRouteKey: Hashable {
    case splash
    case login
    case changePassword
    case main
    case scanQR
    case vendorsMap
    case history
    case profile
}

// MARK: - Student Profile (Matches ProfileScreen.kt StudentProfile 1:1)
struct StudentProfile: Equatable {
    var studentNumber: String = ""
    var firstName: String = ""
    var lastName: String = ""
    /// Stored if present in Firestore, but NEVER displayed in UI per strict no-formalities rule
    var title: String = ""
    var idNumber: String = ""
    var dateOfBirth: String = ""
    var homeLanguage: String = ""
    var nationality: String = ""
    var institution: String = ""
    var address: String = ""
    var photoUrl: String = ""
    var creditScore: Int? = nil
    var isActive: Bool = true
}

// MARK: - Transaction Row (Matches ProfileScreen.kt TxnRow 1:1)
struct TxnRow: Identifiable, Equatable {
    let id: String
    let vendorName: String
    let category: String
    let amount: Double
    let timeMillis: Int64
}

// MARK: - Pending Vendor Bill (Matches ScanScreen.kt PendingBill 1:1)
struct PendingBill: Identifiable, Equatable {
    let id: String
    let vendorId: String
    let vendorName: String
    let category: String
    let description: String
    let amount: Double
    let status: String
    let expiresAtMillis: Int64
}

// MARK: - Partnered Vendor Location (Matches VendorsMapScreen.kt VendorLocation 1:1)
struct VendorLocation: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let address: String
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - South African University Campus Presets (Matches VendorsMapScreen.kt SA_CAMPUSES 1:1)
struct CampusPreset: Identifiable, Equatable {
    var id: String { "\(name)_\(shortName)" }
    let name: String
    let shortName: String
    let city: String
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

let SA_CAMPUSES: [CampusPreset] = [
    CampusPreset(name: "University of the Western Cape (UWC)", shortName: "UWC", city: "Bellville, Cape Town", lat: -33.9333, lng: 18.6315),
    CampusPreset(name: "University of Cape Town (UCT)", shortName: "UCT", city: "Rondebosch, Cape Town", lat: -33.9576, lng: 18.4611),
    CampusPreset(name: "Cape Peninsula University of Tech (CPUT)", shortName: "CPUT", city: "District Six, Cape Town", lat: -33.9317, lng: 18.4289),
    CampusPreset(name: "Stellenbosch University", shortName: "SU / Maties", city: "Stellenbosch", lat: -33.9321, lng: 18.8644),
    CampusPreset(name: "University of the Witwatersrand (Wits)", shortName: "Wits", city: "Braamfontein, JHB", lat: -26.1902, lng: 28.0302),
    CampusPreset(name: "University of Johannesburg (UJ Kingsway)", shortName: "UJ APK", city: "Auckland Park, JHB", lat: -26.1825, lng: 27.9975),
    CampusPreset(name: "University of Johannesburg (UJ Bunting)", shortName: "UJ APB", city: "Auckland Park, JHB", lat: -26.1895, lng: 28.0125),
    CampusPreset(name: "University of Johannesburg (UJ Doornfontein)", shortName: "UJ DFC", city: "Doornfontein, JHB", lat: -26.1925, lng: 28.0580),
    CampusPreset(name: "University of Johannesburg (UJ Soweto)", shortName: "UJ SWC", city: "Soweto, JHB", lat: -26.2575, lng: 27.8631),
    CampusPreset(name: "University of Pretoria (UP)", shortName: "UP / Tuks", city: "Hatfield, Pretoria", lat: -25.7545, lng: 28.2314),
    CampusPreset(name: "Tshwane University of Technology (TUT)", shortName: "TUT", city: "Pretoria West", lat: -25.7317, lng: 28.1633),
    CampusPreset(name: "Sefako Makgatho Health Sciences (SMU)", shortName: "SMU", city: "Ga-Rankuwa, Pretoria", lat: -25.6190, lng: 28.0195),
    CampusPreset(name: "University of KwaZulu-Natal (UKZN Howard)", shortName: "UKZN", city: "Durban", lat: -29.8674, lng: 30.9814),
    CampusPreset(name: "University of KwaZulu-Natal (UKZN Westville)", shortName: "UKZN", city: "Westville, Durban", lat: -29.8183, lng: 30.9436),
    CampusPreset(name: "Durban University of Technology (DUT)", shortName: "DUT", city: "Berea, Durban", lat: -29.8519, lng: 31.0094),
    CampusPreset(name: "Mangosuthu University of Tech (MUT)", shortName: "MUT", city: "Umlazi, Durban", lat: -29.9701, lng: 30.9127),
    CampusPreset(name: "Nelson Mandela University (NMU)", shortName: "NMU", city: "Gqeberha / PE", lat: -34.0044, lng: 25.6705),
    CampusPreset(name: "Rhodes University", shortName: "Rhodes", city: "Makhanda / Grahamstown", lat: -33.3142, lng: 26.5186),
    CampusPreset(name: "University of Fort Hare", shortName: "UFH", city: "Alice / East London", lat: -32.7876, lng: 26.8488),
    CampusPreset(name: "Walter Sisulu University (WSU)", shortName: "WSU", city: "Mthatha", lat: -31.5975, lng: 28.7519),
    CampusPreset(name: "University of the Free State (UFS)", shortName: "UFS / Kovsies", city: "Bloemfontein", lat: -29.1077, lng: 26.1837),
    CampusPreset(name: "Central University of Technology (CUT)", shortName: "CUT", city: "Bloemfontein", lat: -29.1211, lng: 26.2167),
    CampusPreset(name: "North-West University (NWU Potchefstroom)", shortName: "NWU", city: "Potchefstroom", lat: -26.6917, lng: 27.0944),
    CampusPreset(name: "North-West University (NWU Mahikeng)", shortName: "NWU", city: "Mahikeng", lat: -25.8286, lng: 25.6094),
    CampusPreset(name: "North-West University (NWU Vaal)", shortName: "NWU", city: "Vanderbijlpark", lat: -26.7136, lng: 27.8814),
    CampusPreset(name: "Vaal University of Technology (VUT)", shortName: "VUT", city: "Vanderbijlpark", lat: -26.7119, lng: 27.8576),
    CampusPreset(name: "University of Limpopo (Turfloop)", shortName: "UL", city: "Mankweng, Polokwane", lat: -23.8864, lng: 29.7381),
    CampusPreset(name: "University of Venda (Univen)", shortName: "Univen", city: "Thohoyandou", lat: -22.9756, lng: 30.4444),
    CampusPreset(name: "University of Mpumalanga (UMP)", shortName: "UMP", city: "Mbombela / Nelspruit", lat: -25.4385, lng: 30.9817),
    CampusPreset(name: "Sol Plaatje University (SPU)", shortName: "SPU", city: "Kimberley", lat: -28.7423, lng: 24.7648)
]

let QUICK_CAMPUS_PRESETS: [CampusPreset] = [
    CampusPreset(name: "University of the Western Cape (UWC)", shortName: "UWC (Cape Town)", city: "Bellville", lat: -33.9333, lng: 18.6315),
    CampusPreset(name: "University of Johannesburg (UJ Kingsway)", shortName: "UJ Kingsway", city: "Auckland Park", lat: -26.1825, lng: 27.9975),
    CampusPreset(name: "University of the Witwatersrand (Wits)", shortName: "Wits Braamfontein", city: "Braamfontein", lat: -26.1902, lng: 28.0302),
    CampusPreset(name: "University of Cape Town (UCT)", shortName: "UCT Rondebosch", city: "Rondebosch", lat: -33.9576, lng: 18.4611),
    CampusPreset(name: "University of Pretoria (UP)", shortName: "UP Hatfield", city: "Hatfield", lat: -25.7545, lng: 28.2314),
    CampusPreset(name: "Campus Square Mall", shortName: "Campus Square", city: "Auckland Park", lat: -26.1815, lng: 27.9985),
    CampusPreset(name: "Durban University of Tech (DUT)", shortName: "DUT Berea", city: "Durban", lat: -29.8519, lng: 31.0094)
]

let DEFAULT_CAMPUS_VENDORS: [VendorLocation] = [
    VendorLocation(id: "1", name: "Campus Cafeteria", category: "Food & Dining", address: "Kingsway Campus - Block B", lat: -26.1825, lng: 27.9975),
    VendorLocation(id: "2", name: "Stationery & Print Shop", category: "Books & Supplies", address: "Student Center Ground Floor", lat: -26.1840, lng: 27.9990),
    VendorLocation(id: "3", name: "Campus Square Fresh Grocery", category: "Groceries & Snacks", address: "Campus Square Mall", lat: -26.1815, lng: 27.9985)
]

// MARK: - In-App Navigation Route Models (Matches InAppNavigation.kt 1:1)
struct NavStep: Equatable {
    let instruction: String
    let maneuver: String
    let distanceText: String
    let end: CLLocationCoordinate2D

    static func == (lhs: NavStep, rhs: NavStep) -> Bool {
        lhs.instruction == rhs.instruction &&
        lhs.maneuver == rhs.maneuver &&
        lhs.distanceText == rhs.distanceText &&
        lhs.end.latitude == rhs.end.latitude &&
        lhs.end.longitude == rhs.end.longitude
    }
}

struct NavRoute: Equatable {
    let points: [CLLocationCoordinate2D]
    let steps: [NavStep]
    let distanceText: String
    let durationText: String

    static func == (lhs: NavRoute, rhs: NavRoute) -> Bool {
        lhs.points.count == rhs.points.count &&
        lhs.steps == rhs.steps &&
        lhs.distanceText == rhs.distanceText &&
        lhs.durationText == rhs.durationText
    }
}
