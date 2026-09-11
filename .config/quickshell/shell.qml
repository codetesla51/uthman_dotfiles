import Quickshell
import Quickshell.Io
import "components"
import "modules"

ShellRoot {
    Bar { id: mainBar }

    NowPlayingCard { colors: barPalette; hovered: mainBar.musicHover }

    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    AudioVisualizer { colors: barPalette }
    QuickNotes { colors: barPalette }
    PkgManager { colors: barPalette }
    SnapperPanel { colors: barPalette }
    ControlCenter { colors: barPalette }
    PdfViewer { colors: barPalette }
    PassPrompt { colors: barPalette }
    Wallshelf { colors: barPalette }

    Colors { id: barPalette }
}
