import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore

/// Partnered Vendors Map, 30-Campus SA Search & Turn-by-Turn Navigation Screen
/// replicating `VendorsMapScreen.kt` 1:1.
struct VendorsMapView: View {
    let onBack: () -> Void

    @StateObject private var locationManager = LocationHeadingManager()

    @State private var vendors: [VendorLocation] = DEFAULT_CAMPUS_VENDORS
    @State private var selectedVendor: VendorLocation? = nil

    // Search State
    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false
    @State private var searchedPlace: SearchedPlacePin? = nil
    @FocusState private var searchFocused: Bool

    // Camera Command State
    @State private var cameraCommand: MapCameraCommand = .centerZoom(
        coordinate: CLLocationCoordinate2D(latitude: -26.1830, longitude: 27.9980),
        altitude: 1700,
        id: UUID()
    )

    // In-App Turn-by-Turn Navigation State
    @State private var route: NavRoute? = nil
    @State private var routeMode: String = "walking"
    @State private var loadingRoute: Bool = false
    @State private var navigating: Bool = false
    @State private var arrived: Bool = false
    @State private var stepIndex: Int = 0
    @State private var navDest: VendorLocation? = nil
    @State private var pendingRouteRequest: (VendorLocation, String)? = nil
    @State private var lastRerouteTime: Date = .distantPast

    @State private var toastMessage: String? = nil
    @State private var vendorsListener: ListenerRegistration? = nil

