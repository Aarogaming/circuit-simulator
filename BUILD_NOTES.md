# Build Notes

Commands run during this environment setup and successful build:

- Open repo:
  - `C:\Users\aarog\Documents\Github\circuit-simulator`
- Compile Java sources:
  - `"C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin\javac.exe" *.java`
- Build jar:
  - `"C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin\jar.exe" cfm circuit.jar Manifest.txt *.class *.txt circuits/`
- Optional legacy fix for applet JS bridge (compatibility): updated `src/ImportExportAppletDialog.java` to use reflection for `JSObject.getWindow(...)`.

Git auth flow command used:

- `"C:\Program Files\GitHub CLI\gh.exe" auth login --hostname github.com --web`
