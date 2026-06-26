import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:glance :background)
module BatteryLogger {

    // Lightweight background logger to prevent OOM errors (restricted to 32KB RAM)
    function logCurrentStateBackground() as Void {
        var now = Time.now().value();
        var stats = System.getSystemStats();
        
        var battery = stats.battery;
        var chargingStatus = getChargingStatus(stats);
        
        var solar = 0;
        if (stats has :solarIntensity && stats.solarIntensity != null) {
            solar = stats.solarIntensity;
        }

        // Load pending logs from Storage (max 48 entries, very small footprint)
        var pTimestamps = Storage.getValue("p_timestamps") as Array<Number>?;
        var pBatteryLevels = Storage.getValue("p_batteryLevels") as Array<Number>?;
        var pChargingStates = Storage.getValue("p_chargingStates") as Array<Number>?;
        var pSolarIntensities = Storage.getValue("p_solarIntensities") as Array<Number>?;

        if (pTimestamps == null) { pTimestamps = [] as Array<Number>; }
        if (pBatteryLevels == null) { pBatteryLevels = [] as Array<Number>; }
        if (pChargingStates == null) { pChargingStates = [] as Array<Number>; }
        if (pSolarIntensities == null) { pSolarIntensities = [] as Array<Number>; }

        // Align pending arrays if mismatched
        var maxSize = pTimestamps.size();
        if (pBatteryLevels.size() > maxSize) { maxSize = pBatteryLevels.size(); }
        if (pChargingStates.size() > maxSize) { maxSize = pChargingStates.size(); }
        if (pSolarIntensities.size() > maxSize) { maxSize = pSolarIntensities.size(); }

        while (pTimestamps.size() < maxSize) { pTimestamps.add(now); }
        while (pBatteryLevels.size() < maxSize) {
            var lastBat = pBatteryLevels.size() > 0 ? pBatteryLevels[pBatteryLevels.size() - 1] : (battery * 10.0).toNumber();
            pBatteryLevels.add(lastBat);
        }
        while (pChargingStates.size() < maxSize) { pChargingStates.add(0); }
        while (pSolarIntensities.size() < maxSize) { pSolarIntensities.add(0); }

        // If less than 5 minutes passed, update the last entry to capture the latest state
        // without increasing array size.
        var shouldAppend = true;
        if (pTimestamps.size() > 0) {
            var lastTime = pTimestamps[pTimestamps.size() - 1];
            if (now - lastTime < 300) {
                shouldAppend = false;
                pTimestamps[pTimestamps.size() - 1] = now;
                pBatteryLevels[pBatteryLevels.size() - 1] = (battery * 10.0).toNumber();
                pChargingStates[pChargingStates.size() - 1] = chargingStatus;
                pSolarIntensities[pSolarIntensities.size() - 1] = solar;
            }
        }

        if (shouldAppend) {
            pTimestamps.add(now);
            pBatteryLevels.add((battery * 10.0).toNumber());
            pChargingStates.add(chargingStatus);
            pSolarIntensities.add(solar);

            // Cap the pending queue size (48 entries = 24 hours of logs)
            // Keeps memory under 1KB to completely prevent OOM in background process
            if (pTimestamps.size() > 48) {
                pTimestamps = pTimestamps.slice(1, null);
                pBatteryLevels = pBatteryLevels.slice(1, null);
                pChargingStates = pChargingStates.slice(1, null);
                pSolarIntensities = pSolarIntensities.slice(1, null);
            }
        }

        Storage.setValue("p_timestamps", pTimestamps);
        Storage.setValue("p_batteryLevels", pBatteryLevels);
        Storage.setValue("p_chargingStates", pChargingStates);
        Storage.setValue("p_solarIntensities", pSolarIntensities);
    }

