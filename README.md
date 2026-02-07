# Aide-De-Cam

## A Godot Android[^1] Plugin which reports on camera 'capabilities'.  
[^1]:*Leveraging Camera2, so Android-only.*

## Requirements
- **Godot 4.3 or higher**
- Android API 21+ (Android 5.0 Lollipop or higher)

## Compatibility
- Built against: Godot 4.3
- ~~Tested with: Godot 4.3, 4.4, 4.5, 4.6~~
- Should work with future Godot 4.x releases

### How to use:

Get the plugin instance  

    var aide = Engine.get_singleton("AideDeCam")

Check if it loaded successfully, and call the method  

    if adc:      
        # Get capabilities (saves to user dir, returns JSON string)
        var capabilities_json = aide.getCameraCapabilities()
        
        # As per above, but also save to Documents with timestamp
        var capabilities_with_docs = aide.getCameraCapabilities(true)
        
    else:
        print("Plugin not found - are you running on Android?")

### Output:
SDK Version:  
Always included in output, with minimum SDK check (21 for Camera2)  

Concurrent Camera Support:  
Reports which camera combinations can be used simultaneously (Android 11+)
Shows max concurrent cameras and valid combinations

Vendor Implementation Validation:  
Validates all numeric values (sizes, ISO, focal lengths, FPS)
Collects warnings for missing or invalid vendor data
Per-camera warnings array + global warnings summary

Logical Multi-Camera:  
Detects multi-lens setups with sync type info. Well... it *Should*. Currently untested as [@The-Cyber-Captain](https://github.com/The-Cyber-Captain) has no such hardware.

### Installation

#### Release:

- Download the Release [TODO]: "or grab it from the [Godot Asset Library](https://godotengine.org/asset-library/asset)"  
- Drop aide_de_cam/ into addons/  
- Enable addon in Godot  

    Project -> Project Settings -> Plugins -> AideDeCam :ballot_box_with_check: 

- Profit?
  
#### Building from source:

Sure, why not? Enjoy. 😉 [TODO]: Document source build

### Licensing
Code: The Unlicense  
Build tooling: Gradle Wrapper (Apache-2.0), see THIRD_PARTY_NOTICES.md  

### Support me! 🥛🍞

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L4L81SGS9W)
