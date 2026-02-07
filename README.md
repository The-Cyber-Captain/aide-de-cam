# Aide-De-Cam

## A Godot Android[^1] Plugin which reports on camera 'capabilities'.  
[^1]:*Leveraging Camera2, so Android-only.*

### How to use:

Get the plugin instance  

    var adc = Engine.get_singleton("AideDeCam")

Check if it loaded successfully  

    if adc:
        # Call methods on the plugin
        var result = adc.some_method_with_return()
    else:
        print("Plugin not found - are you running on Android?")

### Installation

#### Release:

- Download the Release [TODO]: "or grab it from the [Godot Asset Library](https://godotengine.org/asset-library/asset)"  
- Drop aide_de_cam/ into addons/  
- Enable addon in Godot  

    Project -> Project Settings -> Plugins -> AideDeCam :ballot_box_with_check: 

- Profit?
  
#### Building from source:

Sure, why not? Enjoy. 😉 [TODO]

### Support me! 🥛🍞

<a href='https://ko-fi.com/L4L81SGS9W' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi6.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
