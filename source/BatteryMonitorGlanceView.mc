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
        var centerY = height / 2;

        var stats = System.getSystemStats();
        var battery = stats.battery;

        // Draw left side label
        dc.drawText(
            5, 
            centerY, 
            Graphics.FONT_MEDIUM, 
            "BATT MON", 
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Fetch pre-calculated custom estimate from persistent storage
        var estDaysVal = Storage.getValue("est_days") as Float?;
        var estString = "";
        
        if (estDaysVal != null && estDaysVal > 0.0) {
            if (estDaysVal >= 1.0) {
                estString = estDaysVal.format("%.1f") + "d";
            } else {
                var estHours = estDaysVal * 24.0;
                estString = estHours.format("%.0f") + "h";
            }
        } else {
            // Fallback to system native estimate
            if (stats has :batteryInDays && stats.batteryInDays != null && stats.batteryInDays > 0) {
                estString = stats.batteryInDays.format("%.0f") + "d";
            } else {
                estString = "--";
            }
        }

        // Draw right side percentage and estimate
        var rightText = battery.format("%.1f") + "% (" + estString + ")";
        dc.drawText(
            width - 5, 
            centerY, 
            Graphics.FONT_MEDIUM, 
            rightText, 
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
