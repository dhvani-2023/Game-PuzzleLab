import SwiftUI

/// Icons are SF Symbol names. `ImageVector` keeps the Kotlin type name so ported signatures read the same.
typealias ImageVector = String

/// The Material icons the Android app uses, mapped to SF Symbols, so `Icons.Rounded.Star` ports verbatim.
enum Icons {
    enum Rounded {
        static let AcUnit = "snowflake"
        static let Add = "plus"
        static let AirplanemodeActive = "airplane"
        static let AllInclusive = "infinity"
        static let Apps = "square.grid.3x3.fill"
        static let AutoAwesome = "sparkles"
        static let AutoFixNormal = "wand.and.stars"
        static let BarChart = "chart.bar.fill"
        static let Bolt = "bolt.fill"
        static let CalendarMonth = "calendar"
        static let Check = "checkmark"
        static let CheckBox = "checkmark.square.fill"
        static let CheckCircle = "checkmark.circle.fill"
        static let Close = "xmark"
        static let Cloud = "cloud.fill"
        static let CropPortrait = "rectangle.portrait"
        static let DeleteForever = "trash.fill"
        static let Diamond = "diamond.fill"
        static let DirectionsRun = "figure.run"
        static let Draw = "pencil.tip"
        static let Eco = "leaf.fill"
        static let Edit = "pencil"
        static let EmojiEvents = "trophy.fill"
        static let Error = "exclamationmark.circle.fill"
        static let Event = "calendar"
        static let Explore = "safari.fill"
        static let Extension = "puzzlepiece.extension.fill"
        static let FastForward = "forward.fill"
        static let Favorite = "heart.fill"
        static let FitScreen = "viewfinder"
        static let Flag = "flag.fill"
        static let Gavel = "hammer.fill"
        static let Gesture = "hand.draw.fill"
        static let GridOn = "squareshape.split.3x3"
        static let GridView = "square.grid.2x2.fill"
        static let HeartBroken = "heart.slash.fill"
        static let Home = "house.fill"
        static let Info = "info.circle.fill"
        static let Key = "key.fill"
        static let Layers = "square.3.layers.3d"
        static let Lightbulb = "lightbulb.fill"
        static let LocalFireDepartment = "flame.fill"
        static let Lock = "lock.fill"
        static let LooksOne = "1.square.fill"
        static let Map = "map.fill"
        static let MonetizationOn = "dollarsign.circle.fill"
        static let NightsStay = "moon.stars.fill"
        static let OpenInFull = "arrow.up.left.and.arrow.down.right"
        static let Palette = "paintpalette.fill"
        static let PanTool = "hand.raised.fill"
        static let Park = "tree.fill"
        static let Pause = "pause.fill"
        static let PlayArrow = "play.fill"
        static let PlayCircle = "play.circle.fill"
        static let PrivacyTip = "hand.raised.fill"
        static let Psychology = "brain.head.profile"
        static let QuestionMark = "questionmark"
        static let Reorder = "line.3.horizontal"
        static let Replay = "arrow.counterclockwise"
        static let Route = "point.topleft.down.to.point.bottomright.curvepath.fill"
        static let Sailing = "sailboat.fill"
        static let Schedule = "clock.fill"
        static let Security = "lock.shield.fill"
        static let Settings = "gearshape.fill"
        static let SmartDisplay = "play.rectangle.fill"
        static let SportsEsports = "gamecontroller.fill"
        static let Star = "star.fill"
        static let Tag = "number"
        static let Terrain = "mountain.2.fill"
        static let Timer = "timer"
        static let TouchApp = "hand.tap.fill"
        static let TrackChanges = "scope"
        static let Undo = "arrow.uturn.backward"
        static let Verified = "checkmark.seal.fill"
        static let Vibration = "iphone.radiowaves.left.and.right"
        static let ViewAgenda = "rectangle.split.1x2.fill"
        static let ViewModule = "square.grid.3x2.fill"
        static let VolumeUp = "speaker.wave.2.fill"
        static let Warning = "exclamationmark.triangle.fill"
        static let Waves = "water.waves"
        static let WbSunny = "sun.max.fill"
        static let WbTwilight = "sunset.fill"
    }

    typealias Filled = Rounded
    typealias Default = Rounded
    typealias Outlined = Rounded

    enum AutoMirrored {
        enum Rounded {
            static let ArrowBack = "arrow.left"
            static let ArrowBackIos = "chevron.left"
            static let ArrowForward = "arrow.right"
            static let KeyboardArrowRight = "chevron.right"
            static let Undo = "arrow.uturn.backward"
        }
        typealias Filled = Rounded
    }
}

/// Compose `Icon(icon, null, tint = …, modifier = Modifier.size(size))`: the symbol fills ~84% of a
/// `size` box, like a Material icon in its 24-unit viewport.
struct Icon: View {
    let icon: ImageVector
    var tint: Color
    var size: CGFloat

    init(_ icon: ImageVector, _ contentDescription: String? = nil, tint: Color = .white, size: CGFloat = 24) {
        self.icon = icon
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Image(systemName: icon)
            .resizable()
            .fontWeight(.bold)
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(width: size * 0.84, height: size * 0.84)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