    // Merges background pending logs into main history arrays.
    // Must be called from the main application thread (which has a larger memory limit).
    function mergePendingLogs() as Void {
        var pTimestamps = Storage.getValue("p_timestamps") as Array<Number>?;
        if (pTimestamps == null || pTimestamps.size() == 0) {
            return;
        }

        var pBatteryLevels = Storage.getValue("p_batteryLevels") as Array<Number>?;
        var pChargingStates = Storage.getValue("p_chargingStates") as Array<Number>?;
        var pSolarIntensities = Storage.getValue("p_solarIntensities") as Array<Number>?;

        if (pBatteryLevels == null) { pBatteryLevels = [] as Array<Number>; }
        if (pChargingStates == null) { pChargingStates = [] as Array<Number>; }
        if (pSolarIntensities == null) { pSolarIntensities = [] as Array<Number>; }

        var now = Time.now().value();

        // 1. Determine the maximum size of the main arrays first to align them,
        // loading them one-by-one to avoid high memory utilization.
        var tSize = 0;
        var bSize = 0;
        var cSize = 0;
        var sSize = 0;

        var temp = Storage.getValue("timestamps") as Array<Number>?;
        if (temp != null) { tSize = temp.size(); temp = null; }
        
        temp = Storage.getValue("batteryLevels") as Array<Number>?;
        if (temp != null) { bSize = temp.size(); temp = null; }

        temp = Storage.getValue("chargingStates") as Array<Number>?;
        if (temp != null) { cSize = temp.size(); temp = null; }

        temp = Storage.getValue("solarIntensities") as Array<Number>?;
        if (temp != null) { sSize = temp.size(); temp = null; }

        var maxMainSize = tSize;
        if (bSize > maxMainSize) { maxMainSize = bSize; }
        if (cSize > maxMainSize) { maxMainSize = cSize; }
        if (sSize > maxMainSize) { maxMainSize = sSize; }

        // 2. Load timestamps first to determine merge actions
        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        if (timestamps == null) { timestamps = [] as Array<Number>; }
        while (timestamps.size() < maxMainSize) { timestamps.add(now); }

        // Simulate the merge process to record actions (overwrite last or append)
        var pSize = pTimestamps.size();
        var actions = [] as Array<Number>;
        var currentTSize = timestamps.size();
        var lastTime = currentTSize > 0 ? timestamps[currentTSize - 1] : null;

        for (var i = 0; i < pSize; i++) {
            var pTime = pTimestamps[i];
            if (currentTSize > 0 && lastTime != null && pTime - lastTime < 300) {
                actions.add(-1); // -1 = overwrite last element
                lastTime = pTime;
            } else {
                actions.add(0); // 0 = append new element
                currentTSize++;
                lastTime = pTime;
            }
        }

        // Apply actions to timestamps, slice to 960 if needed, save, and free from RAM
        for (var i = 0; i < pSize; i++) {
            var action = actions[i];
            if (action == -1) {
                if (timestamps.size() > 0) {
                    timestamps[timestamps.size() - 1] = pTimestamps[i];
                }
            } else {
                timestamps.add(pTimestamps[i]);
            }
        }
        if (timestamps.size() > 960) {
            timestamps = timestamps.slice(timestamps.size() - 960, null);
        }
        Storage.setValue("timestamps", timestamps);
        timestamps = null;

        // 3. Process batteryLevels one-by-one
        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        if (batteryLevels == null) { batteryLevels = [] as Array<Number>; }
        while (batteryLevels.size() < maxMainSize) {
            var lastBat = batteryLevels.size() > 0 ? batteryLevels[batteryLevels.size() - 1] : 1000;
            batteryLevels.add(lastBat);
        }
        for (var i = 0; i < pSize; i++) {
            var action = actions[i];
            if (action == -1) {
                if (batteryLevels.size() > 0) {
                    batteryLevels[batteryLevels.size() - 1] = pBatteryLevels[i];
                }
            } else {
                batteryLevels.add(pBatteryLevels[i]);
            }
        }
        if (batteryLevels.size() > 960) {
            batteryLevels = batteryLevels.slice(batteryLevels.size() - 960, null);
        }
        Storage.setValue("batteryLevels", batteryLevels);
        batteryLevels = null;

        // 4. Process chargingStates one-by-one
        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        if (chargingStates == null) { chargingStates = [] as Array<Number>; }
        while (chargingStates.size() < maxMainSize) { chargingStates.add(0); }
        for (var i = 0; i < pSize; i++) {
            var action = actions[i];
            if (action == -1) {
                if (chargingStates.size() > 0) {
                    chargingStates[chargingStates.size() - 1] = pChargingStates[i];
                }
            } else {
                chargingStates.add(pChargingStates[i]);
            }
        }
        if (chargingStates.size() > 960) {
            chargingStates = chargingStates.slice(chargingStates.size() - 960, null);
        }
        Storage.setValue("chargingStates", chargingStates);
        chargingStates = null;

        // 5. Process solarIntensities one-by-one
        var solarIntensities = Storage.getValue("solarIntensities") as Array<Number>?;
        if (solarIntensities == null) { solarIntensities = [] as Array<Number>; }
        while (solarIntensities.size() < maxMainSize) { solarIntensities.add(0); }
        for (var i = 0; i < pSize; i++) {
            var action = actions[i];
            if (action == -1) {
                if (solarIntensities.size() > 0) {
                    solarIntensities[solarIntensities.size() - 1] = pSolarIntensities[i];
                }
            } else {
                solarIntensities.add(pSolarIntensities[i]);
            }
        }
        if (solarIntensities.size() > 960) {
            solarIntensities = solarIntensities.slice(solarIntensities.size() - 960, null);
        }
        Storage.setValue("solarIntensities", solarIntensities);
        solarIntensities = null;

        // 6. Delete pending keys
        Storage.deleteValue("p_timestamps");
        Storage.deleteValue("p_batteryLevels");
        Storage.deleteValue("p_chargingStates");
        Storage.deleteValue("p_solarIntensities");

        // 7. Recalculate statistics (loads arrays directly with small footprint)
        calculateAndSaveAnalytics();
    }

