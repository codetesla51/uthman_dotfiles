import Quickshell
import Quickshell.Io
import "components"
import "modules"

ShellRoot {
    Bar { id: mainBar }

    NowPlayingCard { colors: barPalette; hovered: mainBar.musicHover }

    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    QuickNotes { colors: barPalette }
    PkgManager { colors: barPalette }
    ControlCenter { colors: barPalette }
    Pomodoro { colors: barPalette }
    GitHubDash { colors: barPalette }
    PdfViewer { colors: barPalette }
    PassPrompt { colors: barPalette }
    Wallshelf { colors: barPalette }
    WorkspaceViewer { colors: barPalette }

    Colors { id: barPalette }
}
