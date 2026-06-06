import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class BatteryMonitorDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BatteryMonitorView;

    function initialize(view as BatteryMonitorView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Handles DOWN button press (Next Page)
    function onNextPage() as Lang.Boolean {
        _view.nextPage();
        WatchUi.requestUpdate();
        return true;
    }

    // Handles UP button press (Previous Page)
    function onPreviousPage() as Lang.Boolean {
        _view.previousPage();
        WatchUi.requestUpdate();
        return true;
    }

    // Handles GPS (Enter/Select) button press
    function onSelect() as Lang.Boolean {
        _view.onSelectKey();
        WatchUi.requestUpdate();
        
        // Play a short tactile confirmation vibration if supported
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 100)] as Lang.Array<Attention.VibeProfile>);
        }
        return true;
    }

    // Handles holding the MENU button (UP key hold)
    function onMenu() as Lang.Boolean {
        // Toggle reset confirmation page in the view
        _view.toggleResetConfirmation();
        WatchUi.requestUpdate();
        return true;
    }
}
