import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class BatteryMonitorView extends WatchUi.View {

    private var _page as Number = 0;             // 0 = Battery Stats, 1 = Charging Stats, 2 = Graph Page
    private var _graphDuration as Number = 0;    // 0 = 24h, 1 = 7d, 2 = 20d
    private var _showResetConfirm as Boolean = false;
    private var _isPassive as Boolean = false;

    // Cached history arrays
    private var _timestamps as Array<Number>?;
    private var _batteryLevels as Array<Number>?;
    private var _chargingStates as Array<Number>?;
    private var _solarIntensities as Array<Number>?;
    private var _size as Number = 0;

    // Caching variables for lazy-evaluation graph rendering
    private var _graphDataInvalid as Boolean = true;
    private var _graphHasEnoughData as Boolean = false;
    private var _curvePoints as Array< Array<Number> >?;
    private var _labelTop as String = "100";
    private var _labelMid as String = "50";
    private var _labelBot as String = "0";
    private var _xLabelLeft as String = "";
    private var _xLabelMid as String = "";
    private var _xLabelRight as String = "";
    private var _thresholdMsg as String = "";
    private var _durationLabel as String = "24h";
    private var _gx as Number = 0;
    private var _gy as Number = 0;
    private var _gw as Number = 0;
    private var _gh as Number = 0;
    private var _titleX as Number = 0;
    private var _titleY as Number = 0;

    // Cached statistics
    private var _avgDrainRate as Float = 0.0;
    private var _acGainedToday as Float = 0.0;
    private var _solarGainedToday as Float = 0.0;
    private var _solarIntensityAvgToday as Float = 0.0;
    private var _solarHoursToday as Float = 0.0;

    function initialize(isPassive as Boolean) {
        View.initialize();
        _isPassive = isPassive;
        BatteryLogger.mergePendingLogs();
        loadCachedAnalytics();
    }

    function onLayout(dc as Dc) as Void {
        // Drawing is done dynamically in onUpdate() to adjust coordinates 
        // to the Instinct 2 sub-window.
    }

    // Main draw loop
    function onUpdate(dc as Dc) as Void {
        // Set up background
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // 1. Fetch current status
        var stats = System.getSystemStats();
        var battery = stats.battery;
        var isCharging = stats.charging;
        var solar = 0;
        if (stats has :solarIntensity && stats.solarIntensity != null) {
            solar = stats.solarIntensity;
        }

        // Calculate dynamic estimate based on current battery level and average drain rate
        var estDays = 0.0;
        if (_avgDrainRate > 0.001) { //positive drain rate means that the battery is draining
            estDays = battery / _avgDrainRate / 24.0;
        }

        // 3. Draw Instinct 2 Sub-Window Widget (Dynamic placement via getSubscreen)
        var subscreen = null;
        if (WatchUi has :getSubscreen) {
            subscreen = WatchUi.getSubscreen();
        }
        
        if (subscreen != null) {
            var scx = subscreen.x + subscreen.width / 2;
            var scy = subscreen.y + subscreen.height / 2;
            var scr = subscreen.width / 2;
            
            // Draw border
            dc.setPenWidth(1);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawCircle(scx, scy, scr);
            
            // Draw battery arc gauge inside the circle (r-3)
            if (battery > 0) {
                dc.setPenWidth(3);
                var sweep = (battery * 3.6).toNumber();
                var startAngle = 90;
                var endAngle = 90 - sweep;
                dc.drawArc(scx, scy, scr - 3, Graphics.ARC_CLOCKWISE, startAngle, endAngle);
            }
            
            // Draw status inside
            dc.setPenWidth(1);
            if (isCharging) {
                // Lightning Bolt icon
                dc.drawLine(scx - 3, scy - 7, scx + 1, scy - 2);
                dc.drawLine(scx + 1, scy - 2, scx - 2, scy - 2);
                dc.drawLine(scx - 2, scy - 2, scx + 3, scy + 7);
            } else if (solar > 10) {
                // Sun icon
                dc.drawCircle(scx, scy, 3);
                for (var angle = 0.0; angle < 2.0 * Math.PI; angle += Math.PI / 4.0) {
                    var x1 = scx + (5.0 * Math.cos(angle)).toNumber();
                    var y1 = scy + (5.0 * Math.sin(angle)).toNumber();
                    var x2 = scx + (8.0 * Math.cos(angle)).toNumber();
                    var y2 = scy + (8.0 * Math.sin(angle)).toNumber();
                    dc.drawLine(x1, y1, x2, y2);
                }
            } else {
                // Show raw percentage text centered
                var battStr = battery.format("%.0f");
                dc.drawText(
                    scx, 
                    scy, 
                    Graphics.FONT_XTINY, 
                    battStr, 
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            }
        }

        // Return thickness to normal
        dc.setPenWidth(1);

        // 4. Render main screens
        if (_showResetConfirm) {
            drawResetConfirm(dc);
        } else {
            if (_page == 0) {
                drawStatsPage(dc, battery, estDays, _avgDrainRate);
            } else if (_page == 1) {
                drawChargingPage(dc, _acGainedToday, _solarGainedToday, _solarHoursToday, _solarIntensityAvgToday);
            } else {
                drawGraphPage(dc, _timestamps, _batteryLevels, _chargingStates, _size);
            }
            drawPageIndicator(dc);
        }
    }

    private function loadCachedAnalytics() as Void {
        _avgDrainRate = Storage.getValue("avg_drain_rate") as Float?;
        if (_avgDrainRate == null) { _avgDrainRate = 0.0; }
        
        _acGainedToday = Storage.getValue("ac_gained_today") as Float?;
        if (_acGainedToday == null) { _acGainedToday = 0.0; }
        
        _solarGainedToday = Storage.getValue("solar_gained_today") as Float?;
        if (_solarGainedToday == null) { _solarGainedToday = 0.0; }
        
        _solarIntensityAvgToday = Storage.getValue("solar_intensity_avg_today") as Float?;
        if (_solarIntensityAvgToday == null) { _solarIntensityAvgToday = 0.0; }
        
        _solarHoursToday = Storage.getValue("solar_hours_today") as Float?;
        if (_solarHoursToday == null) { _solarHoursToday = 0.0; }
    }

    private function loadGraphCache() as Void {
        _timestamps = Storage.getValue("timestamps") as Array<Number>?;
        _batteryLevels = Storage.getValue("batteryLevels") as Array<Number>?;
        _chargingStates = Storage.getValue("chargingStates") as Array<Number>?;
        
        _size = 0;
        if (_timestamps != null) {
            _size = _timestamps.size();
            if (_batteryLevels != null && _batteryLevels.size() < _size) { _size = _batteryLevels.size(); }
            if (_chargingStates != null && _chargingStates.size() < _size) { _size = _chargingStates.size(); }
        }
        _graphDataInvalid = true;
    }

    private function clearGraphCache() as Void {
        _timestamps = null;
        _batteryLevels = null;
        _chargingStates = null;
        _size = 0;
        _curvePoints = null;
        _graphDataInvalid = true;
    }

    // Draws a thin vertical scrollbar line on the far-left edge of the screen
    private function drawPageIndicator(dc as Dc) as Void {
        var x = 2;
        var height = dc.getHeight();
        
        var yStart = (height * 0.35).toNumber();
        var segmentHeight = (height * 0.11).toNumber(); // 3 segments
        
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        
        var activeYStart = yStart + _page * segmentHeight;
        dc.drawLine(x, activeYStart, x, activeYStart + segmentHeight - 1);
        
        // Reset pen width
        dc.setPenWidth(1);
    }

    // Page 1: Statistics
    private function drawStatsPage(dc as Dc, battery as Float, estDays as Float, avgDrainRate as Float) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var isInstinct = hasSubscreen();
        
        var leftCenter = width / 2;
        var yTitle = (height * 0.18).toNumber();
        var yPercent = (height * 0.38).toNumber();
        var yEst = (height * 0.60).toNumber();
        var yDrain = (height * 0.78).toNumber();
        
        if (isInstinct) {
            leftCenter = (width <= 156) ? 50 : 60;
            yTitle = (height <= 156) ? 26 : 30;
            yPercent = (height <= 156) ? 48 : 55;
            yEst = (height <= 156) ? 72 : 82;
            yDrain = (height <= 156) ? 94 : 104;
        }
        
        // Title
        dc.drawText(leftCenter, yTitle, Graphics.FONT_XTINY, "BATTERY", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        
        // Large Percent
        dc.drawText(leftCenter, yPercent, Graphics.FONT_MEDIUM, battery.format("%.1f") + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        
        // Custom Estimate falling back to System Native estimate if not enough logs
        var estStr = "Need 2 logs";
        if (estDays > 0.0) {
            var days = estDays.toNumber();
            var hours = ((estDays - days) * 24.0).toNumber();
            estStr = days.toString() + "d " + hours.toString() + "h left";
        } else {
            var stats = System.getSystemStats();
            if (stats has :batteryInDays && stats.batteryInDays != null && stats.batteryInDays > 0) {
                var nativeEst = stats.batteryInDays;
                var days = nativeEst.toNumber();
                var hours = ((nativeEst - days) * 24.0).toNumber();
                estStr = days.toString() + "d " + hours.toString() + "h left (sys)";
            }
        }
        dc.drawText(leftCenter, yEst, Graphics.FONT_XTINY, estStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Drain Rate / Interaction Prompt
        var drainStr = "Drain: --";
        if (_isPassive) {
            drainStr = isInstinct ? "Press GPS" : "Tap to open";
        } else if (avgDrainRate != 0.0) {
            if (avgDrainRate < 0.0) {
                drainStr = "Chrg: +" + (-avgDrainRate).format("%.2f") + "%/h";
            } else {
                drainStr = "Drain: -" + avgDrainRate.format("%.2f") + "%/h";
            }
        }
        dc.drawText(leftCenter, yDrain, Graphics.FONT_XTINY, drainStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Page 2: Today's Charging details
    private function drawChargingPage(dc as Dc, acGainedToday as Float, solarGainedToday as Float, solarHoursToday as Float, solarIntensityAvgToday as Float) as Void {
        var sunSumXAxisMultiplayer = 0.815;
        var width = dc.getWidth();
        var height = dc.getHeight();
        var isInstinct = hasSubscreen();
        
        var leftCenter = width / 2;
        var yTitle1 = (height * 0.16).toNumber();
        var yTitle2 = (height * 0.26).toNumber();
        var yAc = (height * 0.40).toNumber();
        var ySun = (height * 0.52).toNumber();
        var yExp = (height * 0.64).toNumber();
        var yAvgSun = (height * 0.76).toNumber();

        if (isInstinct) {
            leftCenter = (width <= 156) ? 50 : 55;
            yTitle1 = (height <= 156) ? 28 : 36;
            yTitle2 = (height <= 156) ? 44 : 54;
            yAc = (height <= 156) ? 62 : 74;
            ySun = (height <= 156) ? 80 : 94;
            yExp = (height <= 156) ? 98 : 114;
            yAvgSun = (height <= 156) ? 116 : 134;
        }

        // Title split into two lines
        dc.drawText(leftCenter, yTitle1, Graphics.FONT_XTINY, "LAST 24h", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(leftCenter, yTitle2, Graphics.FONT_XTINY, "CHARGE", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Check solar hardware capability dynamically
        var stats = System.getSystemStats();
        var hasSolar = (stats has :solarIntensity && stats.solarIntensity != null);

        if (hasSolar) {
            // AC Gained
            dc.drawText(leftCenter, yAc, Graphics.FONT_XTINY, "AC: +" + acGainedToday.format("%.1f") + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Solar Gained
            dc.drawText(leftCenter, ySun, Graphics.FONT_XTINY, "Sun: +" + solarGainedToday.format("%.1f") + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Solar Time
            dc.drawText(leftCenter, yExp, Graphics.FONT_XTINY, "Exposure: " + solarHoursToday.format("%.1f") + "h", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Solar Avg Intensity
            dc.drawText(leftCenter, yAvgSun, Graphics.FONT_XTINY, "Avg Sun: " + solarIntensityAvgToday.format("%.0f") + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Estimate harvested solar energy dynamically (assuming 2.0 mA max charging current at 100% solar intensity)
            var solarEnergyToday = solarHoursToday * solarIntensityAvgToday * 0.02;
            dc.drawText(width * sunSumXAxisMultiplayer, ySun, Graphics.FONT_XTINY, "Sun Pwr:", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER); 
            dc.drawText(width * sunSumXAxisMultiplayer, yExp, Graphics.FONT_XTINY, "+" + solarEnergyToday.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(width * sunSumXAxisMultiplayer, yAvgSun, Graphics.FONT_XTINY, "mAh", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            
        } else {
            // Hides all solar indicators and vertically centers the AC gained indicator
            var yCenteredAc = (height * 0.55).toNumber();
            if (isInstinct) {
                yCenteredAc = (height <= 156) ? 80 : 90;
            }
            dc.drawText(leftCenter, yCenteredAc, Graphics.FONT_XTINY, "AC: +" + acGainedToday.format("%.1f") + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function calculateGraphData(dc as Dc) as Void {
        _durationLabel = "24h";
        var windowSecs = 24 * 3600;
        _thresholdMsg = "Need 2 data points";
        
        if (_graphDuration == 1) {
            _durationLabel = "7d";
            windowSecs = 168 * 3600;
            _thresholdMsg = "Need 12h of history";
        } else if (_graphDuration == 2) {
            _durationLabel = "20d";
            windowSecs = 20 * 24 * 3600;
            _thresholdMsg = "Need 7d of history";
        }

        var width = dc.getWidth();
        var height = dc.getHeight();
        var isInstinct = hasSubscreen();

        _gw = (width * 0.75).toNumber();
        _gh = (height * 0.35).toNumber();
        _gx = (width - _gw) / 2;
        _gy = (height * 0.38).toNumber();
        
        _titleX = width / 2;
        _titleY = (height * 0.22).toNumber();

        if (isInstinct) {
            _gx = 25;
            _gy = 74; 
            _gw = 125;
            _gh = 57; 
            
            if (width <= 156) {
                // Instinct 2S screen dimensions optimization
                _gx = 20;
                _gw = 115;
                _gy = 68;
                _gh = 50;
            }
            
            _titleX = (width <= 156) ? 48 : 54;
            _titleY = (height <= 156) ? 38 : 45;
        }

        var now = Time.now().value();
        var windowStart = now - windowSecs;

        // Count how many logged points fall within this time window
        var validStartIdx = _size;
        if (_timestamps != null) {
            for (var i = 0; i < _size; i++) {
                if (_timestamps[i] >= windowStart) {
                    validStartIdx = i;
                    break;
                }
            }
        }
        var validPoints = _size - validStartIdx;

        _graphHasEnoughData = false;
        if (validPoints >= 2 && _batteryLevels != null && _chargingStates != null && _timestamps != null) {
            var durationSpanned = _timestamps[_size - 1] - _timestamps[validStartIdx];
            if (_graphDuration == 0) {
                // 24h: just need at least 2 points to draw a line
                _graphHasEnoughData = true;
            } else if (_graphDuration == 1) {
                // 7d: need at least 12 hours spanned
                if (durationSpanned >= 43200) {
                    _graphHasEnoughData = true;
                }
            } else {
                // 20d: need at least 7 days spanned
                if (durationSpanned >= 604800) {
                    _graphHasEnoughData = true;
                }
            }
        }

        // Calculate Y-axis range and labels (dynamic for 24h mode, 0-100% for 7d/20d)
        var minY = 0.0;
        var maxY = 100.0;
        _labelTop = "100";
        _labelMid = "50";
        _labelBot = "0";

        if (_graphHasEnoughData) {
            if (_graphDuration == 0 && _batteryLevels != null) {
                // 24h mode: calculate dynamic Y-axis range based on actual log min/max
                var lowest = 100.0;
                var highest = 0.0;
                for (var i = 0; i < validPoints; i++) {
                    var idx = validStartIdx + i;
                    var val = _batteryLevels[idx] / 10.0; // Float %
                    if (val < lowest) { lowest = val; }
                    if (val > highest) { highest = val; }
                }
                
                minY = lowest - 15.0;
                maxY = highest + 15.0;
                
                // Clamp boundaries
                if (minY < 0.0) { minY = 0.0; }
                if (maxY > 100.0) { maxY = 100.0; }
                
                // Avoid divide-by-zero or flat range
                if (maxY - minY < 1.0) {
                    minY = 0.0;
                    maxY = 100.0;
                }
                
                _labelTop = maxY.format("%.0f");
                _labelMid = ((minY + maxY) / 2.0).format("%.0f");
                _labelBot = minY.format("%.0f");
            }
        }

        // 1. Build the curve points
        _curvePoints = [] as Array< Array<Number> >;
        if (_graphHasEnoughData && _timestamps != null && _batteryLevels != null && _chargingStates != null) {
            var lastAddedX = -1;
            for (var i = 0; i < validPoints; i++) {
                var idx = validStartIdx + i;
                var t = _timestamps[idx];
                var valY = _batteryLevels[idx] / 10.0;
                
                var ratio = (t - windowStart).toFloat() / windowSecs.toFloat();
                if (ratio < 0.0) { ratio = 0.0; }
                if (ratio > 1.0) { ratio = 1.0; }
                
                var x = _gx + (ratio * _gw).toNumber();
                
                // Dynamic Y mapping
                var valRatio = (valY - minY) / (maxY - minY);
                if (valRatio < 0.0) { valRatio = 0.0; }
                if (valRatio > 1.0) { valRatio = 1.0; }
                var y = _gy + _gh - (valRatio * _gh).toNumber();
                
                if (i == 0 || i == validPoints - 1 || x != lastAddedX) {
                    _curvePoints.add([x, y, _chargingStates[idx]] as Array<Number>);
                    lastAddedX = x;
                }
            }
        }

        // Calculate X-axis ticks and labels
        _xLabelLeft = "";
        _xLabelMid = "";
        _xLabelRight = "";
        
        if (_graphHasEnoughData) {
            if (_graphDuration == 0) {
                // 24h: show hour of the day (e.g. 14h)
                var infoLeft = Gregorian.info(new Time.Moment(windowStart), Time.FORMAT_SHORT);
                var infoMid = Gregorian.info(new Time.Moment(windowStart + 43200), Time.FORMAT_SHORT);
                var infoRight = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
                
                _xLabelLeft = infoLeft.hour.format("%02d") + "h";
                _xLabelMid = infoMid.hour.format("%02d") + "h";
                _xLabelRight = infoRight.hour.format("%02d") + "h";
            } else if (_graphDuration == 1) {
                // 7d: show day names (Mon, Wed, Fri)
                var days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                var infoLeft = Gregorian.info(new Time.Moment(windowStart), Time.FORMAT_SHORT);
                var infoMid = Gregorian.info(new Time.Moment(windowStart + 302400), Time.FORMAT_SHORT); // 3.5 days = 302400 seconds
                var infoRight = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
                
                _xLabelLeft = days[infoLeft.day_of_week];
                _xLabelMid = days[infoMid.day_of_week];
                _xLabelRight = days[infoRight.day_of_week];
            } else {
                // 20d: show relative day marks D1, D10, D20
                _xLabelLeft = "D1";
                _xLabelMid = "D10";
                _xLabelRight = "D20";
            }
        }
    }

    // Page 2: History Graph
    private function drawGraphPage(dc as Dc, timestamps as Array<Number>?, batteryLevels as Array<Number>?, chargingStates as Array<Number>?, size as Number) as Void {
        if (_graphDataInvalid) {
            calculateGraphData(dc);
            _graphDataInvalid = false;
        }

        // Title (centered and safe from top-left clipping)
        dc.drawText(_titleX, _titleY, Graphics.FONT_XTINY, "HISTORY: " + _durationLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Draw bounding box
        dc.drawLine(_gx, _gy + _gh, _gx + _gw, _gy + _gh); // X axis
        dc.drawLine(_gx, _gy, _gx, _gy + _gh);           // Y axis

        // Draw Y labels
        dc.drawText(_gx - 1, _gy, Graphics.FONT_XTINY, _labelTop, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_gx - 3, _gy + _gh - 7, Graphics.FONT_XTINY, _labelBot, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_gx - 3, _gy + _gh / 2, Graphics.FONT_XTINY, _labelMid, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (!_graphHasEnoughData) {
            // Display message that more data needs to be collected
            dc.drawText(_gx + _gw / 2, _gy + _gh / 2, Graphics.FONT_XTINY, _thresholdMsg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // 1. Build and fill the polygon for the area under the curve in batches
            var cpSize = _curvePoints != null ? _curvePoints.size() : 0;
            if (cpSize >= 2 && _curvePoints != null) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
                var batchSize = 40; // Under 64 point limit
                var startIdx = 0;
                while (startIdx < cpSize - 1) {
                    var endIdx = startIdx + batchSize;
                    if (endIdx >= cpSize) {
                        endIdx = cpSize - 1;
                    }
                    
                    var poly = [] as Array< Array<Number> >;
                    
                    // Bottom-left anchor for this batch
                    poly.add([_curvePoints[startIdx][0], _gy + _gh] as Array<Number>);
                    
                    // Add curve points for this batch
                    for (var j = startIdx; j <= endIdx; j++) {
                        poly.add([_curvePoints[j][0], _curvePoints[j][1]] as Array<Number>);
                    }
                    
                    // Bottom-right anchor for this batch
                    poly.add([_curvePoints[endIdx][0], _gy + _gh] as Array<Number>);
                    
                    dc.fillPolygon(poly as Array);
                    
                    startIdx = endIdx; // Next batch starts where this one ended
                }
            }

            // 2. Plot white battery points line on top of the gray area
            var prevX = 0;
            var prevY = 0;
            var first = true;
            
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            if (_curvePoints != null) {
                for (var i = 0; i < cpSize; i++) {
                    var pt = _curvePoints[i];
                    var x = pt[0];
                    var y = pt[1];
                    var isCharging = pt[2];

                    if (!first) {
                        // Highlight charging intervals with double lines
                        if (isCharging == 1) {
                            dc.drawLine(prevX, prevY, x, y);
                            dc.drawLine(prevX, prevY + 1, x, y + 1);
                        } else {
                            dc.drawLine(prevX, prevY, x, y);
                        }
                    } else {
                        first = false;
                    }
                    prevX = x;
                    prevY = y;
                }
            }

            // 3. Redraw white bounding box lines to ensure they are crisp on top of the gray fill
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawLine(_gx, _gy + _gh, _gx + _gw, _gy + _gh); // X axis
            dc.drawLine(_gx, _gy, _gx, _gy + _gh);           // Y axis
            
            // Draw tick marks (3 pixels high)
            dc.drawLine(_gx, _gy + _gh, _gx, _gy + _gh + 3);
            dc.drawLine(_gx + _gw / 2, _gy + _gh, _gx + _gw / 2, _gy + _gh + 3);
            dc.drawLine(_gx + _gw, _gy + _gh, _gx + _gw, _gy + _gh + 3);
            
            // Draw labels centered below ticks (positioned at y = 143 to avoid axis overlapping)
            dc.drawText(_gx, _gy + _gh + 12, Graphics.FONT_XTINY, _xLabelLeft, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(_gx + _gw / 2, _gy + _gh + 12, Graphics.FONT_XTINY, _xLabelMid, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(_gx + _gw, _gy + _gh + 12, Graphics.FONT_XTINY, _xLabelRight, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Page 3: Reset Confirmation
    private function drawResetConfirm(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        
        dc.drawText(cx, cy - 45, Graphics.FONT_SMALL, "RESET LOGS?", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy - 10, Graphics.FONT_XTINY, "This wipes all history.", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + 27, Graphics.FONT_XTINY, "GPS: Confirm Reset", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + 47, Graphics.FONT_XTINY, "BACK: Cancel Reset", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Navigation methods
    function nextPage() as Void {
        if (_showResetConfirm) { return; }
        _page = (_page + 1) % 3;
        if (_page != 2) {
            clearGraphCache();
        } else {
            loadGraphCache();
        }
    }

    function previousPage() as Void {
        if (_showResetConfirm) { return; }
        _page = (_page - 1 + 3) % 3;
        if (_page != 2) {
            clearGraphCache();
        } else {
            loadGraphCache();
        }
    }

    function toggleResetConfirmation() as Void {
        _showResetConfirm = !_showResetConfirm;
    }

    function getPage() as Number {
        return _page;
    }

    function setPage(page as Number) as Void {
        _page = page;
        if (_page != 2) {
            clearGraphCache();
        } else {
            loadGraphCache();
        }
    }

    function isResetConfirmationVisible() as Lang.Boolean {
        return _showResetConfirm;
    }

    // Handles selection key (GPS)
    function onSelectKey() as Void {
        if (_showResetConfirm) {
            // Confirm reset
            Storage.deleteValue("timestamps");
            Storage.deleteValue("batteryLevels");
            Storage.deleteValue("chargingStates");
            Storage.deleteValue("solarIntensities");
            Storage.deleteValue("est_days");
            Storage.deleteValue("avg_drain_rate");
            Storage.deleteValue("ac_gained_today");
            Storage.deleteValue("solar_gained_today");
            Storage.deleteValue("solar_intensity_avg_today");
            Storage.deleteValue("solar_hours_today");
            _showResetConfirm = false;
            
            clearGraphCache();
            _avgDrainRate = 0.0;
            _acGainedToday = 0.0;
            _solarGainedToday = 0.0;
            _solarIntensityAvgToday = 0.0;
            _solarHoursToday = 0.0;
            
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_RESET);
            }
        } else if (_page == 2) {
            // Cycle duration: 24h (0) -> 7d (1) -> 20d (2)
            _graphDuration = (_graphDuration + 1) % 3;
            _graphDataInvalid = true;
        } else {
            // BatteryLogger.seedDebugData();
            BatteryLogger.logCurrentState();
            
            loadCachedAnalytics();
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_KEY);
            }
        }
    }

    private function hasSubscreen() as Lang.Boolean {
        if (WatchUi has :getSubscreen) {
            var sub = WatchUi.getSubscreen();
            if (sub != null) {
                return true;
            }
        }
        return false;
    }
}
