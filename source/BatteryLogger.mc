import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:glance :background)
module BatteryLogger {

    // Checks if the database needs migration from old parallel format to unified format
    function needsMigration() as Boolean {
        var hasNewLogs = Storage.getValue("historyLogs") != null;
        if (hasNewLogs) {
            return false;
        }
        var temp = Storage.getValue("timestamps") as Array<Number>?;
        if (temp != null && temp.size() > 0) {
            return true;
        }
        return false;
    }

    // Gets the maximum size of the old database arrays to calculate migration progress
    function getMigrationMaxSize() as Number {
        var tSize = 0;
        var temp = Storage.getValue("timestamps") as Array<Number>?;
        if (temp != null) { tSize = temp.size(); temp = null; }
        return tSize;
    }

    // Performs one step of the migration batch. Returns next start index, or -1 when complete.
    function migrateOneBatch(start as Number, batchSize as Number) as Number {
        var hasNewLogs = Storage.getValue("historyLogs") != null;
        if (hasNewLogs) {
            return -1;
        }

        var tSize = 0;
        var temp = Storage.getValue("timestamps") as Array<Number>?;
        if (temp != null) { tSize = temp.size(); temp = null; }
        if (tSize == 0) { return -1; }

        var bSize = 0;
        temp = Storage.getValue("batteryLevels") as Array<Number>?;
        if (temp != null) { bSize = temp.size(); temp = null; }

        var cSize = 0;
        temp = Storage.getValue("chargingStates") as Array<Number>?;
        if (temp != null) { cSize = temp.size(); temp = null; }

        var sSize = 0;
        temp = Storage.getValue("solarIntensities") as Array<Number>?;
        if (temp != null) { sSize = temp.size(); temp = null; }

        var maxSize = tSize;
        if (bSize > maxSize) { maxSize = bSize; }
        if (cSize > maxSize) { maxSize = cSize; }
        if (sSize > maxSize) { maxSize = sSize; }

        var end = start + batchSize;
        if (end > maxSize) { end = maxSize; }

        // Slice old arrays one-by-one to keep memory footprint minimal
        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        var tSlice = (timestamps != null) ? timestamps.slice(start, end) : [] as Array<Number>;
        timestamps = null;

        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        var bSlice = (batteryLevels != null) ? batteryLevels.slice(start, end) : [] as Array<Number>;
        batteryLevels = null;

        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        var cSlice = (chargingStates != null) ? chargingStates.slice(start, end) : [] as Array<Number>;
        chargingStates = null;

        var solarIntensities = Storage.getValue("solarIntensities") as Array<Number>?;
        var sSlice = (solarIntensities != null) ? solarIntensities.slice(start, end) : [] as Array<Number>;
        solarIntensities = null;

        var sliceSize = tSlice.size();
        while (bSlice.size() < sliceSize) { bSlice.add(1000); }
        while (cSlice.size() < sliceSize) { cSlice.add(0); }
        while (sSlice.size() < sliceSize) { sSlice.add(0); }

        // Load and append to the growing historyLogs array in Storage
        var historyLogs = Storage.getValue("historyLogs") as Array<Number>?;
        if (historyLogs == null) { historyLogs = [] as Array<Number>; }

        for (var i = 0; i < sliceSize; i++) {
            historyLogs.add(tSlice[i]);
            historyLogs.add(bSlice[i]);
            historyLogs.add(cSlice[i]);
            historyLogs.add(sSlice[i]);
        }

        Storage.setValue("historyLogs", historyLogs);
        historyLogs = null;
        tSlice = null;
        bSlice = null;
        cSlice = null;
        sSlice = null;

        if (end >= maxSize) {
            // Finalize pending logs migration
            migratePendingLogsOnce();

            // Transactional Guard: verify and safely clean up old keys
            var verifiedLogs = Storage.getValue("historyLogs") as Array<Number>?;
            if (verifiedLogs != null && verifiedLogs.size() == maxSize * 4) {
                verifiedLogs = null;
                Storage.deleteValue("timestamps");
                Storage.deleteValue("batteryLevels");
                Storage.deleteValue("chargingStates");
                Storage.deleteValue("solarIntensities");
            }
            return -1;
        }

        return end;
    }

