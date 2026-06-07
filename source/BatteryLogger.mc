import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:glance :background)
module BatteryLogger {

    // Logs the current watch state (battery %, charging state, solar intensity).
    // Restricts writes to at most once per 5 minutes to prevent storage spam.
    function logCurrentState() as Void {
        var now = Time.now().value();
        var stats = System.getSystemStats();
        
        // 1. Collect current metrics
        var battery = stats.battery;
        var isCharging = stats.charging ? 1 : 0; // 1 = AC charging, 0 = discharging
        
        var solar = 0;
        if (stats has :solarIntensity && stats.solarIntensity != null) {
            solar = stats.solarIntensity;
        }

        // 2. Load historical logs from Storage
        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        var solarIntensities = Storage.getValue("solarIntensities") as Array<Number>?;

        // Initialize if empty
        if (timestamps == null) { timestamps = [] as Array<Number>; }
        if (batteryLevels == null) { batteryLevels = [] as Array<Number>; }
        if (chargingStates == null) { chargingStates = [] as Array<Number>; }
        if (solarIntensities == null) { solarIntensities = [] as Array<Number>; }

        // 3. Prevent duplicate logs within the 5-minute interval
        var shouldAppend = true;
        if (timestamps.size() > 0) {
            var lastTime = timestamps[timestamps.size() - 1];
            // If less than 5 minutes (300 seconds) have elapsed, update the last reading in place
            if (now - lastTime < 300) {
                shouldAppend = false;
                timestamps[timestamps.size() - 1] = now;
                batteryLevels[batteryLevels.size() - 1] = (battery * 10.0).toNumber();
                chargingStates[chargingStates.size() - 1] = isCharging;
                solarIntensities[solarIntensities.size() - 1] = solar;
            }
        }

        // 4. Append new entry if outside the debounce window
        if (shouldAppend) {
            timestamps.add(now);
            batteryLevels.add((battery * 10.0).toNumber());
            chargingStates.add(isCharging);
            solarIntensities.add(solar);

            // Maintain rolling 14-day history cap (1008 entries at 20-minute intervals)
            // Capped at 1008 to prevent Out Of Memory (OOM) errors in background RAM (32KB limit on Instinct 2)
            if (timestamps.size() > 1008) {
                timestamps = timestamps.slice(1, null);
                batteryLevels = batteryLevels.slice(1, null);
                chargingStates = chargingStates.slice(1, null);
                solarIntensities = solarIntensities.slice(1, null);
            }
        }

        // 5. Save logs back to persistent storage
        Storage.setValue("timestamps", timestamps);
        Storage.setValue("batteryLevels", batteryLevels);
        Storage.setValue("chargingStates", chargingStates);
        Storage.setValue("solarIntensities", solarIntensities);
    }
}
