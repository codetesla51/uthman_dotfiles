import Quickshell
import "components"
import "modules"

ShellRoot {
    Bar {}

    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    AudioVisualizer { colors: barPalette }

    Colors { id: barPalette }
}
