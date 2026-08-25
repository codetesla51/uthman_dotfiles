import Quickshell
import Quickshell.Io
import "components"
import "modules"
import "modules/pet"

ShellRoot {
    Pet {}
    Bar {}

    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    AudioVisualizer { colors: barPalette }
    QuickNotes { colors: barPalette }

    Colors { id: barPalette }
}
