# Garmin Battery Monitor - Agent Instructions, Constraints and memory

Welcome! This document provides vital context, architecture overview, performance constraints, and coding rules for any AI agent working on the Garmin Battery Monitor app. Treat it as guidelines for the agent and it's memory.

---

## App Context & Architecture

This is a **Garmin Connect IQ Widget/App** that monitors the watch's battery level and tracks charging history (AC gains, solar hours, intensity averages, and discharge estimates).

1. **Glance View (`BatteryMonitorGlanceView.mc`)**:
   * Displays the current battery percentage and the remaining battery life estimate.
   * **RAM Limit**: Connect IQ glance processes are limited to **32KB of RAM**.
2. **Active View (`BatteryMonitorView.mc`)**:
   * Page 1: Current battery level, discharge rate, and remaining days estimate.
   * Page 2: Charging page showing AC gains, solar gains, solar hours, and solar average intensity.
   * Page 3: History Graph showing battery curve over 24h, 7d, or 20d duration.
3. **Background Service (`BatteryMonitorServiceDelegate.mc` / `BatteryLogger.mc`)**:
   * A temporal background event that runs every **30 minutes** to record a new state entry (timestamp, battery level, charging state, solar intensity).
   * Calculates rolling averages and estimates, caching them in persistent `Storage`.

---

## Critical Performance Constraints

Garmin watch hardware has very limited CPU power, slow storage access, and lacks hardware floating-point units (FPUs). Adhere to the following rules to prevent watch freezing and **IQ! (Watchdog Timer)** crashes:

### 1. Avoid Floating-Point Division in Loops
* **Rule**: Never perform floating-point divisions inside loops that iterate over historical entries (which can grow up to 960 elements).
* **Workaround**: Perform calculations in **pure integer math** (e.g., using seconds instead of hours, and tenths of a percent instead of floats). Convert to floats and divide **only once** after the loop completes.

### 2. Fast Startup (Watchdog Protection)
* **Rule**: The initial view must return and render within **1-2 seconds** of app launch. Never call heavy calculation loops or perform persistent storage writes during `initialize()` or `onStart()`.
* **Workaround**: Read pre-calculated simple float values from `Storage` during startup. Bypassing calculations on launch keeps startup times under 5ms.

### 3. Glance Memory Limits (32KB RAM)
* **Rule**: Never load large history arrays or execute logger/analytics loops in the Glance View's `onUpdate()`. Doing so will trigger Out Of Memory (OOM) or Watchdog crashes.
* **Workaround**: The background logger pre-calculates the estimate and writes it to a single float key (`"est_days"`). The glance view should read *only* this float directly from `Storage`.

### 4. Graph Rendering Optimization
* **Rule**: Never recalculate pixel coordinates or date formats for 960 entries on every single `onUpdate()` frame redraw.
* **Workaround**: Implement **lazy caching** of coordinates. Calculate the bounding box, Y-axis labels, and screen coordinates (`x`, `y`) only when the user cycles the graph duration or enters the graph page. Cache these in member variables, and draw directly from cache on subsequent frames.

---

## Database Schema & Self-Healing

The app stores data in persistent `Storage` under four parallel arrays:
* `"timestamps"` (Array of Numbers - UNIX epoch seconds)
* `"batteryLevels"` (Array of Numbers - battery percentage * 10)
* `"chargingStates"` (Array of Numbers - 0 = discharging, 1 = charging)
* `"solarIntensities"` (Array of Numbers - 0 to 100 Lux scale)

### Database Mismatches & Upgrades
* **Rule**: When upgrading the app, new fields (like `solarIntensities`) might be missing from older stored logs, causing array size mismatches and Out of Bounds crashes.
* **Workaround**: Use the **History-Preserving Self-Healing Padding** mechanism. On logger load, check all arrays. Find the maximum array size, and pad the shorter arrays with default values (`0`s) to match the maximum size. **Do not slice/truncate arrays**, as that deletes the user's history. 
Remember that all database schema changes cannot affect already saved data!

---

## Debugging and Simulator Rules

* **Simulator Checks**: Use `System.getDeviceSettings().simulator` to run simulator-only debugging behavior (like seeding dummy data).
* **Production safety**: Provide empty release method stubs annotated with `(:release)` to satisfy the compiler while allowing `(:debug)` code to be stripped completely in release builds. Do not comment/uncomment code block manual switches.
