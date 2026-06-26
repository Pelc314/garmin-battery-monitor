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

        var height = dc.getHeight();

        var stats = System.getSystemStats();
        var battery = stats.battery;

        // Dynamically calculate estimate based on current battery and cached avg_drain_rate
        var avgDrainRate = Storage.getValue("avg_drain_rate") as Float?;
        var estDaysVal = null;
        if (avgDrainRate != null && avgDrainRate > 0.001) {
            estDaysVal = battery / avgDrainRate / 24.0;
        }
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

        // Top line: Title (restored to x = 5)
        dc.drawText(
            5, 
            (height * 0.3).toNumber(), 
            Graphics.FONT_XTINY, 
            "Batt Monitor by MPC", 
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Bottom line: Battery state & estimate
        var bodyText = battery.format("%.1f") + "%";
        if (stats.charging || (avgDrainRate != null && avgDrainRate < -0.05)) {
            bodyText += " (Charging)";
        } else if (estString.length() > 0) {
            bodyText += " (" + estString + ")";
        }

        // Draw bottom line text (restored to x = 5)
        dc.drawText(
            5, 
            (height * 0.75).toNumber(), 
            Graphics.FONT_XTINY, 
            bodyText, 
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Draw dynamic battery icon after the bottom line text
        var textWidth = dc.getTextWidthInPixels(bodyText, Graphics.FONT_XTINY);
        var iconX = 5 + textWidth + 8; // 8 pixels spacing
        var iconY = ((height * 0.75) - 6).toNumber(); // Centered vertically relative to the text line
        
        // Draw battery outer container
        dc.drawRectangle(iconX, iconY, 20, 12);
        dc.fillRectangle(iconX + 20, iconY + 3, 2, 6);
        
        // Draw bars based on battery percentage:
        // >= 66% => 3 bars, >= 33% => 2 bars, >= 8% => 1 bar, < 8% => 0 bars (empty)
        if (battery >= 66.0) {
            dc.fillRectangle(iconX + 3, iconY + 2, 4, 8);
            dc.fillRectangle(iconX + 8, iconY + 2, 4, 8);
            dc.fillRectangle(iconX + 13, iconY + 2, 4, 8);
        } else if (battery >= 33.0) {
            dc.fillRectangle(iconX + 3, iconY + 2, 4, 8);
            dc.fillRectangle(iconX + 8, iconY + 2, 4, 8);
        } else if (battery >= 8.0) {
            dc.fillRectangle(iconX + 3, iconY + 2, 4, 8);
        }
    }
}
