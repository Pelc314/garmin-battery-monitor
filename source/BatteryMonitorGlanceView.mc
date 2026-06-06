import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:glance)
class BatteryMonitorGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    // Update the glance draw context
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();

        var stats = System.getSystemStats();
        var battery = stats.battery;

        // Calculate custom estimate dynamically inside the glance view
        var estDaysVal = calculateGlanceEstimate(battery);
        var estString = "";
        
        if (estDaysVal != null && estDaysVal > 0.0) {
            if (estDaysVal >= 1.0) {
                estString = estDaysVal.format("%.1f") + "d";
            } else {
                var estHours = estDaysVal * 24.0;
                estString = estHours.format("%.0f") + "h";
            }
        } else {
            // Fallback to system native estimate (only 1 or 0 data points)
            if (stats has :batteryInDays && stats.batteryInDays != null && stats.batteryInDays > 0) {
                estString = stats.batteryInDays.format("%.0f") + "d";
            } else {
                estString = "--";
            }
        }

        // Top line: Title
        dc.drawText(
            5, 
            (height * 0.3).toNumber(), 
            Graphics.FONT_XTINY, 
            "Batt Monitor by MPC", 
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Bottom line: Battery state & estimate
        var bodyText = battery.format("%.1f") + "%";
        if (stats.charging) {
            bodyText += " (Charging)";
        } else if (estString.length() > 0) {
            bodyText += " (" + estString + ")";
        }

        dc.drawText(
            5, 
            (height * 0.75).toNumber(), 
            Graphics.FONT_XTINY, 
            bodyText, 
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    // Calculates battery life estimate in days based on log history
    private function calculateGlanceEstimate(currentBattery as Float) as Float? {
        var timestamps = Storage.getValue("timestamps") as Array<Number>?;
        var batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        var chargingStates = Storage.getValue("chargingStates") as Array<Number>?;

        if (timestamps == null || batteryLevels == null || chargingStates == null) {
            return null;
        }

        var size = timestamps.size();
        if (size < 2) {
            return null;
        }

        var totalHours = 0.0;
        var totalDrop = 0.0;

        for (var i = 1; i < size; i++) {
            var dt = (timestamps[i] - timestamps[i-1]) / 3600.0;
            var batDiff = (batteryLevels[i-1] - batteryLevels[i]) / 10.0;

            // Only count discharging intervals
            if (chargingStates[i] == 0 && chargingStates[i-1] == 0 && dt > 0.0 && dt < 48.0) {
                if (batDiff >= 0.0) {
                    totalDrop += batDiff;
                    totalHours += dt;
                }
            }
        }

        if (totalHours > 0.1 && totalDrop >= 0.0) {
            var avgDrainRate = totalDrop / totalHours;
            if (avgDrainRate > 0.001) {
                var estHours = currentBattery / avgDrainRate;
                return estHours / 24.0;
            }
        }
        return null;
    }
}
