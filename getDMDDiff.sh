diff -u -x "*.exe" -x "*.swp" -x "*.map" -x win32.mak origDMD dmd | grep -v "^Only in dmd:" | grep -v "^Common subdirectories:"
