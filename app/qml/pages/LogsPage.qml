import QtQuick

// Retired page slot (StackLayout index 1).
//
// Live Logs had no nav row and no App.goto(1) call site anywhere — it was
// unreachable while still being constructed at startup. Its terminal output and
// EMERGENCY STOP button live inside the Scraper page's own log panel (see
// DashboardPage.qml, which hosts the same shared TerminalPanel), so nothing was
// lost by removing the duplicate.
//
// The slot itself is kept rather than deleted: a StackLayout's index IS its child
// order, and pages 2..12 are hardcoded across the QML files and
// app_controller.py's PAGE_* constants. Removing the child would shift every one
// of them by one.
Item {}
