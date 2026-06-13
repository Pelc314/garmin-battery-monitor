# Garmin Battery Monitor Widget

A custom Garmin Connect IQ **Widget** that logs battery level, charging states, and solar intensity, featuring responsive layouts for both dual-screen Instinct watches and standard circular face watches.

This widget logs battery percentage, charger state, and solar charging intensity every 30 minutes in the background, keeping a rolling 20-day history (960 logs) in persistent storage (capped to fit within background RAM memory limits). It calculates custom discharge rates, remaining battery life estimates based on actual usage, and separate daily AC vs. Solar charging gains. It also renders a beautiful monochrome history chart of your battery level and a page scrollbar directly on the watch screen.

---

## Supported Devices

The widget's layout adapts dynamically based on whether the target watch features a dual-screen subscreen or a standard circular screen:

*   **Garmin Instinct Series** (uses offset layout columns to clear the top-right sub-window circle):
    *   **Instinct 2 / Solar / Dual Power** (device ID: `instinct2`, resolution: `176x176`)
    *   **Instinct 2S / Solar / Dual Power** (device ID: `instinct2s`, resolution: `156x156`)
    *   **Instinct Esports 45mm** (device ID: `instincte45mm`, resolution: `176x176`)
*   **Garmin Circular Watches** (uses centered round layouts):
    *   **Venu 2** (device ID: `venu2`, resolution: `416x416`)
    *   **Vívoactive 4** (device ID: `vivoactive4`, resolution: `260x260`)

---

## Controls

### Button-Only Watches (e.g. Instinct Series)
*   **DOWN Button**: Scrolls to Page 3 (History Graph).
  <img width="382" height="507" alt="image" src="https://github.com/user-attachments/assets/f866efff-66c8-45c4-914a-22905f3cbad3" />

*   **UP Button**: Scrolls to Page 1 (Statistics) and Page 2 (Charging info).
  <img width="380" height="504" alt="image" src="https://github.com/user-attachments/assets/98e28306-324e-4c82-b966-0ddc9006b44d" /> <img width="378" height="503" alt="image" src="https://github.com/user-attachments/assets/438b31c2-d2ec-4445-9a20-44eda6218c38" />

*   **GPS (Enter) Button**:
    - *On Stats Page (Page 1):* Triggers an immediate manual battery log.
    - *On Graph Page (Page 3):* Cycles the graph duration between **24 Hours**, **7 Days**, and **20 Days**.
*   **Hold UP (MENU) Button**: Opens the **Reset Logs** screen. Press **GPS** to confirm reset or **BACK** to cancel.
*   **BACK Button**:
    - *On Graph Page / Charging Page:* Navigates back to the Stats Page.
    - *On Reset Confirmation:* Cancels reset and returns to your previous page.
    - *On Stats Page:* Exits the widget.

### Touchscreen Watches with Glance (e.g. Venu 2)
*   **Swipe UP / Swipe DOWN**: Scroll between Page 1 (Statistics), Page 2 (Charging info), and Page 3 (History Graph).
*   **Screen Tap**:
    - *On Stats Page (Page 1):* Triggers an immediate manual battery log.
    - *On Graph Page (Page 3):* Cycles the graph duration between **24 Hours**, **7 Days**, and **20 Days**.
*   **Long Press Screen / Action Button**: Opens the **Reset Logs** screen. Tap the screen to confirm reset or press the Back physical button to cancel.
*   **Swipe Left-to-Right (or physical Back Button)**: Goes back a page, cancels reset, or exits the widget.

### Touchscreen Watches without Glance (e.g. Vívoactive 4)
*   **Activate Widget**: When scrolling the widget loop, the widget starts in a **passive state** displaying `"Tap to open"` at the bottom. **Tap the screen once** (or press the top-right Action button) to activate it and enable swipe controls.
*   **Swipe UP / Swipe DOWN**: Once active, swipe up or down to scroll between pages.
*   **Screen Tap**:
    - *On Stats Page (Page 1):* Triggers an immediate manual battery log.
    - *On Graph Page (Page 3):* Cycles the graph duration between **24 Hours**, **7 Days**, and **20 Days**.
*   **Long Press physical Back button**: Opens the **Reset Logs** screen. Tap the screen to confirm reset or press Back to cancel.
*   **Swipe Left-to-Right (or physical Back Button)**: Exits the active state back to the passive widget loop. Swiping up/down on the passive loop will then scroll to other widgets.

*   **Glance View**:

<img width="377" height="502" alt="image" src="https://github.com/user-attachments/assets/eba2e9ba-4c71-4b7b-8fe7-8dd6a9bb6fc4" />


---

## Folder Structure