    // 0 = discharging (not plugged in, no solar)
    // 1 = charging with AC/USB (plugged in, stats.charging is true)
    // 2 = solar active (not plugged in, stats.charging is false, but stats.solarIntensity > 0)
    function getChargingStatus(stats as $.Toybox.System.Stats) as Number {
        if (stats.charging) {
            return 1;
        } 
        if (stats has :solarIntensity && stats.solarIntensity != null && stats.solarIntensity > 0) {
            return 2;
        }
        return 0;
    }

    // Logs the current watch state (battery %, charging state, solar intensity) manually
    // from the Active View (main app).
    function logCurrentState() as Void {
        // 1. First merge any pending logs recorded by the background service
        mergePendingLogs();

        var now = Time.now().value();
        var stats = System.getSystemStats();
        var battery = stats.battery;
        var chargingStatus = getChargingStatus(stats);
        var solar = 0;
        if (stats has :solarIntensity && stats.solarIntensity != null) {
            solar = stats.solarIntensity;
        }

        // 2. Load max size first to align arrays if mismatched, loading one-by-one to save memory
        var tSize = 0;
        var bSize = 0;
        var cSize = 0;
        var sSize = 0;

        var temp = Storage.getValue("timestamps") as Array<Number>?;
        if (temp != null) { tSize = temp.size(); temp = null; }
        
        temp = Storage.getValue("batteryLevels") as Array<Number>?;
        if (temp != null) { bSize = temp.size(); temp = null; }

        temp = Storage.getValue("chargingStates") as Array<Number>?;
        if (temp != null) { cSize = temp.size(); temp = null; }

        temp = Storage.getValue("solarIntensities") as Array<Number>?;
        if (temp != null) { sSize = temp.size(); temp = null; }

        var maxSize = tSize;
        if (bSize > maxSize) { maxSize = bSize; }
        if (cSize > maxSize) { maxSize = cSize; }
        if (sSize > maxSize) { maxSize = sSize; }

        // 3. Process timestamps first to determine shouldAppend
        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        if (timestamps == null) { timestamps = [] as Array<Number>; }
        while (timestamps.size() < maxSize) { timestamps.add(now); }

        var shouldAppend = true; 
        if (timestamps.size() > 0) {
            var lastTime = timestamps[timestamps.size() - 1];
            if (now - lastTime < 300) {
                shouldAppend = false;
                timestamps[timestamps.size() - 1] = now;
            }
        }
        if (shouldAppend) {
            timestamps.add(now);
            if (timestamps.size() > 960) {
                timestamps = timestamps.slice(timestamps.size() - 960, null);
            }
        }
        Storage.setValue("timestamps", timestamps);
        timestamps = null;

        // 4. Process batteryLevels one-by-one
        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        if (batteryLevels == null) { batteryLevels = [] as Array<Number>; }
        while (batteryLevels.size() < maxSize) {
            var lastBat = batteryLevels.size() > 0 ? batteryLevels[batteryLevels.size() - 1] : (battery * 10.0).toNumber();
            batteryLevels.add(lastBat);
        }
        if (shouldAppend) {
            batteryLevels.add((battery * 10.0).toNumber());
            if (batteryLevels.size() > 960) {
                batteryLevels = batteryLevels.slice(batteryLevels.size() - 960, null);
            }
        } else {
            if (batteryLevels.size() > 0) {
                batteryLevels[batteryLevels.size() - 1] = (battery * 10.0).toNumber();
            }
        }
        Storage.setValue("batteryLevels", batteryLevels);
        batteryLevels = null;

        // 5. Process chargingStates one-by-one
        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        if (chargingStates == null) { chargingStates = [] as Array<Number>; }
        while (chargingStates.size() < maxSize) { chargingStates.add(0); }
        if (shouldAppend) {
            chargingStates.add(chargingStatus);
            if (chargingStates.size() > 960) {
                chargingStates = chargingStates.slice(chargingStates.size() - 960, null);
            }
        } else {
            if (chargingStates.size() > 0) {
                chargingStates[chargingStates.size() - 1] = chargingStatus;
            }
        }
        Storage.setValue("chargingStates", chargingStates);
        chargingStates = null;

        // 6. Process solarIntensities one-by-one
        var solarIntensities = Storage.getValue("solarIntensities") as Array<Number>?;
        if (solarIntensities == null) { solarIntensities = [] as Array<Number>; }
        while (solarIntensities.size() < maxSize) { solarIntensities.add(0); }
        if (shouldAppend) {
            solarIntensities.add(solar);
            if (solarIntensities.size() > 960) {
                solarIntensities = solarIntensities.slice(solarIntensities.size() - 960, null);
            }
        } else {
            if (solarIntensities.size() > 0) {
                solarIntensities[solarIntensities.size() - 1] = solar;
            }
        }
        Storage.setValue("solarIntensities", solarIntensities);
        solarIntensities = null;

        // 7. Recalculate statistics
        calculateAndSaveAnalytics();
    }