    // Helper to migrate pending logs in a single fast, OOM-proof step at the end of migration
    function migratePendingLogsOnce() as Void {
        var pHasNewLogs = Storage.getValue("pendingLogs") != null;
        if (pHasNewLogs) {
            return;
        }

        var ptSize = 0;
        var temp = Storage.getValue("p_timestamps") as Array<Number>?;
        if (temp != null) { ptSize = temp.size(); temp = null; }
        if (ptSize == 0) { return; }

        var pbSize = 0;
        temp = Storage.getValue("p_batteryLevels") as Array<Number>?;
        if (temp != null) { pbSize = temp.size(); temp = null; }

        var pcSize = 0;
        temp = Storage.getValue("p_chargingStates") as Array<Number>?;
        if (temp != null) { pcSize = temp.size(); temp = null; }

        var psSize = 0;
        temp = Storage.getValue("p_solarIntensities") as Array<Number>?;
        if (temp != null) { psSize = temp.size(); temp = null; }

        var pMaxSize = ptSize;
        if (pbSize > pMaxSize) { pMaxSize = pbSize; }
        if (pcSize > pMaxSize) { pMaxSize = pcSize; }
        if (psSize > pMaxSize) { pMaxSize = psSize; }

        var pTimestamps = Storage.getValue("p_timestamps") as Array<Number>?;
        if (pTimestamps == null) { pTimestamps = [] as Array<Number>; }
        var now = Time.now().value();
        while (pTimestamps.size() < pMaxSize) { pTimestamps.add(now); }

        var pBatteryLevels = Storage.getValue("p_batteryLevels") as Array<Number>?;
        if (pBatteryLevels == null) { pBatteryLevels = [] as Array<Number>; }
        while (pBatteryLevels.size() < pMaxSize) {
            var lastBat = pBatteryLevels.size() > 0 ? pBatteryLevels[pBatteryLevels.size() - 1] : 1000;
            pBatteryLevels.add(lastBat);
        }

        var pChargingStates = Storage.getValue("p_chargingStates") as Array<Number>?;
        if (pChargingStates == null) { pChargingStates = [] as Array<Number>; }
        while (pChargingStates.size() < pMaxSize) {
            pChargingStates.add(0);
        }

        var pSolarIntensities = Storage.getValue("p_solarIntensities") as Array<Number>?;
        if (pSolarIntensities == null) { pSolarIntensities = [] as Array<Number>; }
        while (pSolarIntensities.size() < pMaxSize) {
            pSolarIntensities.add(0);
        }

        var pendingLogs = [] as Array<Number>;
        for (var i = 0; i < pMaxSize; i++) {
            pendingLogs.add(pTimestamps[i]);
            pendingLogs.add(pBatteryLevels[i]);
            pendingLogs.add(pChargingStates[i]);
            pendingLogs.add(pSolarIntensities[i]);
        }
        pTimestamps = null;
        pBatteryLevels = null;
        pChargingStates = null;
        pSolarIntensities = null;

        Storage.setValue("pendingLogs", pendingLogs);
        pendingLogs = null;

        var verifiedPending = Storage.getValue("pendingLogs") as Array<Number>?;
        if (verifiedPending != null && verifiedPending.size() == pMaxSize * 4) {
            verifiedPending = null;
            Storage.deleteValue("p_timestamps");
            Storage.deleteValue("p_batteryLevels");
            Storage.deleteValue("p_chargingStates");
            Storage.deleteValue("p_solarIntensities");
        }
    }

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
        var pendingLogs = Storage.getValue("pendingLogs") as Array<Number>?;
        if (pendingLogs == null) {
            pendingLogs = [] as Array<Number>;
        }

        // Self-healing size alignment to prevent corruption
        var size = pendingLogs.size();
        while (size % 4 != 0) {
            pendingLogs.add(0);
            size++;
        }

        // If less than 5 minutes passed, update the last entry to capture the latest state
        var shouldAppend = true;
        if (size >= 4) {
            var lastTime = pendingLogs[size - 4];
            if (now - lastTime < 300) {
                shouldAppend = false;
                pendingLogs[size - 4] = now;
                pendingLogs[size - 3] = (battery * 10.0).toNumber();
                pendingLogs[size - 2] = chargingStatus;
                pendingLogs[size - 1] = solar;
            }
        }

        if (shouldAppend) {
            pendingLogs.add(now);
            pendingLogs.add((battery * 10.0).toNumber());
            pendingLogs.add(chargingStatus);
            pendingLogs.add(solar);

            // Cap the pending queue size to 48 entries (192 elements)
            if (pendingLogs.size() > 192) {
                pendingLogs = pendingLogs.slice(4, null);
            }
        }

