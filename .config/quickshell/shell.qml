import Quickshell
import Quickshell.Io
import "components"
import "modules"

ShellRoot {
    Bar {}

    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    AudioVisualizer { colors: barPalette }
    QuickNotes { colors: barPalette }

    Colors { id: barPalette }
}