    // Recalculates analytics based on arrays loaded from Storage,
    // slicing them to a maximum of 48 entries (last 24 hours) to minimize memory usage.
    function calculateAndSaveAnalytics() as Void {
        var avgDrainRate = 0.0;
        var acGainedToday = 0.0;
        var solarGainedToday = 0.0;
        var solarIntensityAvgToday = 0.0;
        var solarHoursToday = 0.0;
        var estDays = null;

        var tSize = 0;
        var bSize = 0;
        var cSize = 0;
        var sSize = 0;

        var temp = Storage.getValue("timestamps") as Array<Number>?;
        if (temp != null) { tSize = temp.size(); temp = null; }
        
        temp = Storage.getValue("batteryLevels") as Array<Number>?;
        if (temp != null) { bSize = temp.size(); temp = null; }

        temp = Storage.getValue("chargingStates") as Array<Number>?;
        if (temp != null) { cSize = temp.size(); temp = null; }

        temp = Storage.getValue("solarIntensities") as Array<Number>?;
        if (temp != null) { sSize = temp.size(); temp = null; }

        var maxSize = tSize;
        if (bSize > maxSize) { maxSize = bSize; }
        if (cSize > maxSize) { maxSize = cSize; }
        if (sSize > maxSize) { maxSize = sSize; }

        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        if (timestamps == null) { timestamps = [] as Array<Number>; }
        while (timestamps.size() < maxSize) { timestamps.add(Time.now().value()); }

        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        if (batteryLevels == null) { batteryLevels = [] as Array<Number>; }
        while (batteryLevels.size() < maxSize) {
            var lastBat = batteryLevels.size() > 0 ? batteryLevels[batteryLevels.size() - 1] : 1000;
            batteryLevels.add(lastBat);
        }

        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        if (chargingStates == null) { chargingStates = [] as Array<Number>; }
        while (chargingStates.size() < maxSize) { chargingStates.add(0); }

        var solarIntensities = Storage.getValue("solarIntensities") as Array<Number>?;
        if (solarIntensities == null) { solarIntensities = [] as Array<Number>; }
        while (solarIntensities.size() < maxSize) { solarIntensities.add(0); }

        if (maxSize > 48) {
            timestamps = timestamps.slice(maxSize - 48, null);
            batteryLevels = batteryLevels.slice(maxSize - 48, null);
            chargingStates = chargingStates.slice(maxSize - 48, null);
            solarIntensities = solarIntensities.slice(maxSize - 48, null);
        }

        var size = timestamps.size();
        if (size >= 2) {
            // Variables to track semi-current rate over different time windows
            var totalSeconds2h = 0;
            var totalChangeTenths2h = 0;
            
            var totalSeconds24h = 0;
            var totalChangeTenths24h = 0;
            
            var totalSecondsAll = 0;
            var totalChangeTenthsAll = 0;

            var nowVal = Time.now().value();
            
            var acGainedTodayTenths = 0;
            var solarGainedTodayTenths = 0;
            var solarHoursTodaySeconds = 0;
            var solarCountToday = 0;
            var solarSumToday = 0;
            
            for (var i = 1; i < size; i++) {
                var dtSeconds = timestamps[i] - timestamps[i-1];
                var batDiffTenths = batteryLevels[i-1] - batteryLevels[i];
                
                // Track signed battery rate of change across windows (including charging/discharging)
                if (dtSeconds > 0 && dtSeconds < 172800) { // Capped at 48 hours to avoid massive outliers
                    var age = nowVal - timestamps[i];
                    
                    // 2-hour window (preferred for semi-current rate)
                    if (age <= 7200) {
                        totalChangeTenths2h += batDiffTenths;
                        totalSeconds2h += dtSeconds;
                    }
                    
                    // 24-hour window (first fallback)
                    if (age <= 86400) {
                        totalChangeTenths24h += batDiffTenths;
                        totalSeconds24h += dtSeconds;
                    }
                    
                    // All history window (final fallback)
                    totalChangeTenthsAll += batDiffTenths;
                    totalSecondsAll += dtSeconds;
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
                            if (solarIntensities[i] == 0 || gainRatePerHourTenths > 70.0) { // 7% per hour
                                acGainedTodayTenths += gainTenths;
                            } else if (solarIntensities[i] > 0 || chargingStates[i] == 2) {
                                solarGainedTodayTenths += gainTenths;
                            } else {
                                acGainedTodayTenths = 999; //error indication
                                solarGainedTodayTenths = 999;
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
            
            if (totalSeconds2h > 0) {
                avgDrainRate = (totalChangeTenths2h.toFloat() * 360.0) / totalSeconds2h.toFloat();
            } else if (totalSeconds24h > 0) {
                avgDrainRate = (totalChangeTenths24h.toFloat() * 360.0) / totalSeconds24h.toFloat();
            } else if (totalSecondsAll > 0) {
                avgDrainRate = (totalChangeTenthsAll.toFloat() * 360.0) / totalSecondsAll.toFloat();
            }
            
            var stats = System.getSystemStats();
            var battery = stats.battery;
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
                isCharging = 2; // Slow Solar charge (2 = solar active)
                bat += 1.5;
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

        solarIntensities.add(25);
        timestamps.add(nowVal);
        batteryLevels.add(500); // 50.0% battery
        chargingStates.add(2); // 2 = solar active (intensity 25)

        Storage.setValue("timestamps", timestamps);
        Storage.setValue("batteryLevels", batteryLevels);
        Storage.setValue("chargingStates", chargingStates);
        Storage.setValue("solarIntensities", solarIntensities);
    }

    // Dummy implementation for release mode to prevent compiler undefined symbol errors
    (:release)
    function seedDebugData() as Void {
    }
}
