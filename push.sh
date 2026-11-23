#!/usr/bin/sh
rsync --delete --itemize-changes --recursive ./gleba/ cool:/httpd/dlc/gleba/
echo done
