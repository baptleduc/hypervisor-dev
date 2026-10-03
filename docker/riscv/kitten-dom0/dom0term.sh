#!/bin/sh
# XO's host console: vncterm runs this on a fresh pty, and runs it again
# when it exits. login straight on that pty times out after 60 s: the
# console's Enter arrives as CR, which busybox login took as the end of
# a line and util-linux login does not. agetty sets the line up as it
# does on a serial console (it maps CR when the user name ends with
# one), then hands over to login.
exec /sbin/agetty --noclear --local-line - linux
