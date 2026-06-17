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

    // Cached statistics
    private var _avgDrainRate as Float = 0.0;
    private var _acGainedToday as Float = 0.0;
    private var _solarGainedToday as Float = 0.0;
    private var _solarIntensityAvgToday as Float = 0.0;
    private var _solarHoursToday as Float = 0.0;

    function initialize(isPassive as Boolean) {
        View.initialize();
        _isPassive = isPassive;
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
        if (_avgDrainRate > 0.001) {
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
    }

    private function clearGraphCache() as Void {
        _timestamps = null;
        _batteryLevels = null;
        _chargingStates = null;
        _size = 0;
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
        } else if (avgDrainRate > 0.0) {
            drainStr = "Drain: -" + avgDrainRate.format("%.2f") + "%/h";
        }
        dc.drawText(leftCenter, yDrain, Graphics.FONT_XTINY, drainStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Page 2: Today's Charging details
    private function drawChargingPage(dc as Dc, acGainedToday as Float, solarGainedToday as Float, solarHoursToday as Float, solarIntensityAvgToday as Float) as Void {
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
        } else {
            // Hides all solar indicators and vertically centers the AC gained indicator
            var yCenteredAc = (height * 0.55).toNumber();
            if (isInstinct) {
                yCenteredAc = (height <= 156) ? 80 : 90;
            }
            dc.drawText(leftCenter, yCenteredAc, Graphics.FONT_XTINY, "AC: +" + acGainedToday.format("%.1f") + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Page 2: History Graph
    private function drawGraphPage(dc as Dc, timestamps as Array<Number>?, batteryLevels as Array<Number>?, chargingStates as Array<Number>?, size as Number) as Void {
        var durationLabel = "24h";
        var windowSecs = 24 * 3600;
        var thresholdMsg = "Need 2 data points";
        
        if (_graphDuration == 1) {
            durationLabel = "7d";
            windowSecs = 168 * 3600;
            thresholdMsg = "Need 12h of history";
        } else if (_graphDuration == 2) {
            durationLabel = "20d";
            windowSecs = 20 * 24 * 3600;
            thresholdMsg = "Need 7d of history";
        }

        var width = dc.getWidth();
        var height = dc.getHeight();
        var isInstinct = hasSubscreen();

        var gw = (width * 0.75).toNumber();
        var gh = (height * 0.35).toNumber();
        var gx = (width - gw) / 2;
        var gy = (height * 0.38).toNumber();
        
        var titleX = width / 2;
        var titleY = (height * 0.22).toNumber();

        if (isInstinct) {
            gx = 25;
            gy = 74; 
            gw = 125;
            gh = 57; 
            
            if (width <= 156) {
                // Instinct 2S screen dimensions optimization
                gx = 20;
                gw = 115;
                gy = 68;
                gh = 50;
            }
            
            titleX = (width <= 156) ? 48 : 54;
            titleY = (height <= 156) ? 38 : 45;
        }

        // Title (centered and safe from top-left clipping)
        dc.drawText(titleX, titleY, Graphics.FONT_XTINY, "HISTORY: " + durationLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var now = Time.now().value();
        var windowStart = now - windowSecs;

        // Count how many logged points fall within this time window
        var validStartIdx = size;
        if (timestamps != null) {
            for (var i = 0; i < size; i++) {
                if (timestamps[i] >= windowStart) {
                    validStartIdx = i;
                    break;
                }
            }
        }
        var validPoints = size - validStartIdx;

        var hasEnoughData = false;
        if (validPoints >= 2 && batteryLevels != null && chargingStates != null && timestamps != null) {
            var durationSpanned = timestamps[size - 1] - timestamps[validStartIdx];
            if (_graphDuration == 0) {
                // 24h: just need at least 2 points to draw a line
                hasEnoughData = true;
            } else if (_graphDuration == 1) {
                // 7d: need at least 12 hours spanned
                if (durationSpanned >= 43200) {
                    hasEnoughData = true;
                }
            } else {
                // 20d: need at least 7 days spanned
                if (durationSpanned >= 604800) {
                    hasEnoughData = true;
                }
            }
        }

        // Calculate Y-axis range and labels (dynamic for 24h mode, 0-100% for 7d/20d)
        var minY = 0.0;
        var maxY = 100.0;
        var labelTop = "100";
        var labelMid = "50";
        var labelBot = "0";

        if (hasEnoughData) {
            if (_graphDuration == 0 && batteryLevels != null) {
                // 24h mode: calculate dynamic Y-axis range based on actual log min/max
                var lowest = 100.0;
                var highest = 0.0;
                for (var i = 0; i < validPoints; i++) {
                    var idx = validStartIdx + i;
                    var val = batteryLevels[idx] / 10.0; // Float %
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
                
                labelTop = maxY.format("%.0f");
                labelMid = ((minY + maxY) / 2.0).format("%.0f");
                labelBot = minY.format("%.0f");
            }
        }

        // Draw bounding box
        dc.drawLine(gx, gy + gh, gx + gw, gy + gh); // X axis
        dc.drawLine(gx, gy, gx, gy + gh);           // Y axis

        // Draw Y labels
        // Move top label 2 pixels to the right (gx - 1) to prevent left-edge squircle clipping
        dc.drawText(gx - 1, gy, Graphics.FONT_XTINY, labelTop, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        // Move bottom label 7 pixels up (gy + gh - 7) to prevent overlap with the X-axis tick labels below it
        dc.drawText(gx - 3, gy + gh - 7, Graphics.FONT_XTINY, labelBot, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(gx - 3, gy + gh / 2, Graphics.FONT_XTINY, labelMid, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (!hasEnoughData) {
            // Display message that more data needs to be collected
            dc.drawText(gx + gw / 2, gy + gh / 2, Graphics.FONT_XTINY, thresholdMsg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // 1. Build and fill the polygon for the area under the curve in batches
            // Garmin's dc.fillPolygon has a limit of 64 points. We collect all unique points
            // on the curve, then draw the shaded area in contiguous batches of at most 40 curve points.
            var curvePoints = [] as Array< Array<Number> >;
            var lastAddedX = -1;
            
            for (var i = 0; i < validPoints; i++) {
                var idx = validStartIdx + i;
                var t = timestamps[idx];
                var valY = batteryLevels[idx] / 10.0;
                
                var ratio = (t - windowStart).toFloat() / windowSecs.toFloat();
                if (ratio < 0.0) { ratio = 0.0; }
                if (ratio > 1.0) { ratio = 1.0; }
                
                var x = gx + (ratio * gw).toNumber();
                
                // Dynamic Y mapping
                var valRatio = (valY - minY) / (maxY - minY);
                if (valRatio < 0.0) { valRatio = 0.0; }
                if (valRatio > 1.0) { valRatio = 1.0; }
                var y = gy + gh - (valRatio * gh).toNumber();
                
                if (i == 0 || i == validPoints - 1 || x != lastAddedX) {
                    curvePoints.add([x, y, chargingStates[idx]] as Array<Number>);
                    lastAddedX = x;
                }
            }
            
            var cpSize = curvePoints.size();
            if (cpSize >= 2) {
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
                    poly.add([curvePoints[startIdx][0], gy + gh] as Array<Number>);
                    
                    // Add curve points for this batch
                    for (var j = startIdx; j <= endIdx; j++) {
                        poly.add([curvePoints[j][0], curvePoints[j][1]] as Array<Number>);
                    }
                    
                    // Bottom-right anchor for this batch
                    poly.add([curvePoints[endIdx][0], gy + gh] as Array<Number>);
                    
                    dc.fillPolygon(poly as Array);
                    
                    startIdx = endIdx; // Next batch starts where this one ended
                }
            }

            // 2. Plot white battery points line on top of the gray area
            var prevX = 0;
            var prevY = 0;
            var first = true;
            
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            for (var i = 0; i < cpSize; i++) {
                var pt = curvePoints[i];
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

            // 3. Redraw white bounding box lines to ensure they are crisp on top of the gray fill
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawLine(gx, gy + gh, gx + gw, gy + gh); // X axis
            dc.drawLine(gx, gy, gx, gy + gh);           // Y axis
            
            // Draw X-axis ticks and labels
            var xLabelLeft = "";
            var xLabelMid = "";
            var xLabelRight = "";
            
            if (_graphDuration == 0) {
                // 24h: show hour of the day (e.g. 14h)
                var infoLeft = Gregorian.info(new Time.Moment(windowStart), Time.FORMAT_SHORT);
                var infoMid = Gregorian.info(new Time.Moment(windowStart + 43200), Time.FORMAT_SHORT);
                var infoRight = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
                
                xLabelLeft = infoLeft.hour.format("%02d") + "h";
                xLabelMid = infoMid.hour.format("%02d") + "h";
                xLabelRight = infoRight.hour.format("%02d") + "h";
            } else if (_graphDuration == 1) {
                // 7d: show day names (Mon, Wed, Fri)
                var days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                var infoLeft = Gregorian.info(new Time.Moment(windowStart), Time.FORMAT_SHORT);
                var infoMid = Gregorian.info(new Time.Moment(windowStart + 302400), Time.FORMAT_SHORT); // 3.5 days = 302400 seconds
                var infoRight = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
                
                xLabelLeft = days[infoLeft.day_of_week];
                xLabelMid = days[infoMid.day_of_week];
                xLabelRight = days[infoRight.day_of_week];
            } else {
                // 20d: show relative day marks D1, D10, D20
                xLabelLeft = "D1";
                xLabelMid = "D10";
                xLabelRight = "D20";
            }
            
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            
            // Draw tick marks (3 pixels high)
            dc.drawLine(gx, gy + gh, gx, gy + gh + 3);
            dc.drawLine(gx + gw / 2, gy + gh, gx + gw / 2, gy + gh + 3);
            dc.drawLine(gx + gw, gy + gh, gx + gw, gy + gh + 3);
            
            // Draw labels centered below ticks (positioned at y = 143 to avoid axis overlapping)
            dc.drawText(gx, gy + gh + 12, Graphics.FONT_XTINY, xLabelLeft, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(gx + gw / 2, gy + gh + 12, Graphics.FONT_XTINY, xLabelMid, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(gx + gw, gy + gh + 12, Graphics.FONT_XTINY, xLabelRight, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
        } else {
            // Trigger manual logging point or seeder depending on environment
            var settings = System.getDeviceSettings();
            if (settings has :simulator && settings.simulator) {
                BatteryLogger.seedDebugData();
            } else {
                BatteryLogger.logCurrentState();
            }
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
