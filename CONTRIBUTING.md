# Contributing to Godot 3D Multiplayer Template

If you wish to contribute to the project, please follow the steps below to ensure your contribution is organized and easily integrated into the main repository.

## How to Contribute

1. **Fork the repository**: Create a fork of the repository so you can work on your changes.
2. **Clone your fork**: Clone your fork to your local machine.
3. **Create a new branch**: Always create a new branch for each feature or bugfix. Naming your branch descriptively is helpful.
   - Example: `fix/chat-freeze-bug` or `feature/player-skin-selection`
4. **Make your changes**: Implement the feature or bug fix.
5. **Commit your changes**: Write clear and concise commit messages following this format:
   - `fix: <description of the bug fix>`
   - `feat: <description of the feature>`
   - `docs: <documentation changes>`
6. **Push your changes**: Push the branch to your fork on GitHub.
7. **Submit a Pull Request**: Go to the "Pull Requests" tab in the original repository and submit your changes.

## Testing

Before submitting a pull request, please ensure your changes work in both:

1. **Host/Client Mode:** Run multiple instances locally to verify player interaction.
2. **Dedicated Server Mode:** Use the provided scripts to run a headless server and connect to it with a client.

### Unit Tests (GUT)

This project uses [GUT](https://github.com/bitwes/Gut) for automated unit tests.

1. Install GUT into `res://addons/gut/`:
   - Option A: Godot Asset Library (search for `GUT` and install)
   - Option B: Git submodule
     ```bash
     git submodule add https://github.com/bitwes/Gut.git addons/gut
     ```
2. Ensure the plugin is enabled in `project.godot`:
   - `[editor_plugins]`
   - `enabled=PackedStringArray("res://addons/gut/plugin.cfg")`
3. Run the unit test suite from project root:
   ```bash
   bash run_tests.sh
   ```

Thank you for contributing!