        Storage.setValue("pendingLogs", pendingLogs);
    }

    // Merges background pending logs into main history arrays.
    // Must be called from the main application thread (which has a larger memory limit).
    // Merges background pending logs into main history arrays.
    // Must be called from the main application thread (which has a larger memory limit).
    function mergePendingLogs() as Void {

        var pendingLogs = Storage.getValue("pendingLogs") as Array<Number>?;
        if (pendingLogs == null || pendingLogs.size() == 0) {
            return;
        }

        var historyLogs = Storage.getValue("historyLogs") as Array<Number>?;
        if (historyLogs == null) {
            historyLogs = [] as Array<Number>;
        }

        // Align size of historyLogs to be a multiple of 4
        var hSize = historyLogs.size();
        while (hSize % 4 != 0) {
            historyLogs.add(0);
            hSize++;
        }

        var pSize = pendingLogs.size();
        var numPending = pSize / 4;

        for (var i = 0; i < numPending; i++) {
            var pIdx = i * 4;
            var pTime = pendingLogs[pIdx];
            var pBat = pendingLogs[pIdx + 1];
            var pChrg = pendingLogs[pIdx + 2];
            var pSolar = pendingLogs[pIdx + 3];

            var size = historyLogs.size();
            var shouldAppend = true;

            if (size >= 4) {
                var lastTime = historyLogs[size - 4];
                if (pTime - lastTime < 300) {
                    shouldAppend = false;
                    historyLogs[size - 4] = pTime;
                    historyLogs[size - 3] = pBat;
                    historyLogs[size - 2] = pChrg;
                    historyLogs[size - 1] = pSolar;
                }
            }

            if (shouldAppend) {
                historyLogs.add(pTime);
                historyLogs.add(pBat);
                historyLogs.add(pChrg);
                historyLogs.add(pSolar);
            }
        }

        // Slice historyLogs to keep last 960 entries (3840 elements)
        if (historyLogs.size() > 3840) {
            historyLogs = historyLogs.slice(historyLogs.size() - 3840, null);
        }

        Storage.setValue("historyLogs", historyLogs);
        Storage.deleteValue("pendingLogs");

        // Recalculate statistics
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

        var historyLogs = Storage.getValue("historyLogs") as Array<Number>?;
        if (historyLogs == null) {
            historyLogs = [] as Array<Number>;
        }

        // Align size of historyLogs to be a multiple of 4
        var hSize = historyLogs.size();
        while (hSize % 4 != 0) {
            historyLogs.add(0);
            hSize++;
        }

        var shouldAppend = true;
        if (hSize >= 4) {
            var lastTime = historyLogs[hSize - 4];
            if (now - lastTime < 300) {
                shouldAppend = false;
                historyLogs[hSize - 4] = now;
                historyLogs[hSize - 3] = (battery * 10.0).toNumber();
                historyLogs[hSize - 2] = chargingStatus;
                historyLogs[hSize - 1] = solar;
            }
        }

        if (shouldAppend) {
            historyLogs.add(now);
            historyLogs.add((battery * 10.0).toNumber());
            historyLogs.add(chargingStatus);
            historyLogs.add(solar);

            // Slice to 3840 elements (960 entries)
            if (historyLogs.size() > 3840) {
                historyLogs = historyLogs.slice(historyLogs.size() - 3840, null);
            }
        }

        Storage.setValue("historyLogs", historyLogs);
        historyLogs = null;

        // Recalculate statistics
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

        var historyLogs = Storage.getValue("historyLogs") as Array<Number>?;
        if (historyLogs == null) {
            historyLogs = [] as Array<Number>;
        }

        // Align size of historyLogs to be a multiple of 4
        var hSize = historyLogs.size();
        while (hSize % 4 != 0) {
            historyLogs.add(0);
            hSize++;
        }

        // Slice local copy to last 48 records (192 elements)
        if (hSize > 192) {
            historyLogs = historyLogs.slice(hSize - 192, null);
            hSize = historyLogs.size();
        }

        var numRecords = hSize / 4;
        if (numRecords >= 2) {
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
            
            for (var i = 1; i < numRecords; i++) {
                var prevIdx = (i - 1) * 4;
                var currIdx = i * 4;

                var prevT = historyLogs[prevIdx];
                var currT = historyLogs[currIdx];
                var prevB = historyLogs[prevIdx + 1];
                var currB = historyLogs[currIdx + 1];
                var prevC = historyLogs[prevIdx + 2];
                var currC = historyLogs[currIdx + 2];
                var currS = historyLogs[currIdx + 3];

                var dtSeconds = currT - prevT;
                var batDiffTenths = prevB - currB;
                
                // Track signed battery rate of change across windows (including charging/discharging)
                if (dtSeconds > 0 && dtSeconds < 172800) { // Capped at 48 hours to avoid massive outliers
                    var age = nowVal - currT;
                    
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
                if (nowVal - currT <= 86400) {
                    var gainTenths = -batDiffTenths; // Positive if battery increased
                    if (gainTenths > 0) {
                        if (currC == 1 || prevC == 1) {
                            acGainedTodayTenths += gainTenths;
                        } else {
                            // Float conversion only when calculating the charge rate of active points
                            var gainRatePerHourTenths = dtSeconds > 0 ? (gainTenths * 3600.0 / dtSeconds.toFloat()) : 0.0;
                            if (currS == 0 || gainRatePerHourTenths > 70.0) { // 7% per hour
                                acGainedTodayTenths += gainTenths;
                            } else if (currS > 0 || currC == 2) {
                                solarGainedTodayTenths += gainTenths;
                            }
                        }
                    }
                    
                    if (currS > 0) {
                        solarCountToday++;
                        solarSumToday += currS;
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