```
garmin-battery-monitor/
├── manifest.xml                 # Target devices, UUID, type="widget", and Background permissions
├── monkey.jungle                # Project build path configurations
├── README.md                    # Setup and sideloading instructions (this file)
├── resources/
│   ├── drawables/
│   │   ├── drawables.xml        # Declares drawable assets
│   │   └── launcher_icon.png    # 62x62 circular battery icon (required by compiler)
│   └── strings/
│       └── strings.xml          # Declares localizable strings (AppName, etc.)
└── source/
    ├── BatteryMonitorApp.mc     # Main application lifecycle & service registration
    ├── BatteryMonitorDelegate.mc# Handlers for button interactions (UP/DOWN/GPS/MENU/BACK)
    ├── BatteryMonitorGlanceView.mc# Memory-safe widget glance loop display (on-the-fly estimates)
    ├── BatteryMonitorServiceDelegate.mc# Background temporal logger (runs every 30 minutes)
    └── BatteryMonitorView.mc    # Core UI, analytics calculations, graph & scrollbar rendering
```

---

## System Requirements

To build and run this application on your Mac, you need:
1. **Visual Studio Code** installed.
2. **Java Runtime Environment (JRE)** (v11 or later) installed on your Mac. 
   - *Check in Terminal:* `java -version`. 
   - If not found, download and install the standard JRE or JDK from [Adoptium (Temurin)](https://adoptium.net/).
3. **Garmin Connect IQ SDK Manager** and SDK.

---

## Getting Started: VS Code Setup

1. **Open VS Code** and select **File > Open Folder...**.
2. Open the `garmin-battery-monitor` project folder.
3. Open the VS Code Extensions Marketplace (`Cmd + Shift + X`), search for **"Monkey C"** (by Garmin), and install it.
4. Once installed, open the VS Code Command Palette (`Cmd + Shift + P`) and run **"Monkey C: Verify Installation"**.
   - If prompted, download the **Connect IQ SDK Manager** via the link provided.
   - Run the SDK Manager, download the latest **Connect IQ SDK**, and set it as the **Active SDK** in the Manager's "SDKs" tab.
   - Under the "Devices" tab, search for your watch profile (**Instinct 2**, **Instinct 2S**, **Instinct Esports 45mm**, or **Vívoactive 4**) and download it.
5. Restart VS Code so it reads your active SDK configuration.

---

## Running in the Simulator

1. Open `source/BatteryMonitorApp.mc` in VS Code.
2. Press **`F5`** (or go to **Run > Start Debugging**).
3. If prompted to select a device, choose **`instinct2`**, **`instinct2s`**, **`instincte45mm`**, or **`vivoactive4`**.
4. The Connect IQ Simulator will launch and show the watch face. 
5. **Seeding Initial Data**:
   - Scroll up/down to see the widget glance **"Batt Monitor by MPC"**.
   - Press the **GPS (Enter)** key to open the widget.
   - Because the background service fires every 30 minutes, the graph and analytics will initially show "Collecting data..." or "Need 12h of history".
   - Go to the **Statistics page** (Page 1) and press the **GPS (Enter)** key. Press it a few times (waiting a few seconds in between) to manually record data points immediately.
   - Switch to the **History Graph** (Page 2) by pressing **DOWN**. You will see the graph start to populate!
6. **Simulating charging states**:
   - In the Simulator menu, go to **Simulation > Battery** (or **Activity > Battery**) to change the battery level.
   - Check the **Charging** checkbox to simulate plugging the watch in.
   - Slide the **Solar Intensity** slider (above 10) to simulate standing in the sun.
   - Trigger a manual log (GPS key) after changing these settings, and you will see the sub-screen icon change dynamically (Lightning Bolt for AC charging, Sun icon for Solar charging, or battery number for normal discharging).
7. **Simulating background logs**:
   - To simulate the background logger running, go to **Simulation > Background Event** in the simulator menu. This will trigger the background `onTemporalEvent` log manually.

---

## Sideloading onto your physical Garmin watch

To load the widget onto your watch:
1. Move the *.prg file from [**releases**](https://github.com/Pelc314/garmin-battery-monitor/releases) into **apps** folder on your garmin

or build the app yourself:

1. Plug your Garmin watch into your Mac using the USB cable. The watch should mount as a USB drive.
2. In VS Code, open the Command Palette (`Cmd + Shift + P`) and run **"Monkey C: Build for Device"**.
3. Select your watch model (e.g. **`instinct2`**, **`instinct2s`**, **`instincte45mm`**, or **`vivoactive4`**).
4. Select a folder on your Mac (e.g., your Desktop) to output the compiled file.
5. Once the build completes, copy the generated `.prg` file (e.g. `garminbatterymonitor.prg`).
6. Open your Finder, navigate to the mounted Garmin watch drive, and open the folder **`GARMIN/APPS/`**.
7. Paste the `.prg` file into the `GARMIN/APPS/` folder.
8. Unmount/eject the watch from your Mac and unplug it.
9. Press **UP** or **DOWN** from your main watch face, scroll through your widget loop, and you will find your new **Battery Monitor** widget active and logging in the background!
