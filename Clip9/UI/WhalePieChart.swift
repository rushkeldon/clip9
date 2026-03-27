import SwiftUI

/// Red pie chart badge showing how many display-countdown slices remain.
/// 4 = full circle, 3 = 3/4, 2 = 1/2, 1 = 1/4, 0 = triggers pop animation.
struct WhalePieChart: View {
    let remainingDisplays: Int
    let size: CGFloat

    private var fraction: Double {
        Double(max(0, min(4, remainingDisplays))) / 4.0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
            PieSlice(fraction: fraction)
                .fill(Color.red)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }
}

private struct PieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle(degrees: -90)
        let endAngle = Angle(degrees: -90 + 360 * fraction)

        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}
