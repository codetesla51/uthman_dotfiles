import Quickshell
import "components"
import "modules"

ShellRoot {
    Bar {}

    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }

    Colors { id: barPalette }
}
