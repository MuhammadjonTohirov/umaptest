import SwiftUI
import MapPack

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel

    private var safeAreaInsets: UIEdgeInsets {
        UIApplication.shared.safeAreaInsets
    }

    init(viewModel: @autoclosure @escaping () -> ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        UniversalMapView(viewModel: viewModel.mapModel)
            .onAppear(perform: viewModel.onAppear)
            .overlay {
                VStack {
                    Spacer()

                    TrackingControlsView(
                        isTracking: viewModel.isTrackingMarker,
                        isRouteLoading: viewModel.isRouteLoading,
                        isCameraFollowEnabled: viewModel.isCameraFollowEnabled,
                        onToggleTracking: toggleTrackingState,
                        onReloadRoute: viewModel.reloadRoute,
                        onToggleCameraFollow: viewModel.toggleCameraFollow
                    )
                    .padding(.bottom, Layout.controlsBottomPadding)

                    MapBottomActionsView(
                        statusText: statusText,
                        statusDotColor: statusDotColor,
                        onFocusTap: viewModel.focusToCurrentLocation
                    )
                    .padding(.bottom, safeAreaInsets.bottom + Layout.bottomActionsBottomPadding)
                }
            }
    }

    private func toggleTrackingState() {
        if viewModel.isTrackingMarker {
            viewModel.stopTrackingMarker()
            return
        }

        viewModel.startTrackingMarker()
    }

    private var statusText: String {
        if viewModel.isRouteLoading {
            return "Loading Route"
        }
        if viewModel.isTrackingMarker {
            return "Tracking"
        }
        return viewModel.isRouteLoaded ? "Ready" : "Idle"
    }

    private var statusDotColor: Color {
        if viewModel.isRouteLoading {
            return .orange
        }
        if viewModel.isTrackingMarker {
            return .green
        }
        return viewModel.isRouteLoaded ? .blue : .gray
    }
}

private struct TrackingControlsView: View {
    let isTracking: Bool
    let isRouteLoading: Bool
    let isCameraFollowEnabled: Bool
    let onToggleTracking: () -> Void
    let onReloadRoute: () -> Void
    let onToggleCameraFollow: () -> Void

    var body: some View {
        HStack(spacing: Layout.controlSpacing) {
            Button(action: onToggleTracking) {
                Image(systemName: isTracking ? "stop.fill" : "car.fill")
                .padding(.horizontal, Layout.buttonHorizontalPadding)
                .padding(.vertical, Layout.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .tint(isTracking ? .red : .blue)
            .disabled(isRouteLoading)

            Button(action: onReloadRoute) {
                Image(systemName: "arrow.clockwise")
                .padding(.horizontal, Layout.buttonHorizontalPadding)
                .padding(.vertical, Layout.buttonVerticalPadding)
            }
            .buttonStyle(.bordered)
            .disabled(isRouteLoading)

            Button(action: onToggleCameraFollow) {
                Image(systemName: isCameraFollowEnabled ? "location.fill" : "location.slash")
                .padding(.horizontal, Layout.buttonHorizontalPadding)
                .padding(.vertical, Layout.buttonVerticalPadding)
            }
            .buttonStyle(.bordered)
            .disabled(isRouteLoading)
        }
        .padding(.horizontal, Layout.horizontalPadding)
    }
}

private struct MapBottomActionsView: View {
    let statusText: String
    let statusDotColor: Color
    let onFocusTap: () -> Void

    var body: some View {
        HStack {
            StatusIndicatorView(text: statusText, dotColor: statusDotColor)

            Spacer()

            FocusButtonView(onTap: onFocusTap)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: Layout.bottomActionsHeight)
    }
}

private struct StatusIndicatorView: View {
    let text: String
    let dotColor: Color

    var body: some View {
        HStack(spacing: Layout.statusSpacing) {
            Circle()
                .fill(dotColor)
                .frame(width: Layout.statusDotSize, height: Layout.statusDotSize)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Layout.statusHorizontalPadding)
        .padding(.vertical, Layout.statusVerticalPadding)
        .background(
            Capsule()
                .fill(.background)
                .shadow(color: .black.opacity(Layout.statusShadowOpacity), radius: Layout.statusShadowRadius)
        )
    }
}

private struct FocusButtonView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "scope")
                .font(.system(size: Layout.focusIconSize, weight: .medium))
                .foregroundColor(.primary)
                .padding(Layout.focusButtonPadding)
                .background(
                    Circle()
                        .foregroundStyle(.background)
                        .shadow(
                            color: .black.opacity(Layout.focusButtonShadowOpacity),
                            radius: Layout.focusButtonShadowRadius
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

private enum Layout {
    static let horizontalPadding: CGFloat = 20
    static let controlsBottomPadding: CGFloat = 10
    static let bottomActionsBottomPadding: CGFloat = 10
    static let bottomActionsHeight: CGFloat = 60

    static let controlSpacing: CGFloat = 12
    static let buttonHorizontalPadding: CGFloat = 16
    static let buttonVerticalPadding: CGFloat = 8

    static let statusSpacing: CGFloat = 8
    static let statusDotSize: CGFloat = 8
    static let statusHorizontalPadding: CGFloat = 12
    static let statusVerticalPadding: CGFloat = 6
    static let statusShadowOpacity: CGFloat = 0.1
    static let statusShadowRadius: CGFloat = 2

    static let focusIconSize: CGFloat = 18
    static let focusButtonPadding: CGFloat = 12
    static let focusButtonShadowOpacity: CGFloat = 0.2
    static let focusButtonShadowRadius: CGFloat = 4
}

#Preview {
    ContentView()
}
