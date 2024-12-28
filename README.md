# Godot Unused Asset Finder

A Godot editor plugin that helps you find unused scenes and scripts in your project. It performs a comprehensive scan of your project to identify assets that aren't referenced anywhere, helping you maintain a cleaner project structure.

## Features

- Finds unused `.tscn` scene files
- Finds unused `.gd` script files
- Intelligent detection of:
  - Autoloaded scenes and scripts
  - Resource type scripts
  - Abstract base classes
  - Inherited scenes
- Background scanning (doesn't freeze the editor)
- Progress tracking with detailed status updates
- Ignores addon folder content by default

## Installation

1. Create an `addons/unused_asset_finder` directory in your project
2. Copy the plugin files into this directory:
   - `plugin.gd`
   - `plugin.cfg`
   - `dock.tscn`
3. Enable the plugin in Project → Project Settings → Plugins

## Usage

1. Once enabled, the plugin adds a new dock to your editor
2. Click the "Scan" button to start scanning your project
3. The scan runs in the background, allowing you to continue working
4. Results are displayed in a tree view, organized by type (Scenes/Scripts)

## How It Works

The plugin performs several checks to ensure accurate results:

### Scene References
- Direct scene references in node properties
- Scenes in arrays or dictionaries
- Inherited scenes
- Preloaded or loaded scenes in scripts
- Scene paths in strings and variables
- Scenes referenced through Godot's resource system

### Script References
- Attached scripts on nodes
- Scripts in exported variables
- Extended scripts (parent classes)
- Resource type definitions
- Autoloaded scripts
- Scripts referenced in other scripts

## False Positives Prevention

The plugin includes several mechanisms to prevent false positives:

1. Autoload Detection
   - Checks both traditional autoloads and alternative configurations
   - Verifies both exact paths and base paths

2. Resource Scripts
   - Identifies scripts that define custom Resource types
   - These are often used as data containers and might not have direct references

3. Abstract Classes
   - Detects scripts that serve as base classes for other scripts
   - Prevents marking parent classes as unused

4. Addon Exclusion
   - Automatically skips the `res://addons` directory
   - Prevents marking editor plugin files as unused

## Contributing

Feel free to submit issues and enhancement requests!

## License

MIT License

## Credits

Created by Yalt
