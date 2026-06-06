# Garmin Instinct 2 Solar Battery Monitor App

A custom Garmin Connect IQ Device App (with Glance support) designed and optimized specifically for the **Garmin Instinct 2 Solar** smartwatch. 

This app logs battery percentage, charger state, and solar charging intensity once per hour in the background, keeping a rolling 30-day history (720 logs) in persistent storage. It calculates custom discharge rates, remaining battery life estimates based on usage, and separate daily AC vs. Solar charging gains. It also renders a beautiful monochrome history chart of your battery level directly on the watch screen.

---

## Folder Structure

```
garmin-battery-monitor/
├── manifest.xml                 # Target devices, UUID, and Background permissions
├── monkey.jungle                # Project build path configurations
├── README.md                    # Setup and sideloading instructions (this file)
├── resources/
│   ├── drawables/
│   │   ├── drawables.xml        # Declares drawable assets
│   │   └── launcher_icon.png    # 40x40 black launcher icon (required by compiler)
│   └── strings/
│       └── strings.xml          # Declares localizable strings (AppName, etc.)
└── source/
    ├── BatteryMonitorApp.mc     # Main application lifecycle & service registration
    ├── BatteryMonitorDelegate.mc# Handlers for button interactions (UP/DOWN/GPS/MENU)
    ├── BatteryMonitorGlanceView.mc# Memory-safe widget glance loop display
    ├── BatteryMonitorServiceDelegate.mc# Background temporal logger (runs hourly)
    └── BatteryMonitorView.mc    # Core UI, analytics calculations, and graph rendering
```

---

## System Requirements

To build and run this application on your Mac, you need:
1. **Visual Studio Code** installed.
2. **Java Runtime Environment (JRE)** (v8 or later) installed on your Mac. 
   - *Check in Terminal:* `java -version`. 
   - If not found, download and install the standard JRE or JDK from [Adoptium (Temurin)](https://adoptium.net/) or Oracle.
3. **Garmin Connect IQ SDK Manager** and SDK.

---

## Getting Started: VS Code Setup

1. **Open VS Code** and select **File > Open Folder...**.
2. Open the `garmin-battery-monitor` project folder.
3. Open the VS Code Extensions Marketplace (`Cmd + Shift + X`), search for **"Monkey C"** (by Garmin), and install it.
4. Once installed, open the VS Code Command Palette (`Cmd + Shift + P`) and run **"Monkey C: Verify Installation"**.
   - If prompted, download the **Connect IQ SDK Manager** via the link provided.
   - Run the SDK Manager and download the latest **Connect IQ SDK** and the device files for the **Instinct 2** (under the "Devices" tab).
5. Set the active SDK by running **"Monkey C: Choose SDK"** in the Command Palette and selecting the SDK version you just downloaded.

---

## Running in the Simulator

1. Open `source/BatteryMonitorApp.mc` in VS Code.
2. Press **`F5`** (or go to **Run > Start Debugging**).
3. If prompted to select a device, choose **`instinct2`** (which supports the Instinct 2 and Instinct 2 Solar profiles).
4. The Connect IQ Simulator will launch and show the app's initial screen.
5. **Seeding Initial Data**:
   - Because the background service only fires once an hour, the graph and analytics will initially show "Collecting data...".
   - You can manually record data points immediately by pressing the **GPS (Enter)** key. Press it a few times (waiting a few seconds in between) to see the battery graph start to populate!
6. **Simulating charging states**:
   - In the Simulator menu, go to **Activity > Battery** or **Simulation > Battery** to change the battery level.
   - To simulate AC charging, check the **Charging** checkbox in the simulator.
   - To simulate Solar charging, slide the **Solar Intensity** slider to a value greater than 10.
   - Trigger a manual log (GPS key) after changing these settings, and you will see the sub-screen icon change dynamically (Lightning Bolt for AC charging, Sun icon for Solar charging, or battery number for normal discharging).
7. **Simulating background logs**:
   - To simulate the background logger running every hour, go to **Simulation > Background Event** in the simulator menu. This will trigger the background `onTemporalEvent` log manually, appending a data point to your persistent storage.

---

## Controls

*   **DOWN Button**: Toggles between Page 1 (Statistics) and Page 2 (History Graph).
*   **UP Button**: Toggles between Page 1 (Statistics) and Page 2 (History Graph).
*   **GPS (Enter) Button**:
    - *On Stats Page:* Triggers an immediate manual battery log.
    - *On Graph Page:* Cycles the graph duration between **24 Hours**, **7 Days**, and **30 Days**.
*   **Hold UP (MENU) Button**: Opens the **Reset Logs** screen. Press **GPS** to confirm reset or **BACK** to cancel.

---

## Sideloading onto your physical Instinct 2 Solar

To load the app onto your watch:
1. Plug your Garmin Instinct 2 Solar into your Mac using the USB cable. The watch should mount as a USB drive.
2. In VS Code, open the Command Palette (`Cmd + Shift + P`) and run **"Monkey C: Build for Device"**.
3. Select **`instinct2`** as the device.
4. Select a folder on your Mac (e.g., your Desktop) to output the compiled file.
5. Once the build completes, copy the generated `.prg` file (e.g. `BatteryMonitor.prg`) from your Mac.
6. Open your Finder, navigate to the mounted Garmin watch drive, and open the folder **`GARMIN/APPS/`**.
7. Paste the `.prg` file into the `GARMIN/APPS/` folder.
8. Unmount/eject the watch from your Mac and unplug it.
9. Press the **GPS** button on your watch, scroll to the bottom of your activities list, and you will find **Battery Monitor** ready to launch! The widget glance will also appear in your standard widget glance loop as you scroll up/down from the main watch face.
