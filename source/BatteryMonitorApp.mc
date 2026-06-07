import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class BatteryMonitorApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Register the background service to run every 20 minutes (1200 seconds)
        // System enforces a minimum of 5 minutes (300 seconds)
        registerBackgroundEvent();
    }

    // onStop() is called when the application is exiting
    function onStop(state as Dictionary?) as Void {
        // We do NOT unregister the background service because we want it to keep
        // logging battery data even when the user closes the main app screen.
    }

    // Return the initial view and delegate of the application
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new BatteryMonitorView();
        var delegate = new BatteryMonitorDelegate(view);
        return [ view, delegate ] as [WatchUi.Views, WatchUi.InputDelegates];
    }

    // Return the view to show in the Glance/Widget loop
    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [ new BatteryMonitorGlanceView() ] as [WatchUi.GlanceView];
    }

    // Return the service delegate to run in the background process
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [ new BatteryMonitorServiceDelegate() ] as [System.ServiceDelegate];
    }

    // Registers the temporal background event if not already set or mismatched
    function registerBackgroundEvent() as Void {
        if (System has :ServiceDelegate) {
            // Register background temporal event for every 20 minutes (1200 seconds)
            Background.registerForTemporalEvent(new Time.Duration(1200));
        }
    }
}

// Global function to return the app instance (standard boilerplate)
function getApp() as BatteryMonitorApp {
    return Application.getApp() as BatteryMonitorApp;
}
