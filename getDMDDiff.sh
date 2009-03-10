diff -u -x "*.exe" -x "*.swp" -x "*.map" -X dmd/sc.ini origDMD dmd | grep -v "^Only in dmd:" | grep -v "^Common subdirectories:"
