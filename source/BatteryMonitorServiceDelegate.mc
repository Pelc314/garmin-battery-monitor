import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
class BatteryMonitorServiceDelegate extends System.ServiceDelegate {

    // Maximum number of entries to keep in history (30 days * 24 hours = 720 hours)
    private const MAX_HISTORY = 720;

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Called when the temporal background event triggers
    function onTemporalEvent() as Void {
        var now = Time.now().value();
        var stats = System.getSystemStats();
        
        // 1. Collect metrics
        var battery = stats.battery; // Float
        var isCharging = stats.charging ? 1 : 0; // 1 = connected to AC/USB, 0 = discharging
        
        var solar = 0;
        if (stats has :solarIntensity && stats.solarIntensity != null) {
            solar = stats.solarIntensity;
        }

        // 2. Load historical logs
        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        var solarIntensities = Storage.getValue("solarIntensities") as Array<Number>?;

        // Initialize if empty
        if (timestamps == null) { timestamps = [] as Array<Number>; }
        if (batteryLevels == null) { batteryLevels = [] as Array<Number>; }
        if (chargingStates == null) { chargingStates = [] as Array<Number>; }
        if (solarIntensities == null) { solarIntensities = [] as Array<Number>; }

        // 3. Prevent duplicate logs for the same hour
        // (sometimes temporal events can fire slightly early or twice due to syncs)
        var shouldAppend = true;
        if (timestamps.size() > 0) {
            var lastTime = timestamps[timestamps.size() - 1];
            // If less than 45 minutes have elapsed, just update the last reading
            // rather than creating a new hourly record
            if (now - lastTime < 2700) {
                shouldAppend = false;
                timestamps[timestamps.size() - 1] = now;
                batteryLevels[batteryLevels.size() - 1] = (battery * 10.0).toNumber();
                chargingStates[chargingStates.size() - 1] = isCharging;
                solarIntensities[solarIntensities.size() - 1] = solar;
            }
        }

        if (shouldAppend) {
            // Append new entry
            timestamps.add(now);
            batteryLevels.add((battery * 10.0).toNumber()); // Store percentage * 10 to keep as Integer
            chargingStates.add(isCharging);
            solarIntensities.add(solar);

            // Bounded array checks to prevent memory leakage
            if (timestamps.size() > MAX_HISTORY) {
                timestamps = timestamps.slice(1, null);
                batteryLevels = batteryLevels.slice(1, null);
                chargingStates = chargingStates.slice(1, null);
                solarIntensities = solarIntensities.slice(1, null);
            }
        }

        // 4. Save updated logs back to persistent storage
        Storage.setValue("timestamps", timestamps);
        Storage.setValue("batteryLevels", batteryLevels);
        Storage.setValue("chargingStates", chargingStates);
        Storage.setValue("solarIntensities", solarIntensities);

        // Notify app shell and exit
        Background.exit(true);
    }
}
