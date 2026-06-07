import Toybox.Background;
import Toybox.System;

(:background)
class BatteryMonitorServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Called when the temporal background event triggers
    function onTemporalEvent() as Void {
        BatteryLogger.logCurrentState();
        Background.exit(true);
    }
}