    private var googleApiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top App Bar
            HStack(spacing: 12) {
                Button(action: {
                    stopNavigation()
                    onBack()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Text("Partnered Vendors")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.crumzDarkBlue.ignoresSafeArea(edges: .top))

            // Interactive Map + Floating Overlays
            ZStack {
                CrumzInteractiveMapRepresentable(
                    vendors: vendors,
                    selectedVendorId: selectedVendor?.id,
                    searchedPlace: searchedPlace,
                    route: route,
                    routeMode: routeMode,
                    showsUserLocation: locationManager.hasLocationPermission,
                    cameraCommand: cameraCommand,
                    onSelectVendor: { v in
                        searchFocused = false
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            selectedVendor = v
                        }
                    },
                    onMapBackgroundTap: {
                        searchFocused = false
                        if !navigating {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedVendor = nil
                            }
                        }
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                // Top Search Bar & Campus Presets (hidden when actively navigating)
                if !navigating {
                    VStack(spacing: 0) {
                        floatingSearchBarCard

                        quickCampusPresetsRow
                            .padding(.top, 8)

                        autocompleteDropdownCard

                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 14)
                }

                // Active Turn-by-Turn Navigation Banner
                if navigating, let activeRoute = route {
                    VStack {
                        let currentStep = activeRoute.steps.indices.contains(stepIndex)
                            ? activeRoute.steps[stepIndex]
                            : nil

                        VStack(alignment: .leading, spacing: 4) {
                            Text(arrived ? "You have arrived!" : (currentStep?.instruction ?? "Continue to destination"))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)

                            if !arrived, let s = currentStep {
                                Text("for \(s.distanceText)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.crumzGold)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.crumzDarkBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                        .padding(12)

                        Spacer()
                    }
                }

                // My Location Floating Button
                if locationManager.hasLocationPermission, let loc = locationManager.userLocation {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                cameraCommand = .centerZoom(
                                    coordinate: loc.coordinate,
                                    altitude: 1200,
                                    id: UUID()
                                )
                            }) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.crumzDarkBlue)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.bottom, selectedVendor != nil ? 210 : 28)
                        }
                    }
                }

                // Bottom Sliding Vendor Detail & Navigation Card
                if let vendor = selectedVendor {
                    VStack {
                        Spacer()
                        vendorBottomSheet(vendor)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .crumzToast($toastMessage)
        .onAppear {
            locationManager.refreshAuthorizationState()
            attachVendorsListener()
        }
        .onDisappear {
            vendorsListener?.remove()
            vendorsListener = nil
            locationManager.setHeadingUpdates(active: false)
        }
        .onChange(of: navigating) { isNav in
            locationManager.setHeadingUpdates(active: isNav)
        }
        .onChange(of: locationManager.userLocation) { newLoc in
            handleNavigationProgressUpdate(location: newLoc)
        }
        .onChange(of: Int((locationManager.compassHeading ?? 0.0) / 6.0)) { _ in
            handleNavigationProgressUpdate(location: locationManager.userLocation)
        }
    }

    // MARK: - Top Floating Search Card
    private var floatingSearchBarCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.crumzDarkBlue)

            TextField(
                "",
                text: $searchQuery,
                prompt: Text("Search campus (e.g. UWC, UJ, Wits)...")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x94A3B8))
            )
            .focused($searchFocused)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.crumzDarkBlue)
            .tint(.crumzGold)
            .submitLabel(.search)
            .onSubmit {
                performSearch(searchQuery)
            }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchedPlace = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            Button(action: { performSearch(searchQuery) }) {
                ZStack {
                    Circle()
                        .fill(Color.crumzDarkBlue)
                        .frame(width: 38, height: 38)
                    if isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
    }

    // MARK: - Quick Campus Presets Chip Bar
    private var quickCampusPresetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QUICK_CAMPUS_PRESETS) { preset in
                    Button(action: {
                        selectLocation(name: preset.name, coordinate: preset.coordinate)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.crumzGold)
                            Text(preset.shortName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.crumzDarkBlue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Real-Time Autocomplete Dropdown
    @ViewBuilder
    private var autocompleteDropdownCard: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 && searchFocused {
            let matchingCampuses = Array(SA_CAMPUSES.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.shortName.localizedCaseInsensitiveContains(trimmed) ||
                $0.city.localizedCaseInsensitiveContains(trimmed)
            }.prefix(4))

            let matchingVendors = Array(vendors.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.address.localizedCaseInsensitiveContains(trimmed)
            }.prefix(3))

            if !matchingCampuses.isEmpty || !matchingVendors.isEmpty {
                VStack(spacing: 0) {
                    ForEach(matchingCampuses) { campus in
                        Button(action: {
                            selectLocation(name: campus.name, coordinate: campus.coordinate)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.crumzGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(campus.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.crumzDarkBlue)
                                        .lineLimit(1)
                                    Text(campus.city)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().background(Color(hex: 0xF1F5F9))
                    }

                    ForEach(matchingVendors) { vendor in
                        Button(action: {
                            selectVendor(vendor)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "storefront.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.crumzDarkBlue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vendor.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.crumzDarkBlue)
                                        .lineLimit(1)
                                    Text("\(vendor.category) • \(vendor.address)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().background(Color(hex: 0xF1F5F9))
                    }
                }
                .padding(.vertical, 4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Vendor Bottom Sheet
    private func vendorBottomSheet(_ vendor: VendorLocation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.crumzDarkBlue.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "storefront.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.crumzDarkBlue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vendor.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.crumzDarkBlue)
                        Text("\(vendor.category) • \(vendor.address)")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0x64748B))
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedVendor = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 16)

            if loadingRoute {
                HStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .crumzGold))
                    Text("Finding best route...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x475569))
                    Spacer()
                }
                .padding(.vertical, 6)
            } else if let activeRoute = route {
                Text("\(activeRoute.durationText) • \(activeRoute.distanceText) (\(routeMode == "walking" ? "Walking" : "Driving"))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.crumzDarkBlue)

                Spacer().frame(height: 10)

                HStack(spacing: 12) {
                    Button(action: stopNavigation) {
                        Text(navigating ? "End" : "Cancel")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.crumzDarkBlue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(hex: 0xCBD5E1), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    if !navigating {
                        Button(action: {
                            navigating = true
                            stepIndex = 0
                        }) {
                            Text("Start")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(hex: 0x16A34A))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Navigation Options:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: 0x475569))

                Spacer().frame(height: 8)

                HStack(spacing: 12) {
                    Button(action: { beginRoute(vendor: vendor, mode: "walking") }) {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 16, weight: .bold))
                            Text("Walk")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.crumzDarkBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { beginRoute(vendor: vendor, mode: "driving") }) {
                        HStack(spacing: 6) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Drive")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.crumzGold)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(16)
    }

    // MARK: - Search & Navigation Logic
    private func selectLocation(name: String, coordinate: CLLocationCoordinate2D) {
        searchFocused = false
        searchQuery = name
        searchedPlace = SearchedPlacePin(name: name, coordinate: coordinate)
        selectedVendor = nil
        cameraCommand = .centerZoom(coordinate: coordinate, altitude: 1100, id: UUID())
    }

    private func selectVendor(_ vendor: VendorLocation) {
        searchFocused = false
        searchQuery = vendor.name
        searchedPlace = SearchedPlacePin(name: vendor.name, coordinate: vendor.coordinate)
        selectedVendor = vendor
        cameraCommand = .centerZoom(coordinate: vendor.coordinate, altitude: 800, id: UUID())
    }

    private func performSearch(_ rawQuery: String) {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchFocused = false

        // 1. Check SA_CAMPUSES (30 campuses)
        if let campusMatch = SA_CAMPUSES.first(where: {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.shortName.caseInsensitiveCompare(q) == .orderedSame ||
            $0.city.localizedCaseInsensitiveContains(q)
        }) {
            selectLocation(name: campusMatch.name, coordinate: campusMatch.coordinate)
            toastMessage = "Navigated to \(campusMatch.name)"
            return
        }

        // 2. Check partnered vendors
        if let vendorMatch = vendors.first(where: {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.address.localizedCaseInsensitiveContains(q)
        }) {
            selectVendor(vendorMatch)
            toastMessage = "Found vendor: \(vendorMatch.name)"
            return
        }

        // 3. Fallback to CLGeocoder lookup in South Africa
        isSearching = true
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString("\(q), South Africa") { placemarks, error in
            isSearching = false
            if let first = placemarks?.first, let loc = first.location {
                let placeName = first.name ?? first.locality ?? q
                selectLocation(name: placeName, coordinate: loc.coordinate)
                toastMessage = "Found: \(placeName)"
            } else if let error = error {
                toastMessage = "Location not found (\(error.localizedDescription)). Try 'UWC' or 'UJ'."
            } else {
                toastMessage = "Location not found. Try searching an institution like 'UWC' or 'UJ'."
            }
        }
    }

    private func beginRoute(vendor: VendorLocation, mode: String) {
        if !locationManager.hasLocationPermission {
            pendingRouteRequest = (vendor, mode)
            locationManager.requestPermission(
                onGranted: {
                    toastMessage = "Getting your location... tap again in a moment."
                    if let req = pendingRouteRequest, locationManager.userLocation != nil {
                        pendingRouteRequest = nil
                        computeRoute(vendor: req.0, mode: req.1)
                    }
                },
                onDenied: {
                    pendingRouteRequest = nil
                    toastMessage = "Location permission is needed for navigation."
                }
            )
        } else {
            computeRoute(vendor: vendor, mode: mode)
        }
    }

    private func computeRoute(vendor: VendorLocation, mode: String) {
        guard let loc = locationManager.userLocation else {
            toastMessage = "Waiting for your location... make sure Location is turned on."
            return
        }
        loadingRoute = true
        routeMode = mode
        navDest = vendor

        Task {
            let computed = await RouteService.fetchRoute(
                origin: loc.coordinate,
                dest: vendor.coordinate,
                mode: mode,
                apiKey: googleApiKey
            )
            await MainActor.run {
                loadingRoute = false
                if let computed = computed {
                    route = computed
                    cameraCommand = .fitBounds(points: computed.points, id: UUID())
                } else {
                    toastMessage = "Could not find route: \(RouteService.lastNavError ?? "unknown error")"
                }
            }
        }
    }

    private func stopNavigation() {
        navigating = false
        arrived = false
        route = nil
        stepIndex = 0
    }

    private func handleNavigationProgressUpdate(location: CLLocation?) {
        guard navigating, let loc = location, let activeRoute = route else { return }

        // Step advancement within 25m
        if activeRoute.steps.indices.contains(stepIndex) {
            let step = activeRoute.steps[stepIndex]
            let dist = LocationHeadingManager.distanceMeters(from: loc.coordinate, to: step.end)
            if dist < 25.0 {
                if stepIndex >= activeRoute.steps.count - 1 {
                    arrived = true
                } else {
                    stepIndex += 1
                }
            }
        }

        // Off-route detection (>60m walking, >100m driving)
        let offLimit: Double = (routeMode == "walking") ? 60.0 : 100.0
        let minDistanceToRoute = activeRoute.points.map {
            LocationHeadingManager.distanceMeters(from: loc.coordinate, to: $0)
        }.min() ?? 0.0

        let now = Date()
        if !arrived,
           minDistanceToRoute > offLimit,
           let dest = navDest,
           now.timeIntervalSince(lastRerouteTime) > 15.0 {
            lastRerouteTime = now
            Task {
                if let newRoute = await RouteService.fetchRoute(
                    origin: loc.coordinate,
                    dest: dest.coordinate,
                    mode: routeMode,
                    apiKey: googleApiKey
                ) {
                    await MainActor.run {
                        route = newRoute
                        stepIndex = 0
                    }
                }
            }
        }

        // 3D Heading-up camera follow
        let moving = loc.course >= 0 && loc.speed > 1.0
        let ahead = activeRoute.points.first(where: {
            LocationHeadingManager.distanceMeters(from: loc.coordinate, to: $0) > 20.0
        })

        let bearing: Double
        if moving {
            bearing = loc.course
        } else if let heading = locationManager.compassHeading {
            bearing = heading
        } else if let ahead = ahead {
            bearing = LocationHeadingManager.bearingDegrees(from: loc.coordinate, to: ahead)
        } else {
            bearing = 0
        }

        cameraCommand = .followNavigation(
            coordinate: loc.coordinate,
            heading: bearing,
            pitch: 60.0,
            altitude: routeMode == "walking" ? 240.0 : 480.0,
            id: UUID()
        )
    }

    private func attachVendorsListener() {
        vendorsListener?.remove()
        vendorsListener = Firestore.firestore().collection("vendors").addSnapshotListener { snap, _ in
            var loaded: [VendorLocation] = []
            snap?.documents.forEach { doc in
                let d = doc.data()
                guard let name = d["name"] as? String,
                      let lat = (d["latitude"] as? NSNumber)?.doubleValue,
                      let lng = (d["longitude"] as? NSNumber)?.doubleValue
                else { return }
                loaded.append(
                    VendorLocation(
                        id: doc.documentID,
                        name: name,
                        category: d["category"] as? String ?? "Partner Store",
                        address: d["address"] as? String ?? "Campus Location",
                        lat: lat,
                        lng: lng
                    )
                )
            }
            vendors = loaded.isEmpty ? DEFAULT_CAMPUS_VENDORS : loaded
        }
    }
}

// MARK: - Map Helper Types & UIViewRepresentable (`MKMapView`)
struct SearchedPlacePin: Equatable {
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: SearchedPlacePin, rhs: SearchedPlacePin) -> Bool {
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

enum MapCameraCommand: Equatable {
    case centerZoom(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, id: UUID)
    case fitBounds(points: [CLLocationCoordinate2D], id: UUID)
    case followNavigation(coordinate: CLLocationCoordinate2D, heading: CLLocationDirection, pitch: CGFloat, altitude: CLLocationDistance, id: UUID)

    var commandId: UUID {
        switch self {
        case .centerZoom(_, _, let id): return id
        case .fitBounds(_, let id): return id
        case .followNavigation(_, _, _, _, let id): return id
        }
    }

    static func == (lhs: MapCameraCommand, rhs: MapCameraCommand) -> Bool {
        lhs.commandId == rhs.commandId
    }
}

private final class VendorMapAnnotation: NSObject, MKAnnotation {
    let vendor: VendorLocation
    var isSelected: Bool
    var coordinate: CLLocationCoordinate2D { vendor.coordinate }
    var title: String? { vendor.name }

    init(vendor: VendorLocation, isSelected: Bool) {
        self.vendor = vendor
        self.isSelected = isSelected
    }
}

private final class CampusSearchAnnotation: NSObject, MKAnnotation {
    let placeName: String
    let coordinate: CLLocationCoordinate2D
    var title: String? { placeName }

    init(placeName: String, coordinate: CLLocationCoordinate2D) {
        self.placeName = placeName
        self.coordinate = coordinate
    }
}

private struct CrumzInteractiveMapRepresentable: UIViewRepresentable {
    let vendors: [VendorLocation]
    let selectedVendorId: String?
    let searchedPlace: SearchedPlacePin?
    let route: NavRoute?
    let routeMode: String
    let showsUserLocation: Bool
    let cameraCommand: MapCameraCommand
    let onSelectVendor: (VendorLocation) -> Void
    let onMapBackgroundTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.showsUserLocation = showsUserLocation

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)

        context.coordinator.applyCamera(command: cameraCommand, on: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }

        // Sync Annotations when vendors, selection, or searchedPlace changes
        let stateSignature = "\(vendors.map(\.id).joined(separator: ","))|\(selectedVendorId ?? "")|\(searchedPlace?.name ?? "")|\(searchedPlace?.coordinate.latitude ?? 0)"
        if context.coordinator.lastAnnotationSignature != stateSignature {
            context.coordinator.lastAnnotationSignature = stateSignature
            let existing = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(existing)

            for v in vendors {
                mapView.addAnnotation(VendorMapAnnotation(vendor: v, isSelected: v.id == selectedVendorId))
            }
            if let sp = searchedPlace {
                mapView.addAnnotation(CampusSearchAnnotation(placeName: sp.name, coordinate: sp.coordinate))
            }
        }

        // Sync Route Polyline
        let polySignature = "\(route?.points.count ?? 0)|\(route?.distanceText ?? "")|\(routeMode)"
        if context.coordinator.lastPolylineSignature != polySignature {
            context.coordinator.lastPolylineSignature = polySignature
            mapView.removeOverlays(mapView.overlays)
            if let r = route, !r.points.isEmpty {
                var pts = r.points
                let poly = MKPolyline(coordinates: &pts, count: pts.count)
                mapView.addOverlay(poly)
            }
        }

        // Apply Camera Command if new
        if context.coordinator.lastCameraCommandId != cameraCommand.commandId {
            context.coordinator.applyCamera(command: cameraCommand, on: mapView, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CrumzInteractiveMapRepresentable
        var lastAnnotationSignature: String = ""
        var lastPolylineSignature: String = ""
        var lastCameraCommandId: UUID?

        init(parent: CrumzInteractiveMapRepresentable) {
            self.parent = parent
        }

        func applyCamera(command: MapCameraCommand, on mapView: MKMapView, animated: Bool) {
            lastCameraCommandId = command.commandId
            switch command {
            case .centerZoom(let coord, let altitude, _):
                let cam = MKMapCamera(lookingAtCenter: coord, fromDistance: altitude, pitch: 0, heading: 0)
                mapView.setCamera(cam, animated: animated)

            case .fitBounds(let points, _):
                guard !points.isEmpty else { return }
                var pts = points
                let poly = MKPolyline(coordinates: &pts, count: pts.count)
                mapView.setVisibleMapRect(
                    poly.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 140, left: 60, bottom: 260, right: 60),
                    animated: animated
                )

            case .followNavigation(let coord, let heading, let pitch, let altitude, _):
                let cam = MKMapCamera(lookingAtCenter: coord, fromDistance: altitude, pitch: pitch, heading: heading)
                UIView.animate(withDuration: 0.55) {
                    mapView.camera = cam
                }
            }
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                if let view = mapView.view(for: annotation) {
                    let converted = mapView.convert(point, to: view)
                    if view.bounds.contains(converted) {
                        return
                    }
                }
            }
            parent.onMapBackgroundTap()
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let vendorAnn = view.annotation as? VendorMapAnnotation {
                mapView.deselectAnnotation(vendorAnn, animated: false)
                parent.onSelectVendor(vendorAnn.vendor)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = parent.routeMode == "walking"
                    ? UIColor(red: 37.0 / 255.0, green: 99.0 / 255.0, blue: 235.0 / 255.0, alpha: 1.0)
                    : UIColor.crumzGold
                renderer.lineWidth = 6.0
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let vendorAnn = annotation as? VendorMapAnnotation {
                let identifier = "CrumzVendorPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: vendorAnn, reuseIdentifier: identifier)
                view.annotation = vendorAnn
                view.canShowCallout = false
                view.image = Self.renderVendorMarkerImage(isSelected: vendorAnn.isSelected)
                view.centerOffset = CGPoint(x: 0, y: -(view.image?.size.height ?? 44) / 2.0)
                return view
            }

            if let campusAnn = annotation as? CampusSearchAnnotation {
                let identifier = "CrumzCampusPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: campusAnn, reuseIdentifier: identifier)
                view.annotation = campusAnn
                view.canShowCallout = false
                view.image = Self.renderCampusBadgeImage(title: String(campusAnn.placeName.prefix(28)))
                view.centerOffset = CGPoint(x: 0, y: -(view.image?.size.height ?? 36) / 2.0)
                return view
            }

            return nil
        }

        /// Renders the custom circular Crumz "C" vendor marker matching Android's `MarkerComposable`
        private static func renderVendorMarkerImage(isSelected: Bool) -> UIImage {
            let circleDiameter: CGFloat = isSelected ? 46 : 38
            let dotSize: CGFloat = 6
            let totalWidth = circleDiameter + 4
            let totalHeight = circleDiameter + dotSize + 4

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
            return renderer.image { ctx in
                let cg = ctx.cgContext
                let circleRect = CGRect(x: 2, y: 2, width: circleDiameter, height: circleDiameter)

                cg.setFillColor(UIColor.crumzDarkBlue.cgColor)
                cg.fillEllipse(in: circleRect)

                cg.setStrokeColor(UIColor.crumzGold.cgColor)
                cg.setLineWidth(2.5)
                cg.strokeEllipse(in: circleRect.insetBy(dx: 1.25, dy: 1.25))

                let font = UIFont.systemFont(ofSize: isSelected ? 22 : 18, weight: .heavy)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
                let letter = "C" as NSString
                let textSize = letter.size(withAttributes: attrs)
                let textOrigin = CGPoint(
                    x: circleRect.midX - textSize.width / 2.0,
                    y: circleRect.midY - textSize.height / 2.0
                )
                letter.draw(at: textOrigin, withAttributes: attrs)

                let dotRect = CGRect(
                    x: (totalWidth - dotSize) / 2.0,
                    y: circleRect.maxY + 1,
                    width: dotSize,
                    height: dotSize
                )
                cg.setFillColor(UIColor.crumzGold.cgColor)
                cg.fillEllipse(in: dotRect)
            }
        }

        /// Renders the Gold Campus Search Marker badge matching Android's `searchedPlace` `MarkerComposable`
        private static func renderCampusBadgeImage(title: String) -> UIImage {
            let label = "🎓 \(title)" as NSString
            let font = UIFont.systemFont(ofSize: 12, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let textSize = label.size(withAttributes: attrs)
            let pillWidth = textSize.width + 20
            let pillHeight: CGFloat = 28
            let dotSize: CGFloat = 8
            let totalWidth = pillWidth + 4
            let totalHeight = pillHeight + dotSize + 5

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
            return renderer.image { ctx in
                let cg = ctx.cgContext
                let pillRect = CGRect(x: 2, y: 2, width: pillWidth, height: pillHeight)
                let path = UIBezierPath(roundedRect: pillRect, cornerRadius: 10)

                cg.setFillColor(UIColor.crumzGold.cgColor)
                cg.addPath(path.cgPath)
                cg.fillPath()

                cg.setStrokeColor(UIColor.crumzDarkBlue.cgColor)
                cg.setLineWidth(2.0)
                cg.addPath(path.cgPath)
                cg.strokePath()

                let textOrigin = CGPoint(
                    x: pillRect.midX - textSize.width / 2.0,
                    y: pillRect.midY - textSize.height / 2.0
                )
                label.draw(at: textOrigin, withAttributes: attrs)

                let dotRect = CGRect(
                    x: (totalWidth - dotSize) / 2.0,
                    y: pillRect.maxY + 2,
                    width: dotSize,
                    height: dotSize
                )
                cg.setFillColor(UIColor.crumzDarkBlue.cgColor)
                cg.fillEllipse(in: dotRect)
            }
        }
    }
}
