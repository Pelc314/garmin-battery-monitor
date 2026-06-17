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

        // Ensure all arrays have the exact same size by padding shorter ones (prevents Out of Bounds crashes while preserving history)
        var maxSize = timestamps.size();
        if (batteryLevels.size() > maxSize) { maxSize = batteryLevels.size(); }
        if (chargingStates.size() > maxSize) { maxSize = chargingStates.size(); }
        if (solarIntensities.size() > maxSize) { maxSize = solarIntensities.size(); }

        while (timestamps.size() < maxSize) {
            timestamps.add(now);
        }
        while (batteryLevels.size() < maxSize) {
            var lastBat = batteryLevels.size() > 0 ? batteryLevels[batteryLevels.size() - 1] : (battery * 10.0).toNumber();
            batteryLevels.add(lastBat);
        }
        while (chargingStates.size() < maxSize) {
            chargingStates.add(0);
        }
        while (solarIntensities.size() < maxSize) {
            solarIntensities.add(0);
        }

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

            // Maintain rolling 20-day history cap (960 entries at 30-minute intervals)
            // Capped at 960 to prevent Out Of Memory (OOM) errors in background RAM (32KB limit on Instinct 2)
            if (timestamps.size() > 960) {
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

        // 6. Update cached analytics in Storage
        var avgDrainRate = 0.0;
        var acGainedToday = 0.0;
        var solarGainedToday = 0.0;
        var solarIntensityAvgToday = 0.0;
        var solarHoursToday = 0.0;
        var estDays = null;

        var size = timestamps.size();
        if (size >= 2) {
            var totalSeconds = 0;
            var totalDropTenths = 0;
            var nowVal = Time.now().value();
            
            var acGainedTodayTenths = 0;
            var solarGainedTodayTenths = 0;
            var solarHoursTodaySeconds = 0;
            var solarCountToday = 0;
            var solarSumToday = 0;
            
            for (var i = 1; i < size; i++) {
                var dtSeconds = timestamps[i] - timestamps[i-1];
                var batDiffTenths = batteryLevels[i-1] - batteryLevels[i];
                
                // Average drain rate during non-charging periods
                if (chargingStates[i] == 0 && chargingStates[i-1] == 0 && dtSeconds > 0 && dtSeconds < 172800) { // 48 hours = 172800 seconds
                    if (batDiffTenths >= 0) {
                        totalDropTenths += batDiffTenths;
                        totalSeconds += dtSeconds;
                    }
                }
                
                // Daily accumulator (last 24 hours)
                if (nowVal - timestamps[i] <= 86400) {
                    var gainTenths = -batDiffTenths; // Positive if battery increased
                    if (gainTenths > 0) {
                        if (chargingStates[i] == 1 || chargingStates[i-1] == 1) {
                            acGainedTodayTenths += gainTenths;
                        } else {
                            // Float conversion only when calculating the charge rate of active points
                            var gainRatePerHourTenths = dtSeconds > 0 ? (gainTenths * 3600.0 / dtSeconds.toFloat()) : 0.0;
                            if (solarIntensities[i] == 0 || gainRatePerHourTenths > 25.0) { // 2.5% per hour = 25 tenths
                                acGainedTodayTenths += gainTenths;
                            } else if (solarIntensities[i] > 0) {
                                solarGainedTodayTenths += gainTenths;
                            }
                        }
                    }
                    
                    if (solarIntensities[i] > 0) {
                        solarCountToday++;
                        solarSumToday += solarIntensities[i];
                        solarHoursTodaySeconds += dtSeconds;
                    }
                }
            }
            
            if (totalSeconds > 0) {
                // avgDrainRate = (totalDropTenths / 10.0) / (totalSeconds / 3600.0) = (totalDropTenths * 360) / totalSeconds
                avgDrainRate = (totalDropTenths.toFloat() * 360.0) / totalSeconds.toFloat();
            }
            
            if (avgDrainRate > 0.001) {
                var estHours = battery / avgDrainRate;
                estDays = estHours / 24.0;
            }
            
            acGainedToday = acGainedTodayTenths.toFloat() / 10.0;
            solarGainedToday = solarGainedTodayTenths.toFloat() / 10.0;
            solarHoursToday = solarHoursTodaySeconds.toFloat() / 3600.0;
            
            if (solarCountToday > 0) {
                solarIntensityAvgToday = solarSumToday.toFloat() / solarCountToday.toFloat();
            }
        }

        Storage.setValue("avg_drain_rate", avgDrainRate);
        Storage.setValue("ac_gained_today", acGainedToday);
        Storage.setValue("solar_gained_today", solarGainedToday);
        Storage.setValue("solar_intensity_avg_today", solarIntensityAvgToday);
        Storage.setValue("solar_hours_today", solarHoursToday);
        Storage.setValue("est_days", estDays);
    }

    // Seeds 10 days of dummy history log data for emulator testing
    (:debug)
    function seedDebugData() as Void {
        var nowVal = Time.now().value();
        var timestamps = [] as Array<Number>;
        var batteryLevels = [] as Array<Number>;
        var chargingStates = [] as Array<Number>;
        var solarIntensities = [] as Array<Number>;

        var size = 680; // 10 days at 30-minute intervals
        var bat = 100.0;
        
        for (var i = size; i >= 0; i--) {
            var t = nowVal - (i * 1800); // 30 minutes ago
            timestamps.add(t);
            
            var isCharging = 0;
            var solar = 0;
            
            // Charge for 2 hours every 3 days (every 144 intervals)
            var idx = size - i;
            var dayIndex = idx / 48;
            var intervalInDay = idx % 48;
            
            if (dayIndex % 3 == 0 && intervalInDay >= 20 && intervalInDay <= 24) {
                isCharging = 1;
                bat += 8.0; // Rapid AC charge
                if (bat > 100.0) { bat = 100.0; }
                solar = 0;
            } else if (dayIndex % 3 == 1 && intervalInDay >= 24 && intervalInDay <= 28) {
                isCharging = 1;
                bat += 1.5; // Slow Solar charge
                if (bat > 100.0) { bat = 100.0; }
                solar = 50; // Sunlight
            } else {
                bat -= 0.15; // Slow discharge
                if (bat < 5.0) { bat = 5.0; }
            }
            
            batteryLevels.add((bat * 10.0).toNumber());
            chargingStates.add(isCharging);
            solarIntensities.add(solar);
        }

        Storage.setValue("timestamps", timestamps);
        Storage.setValue("batteryLevels", batteryLevels);
        Storage.setValue("chargingStates", chargingStates);
        Storage.setValue("solarIntensities", solarIntensities);
        
        // Run logCurrentState to calculate and save the estimate
        logCurrentState();
    }

    // Dummy implementation for release mode to prevent compiler undefined symbol errors
    (:release)
    function seedDebugData() as Void {
    }
}
