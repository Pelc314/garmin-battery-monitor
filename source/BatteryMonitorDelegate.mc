import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class BatteryMonitorDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BatteryMonitorView;
    private var _isPassive as Boolean;

    function initialize(view as BatteryMonitorView, isPassive as Boolean) {
        BehaviorDelegate.initialize();
        _view = view;
        _isPassive = isPassive;
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
        if (_isPassive) {
            var activeView = new BatteryMonitorView(false);
            var activeDelegate = new BatteryMonitorDelegate(activeView, false);
            WatchUi.pushView(activeView, activeDelegate, WatchUi.SLIDE_IMMEDIATE);
            return true;
        }

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

    // Handles BACK button press
    function onBack() as Lang.Boolean {
        if (_view.isResetConfirmationVisible()) {
            _view.toggleResetConfirmation();
            WatchUi.requestUpdate();
            return true; // Stay in the app, cancel reset
        } else if (_view.getPage() != 0) {
            _view.setPage(0);
            WatchUi.requestUpdate();
            return true; // Stay in the app, return to stats page
        }
        return false; // Let default system behavior handle it (exit widget)
    }
}
