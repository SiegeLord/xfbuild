diff -d --strip-trailing-cr --ignore-tab-expansion -x "*.obj" -x "*.exe" -x "*.swp" -x "*.map" -x win32.mak -rpu origDMD dmd | grep -v "^Only in dmd:" | grep -v "^Common subdirectories:" > dmdDiff.patch
rm patchDMD.sh
touch patchDMD.sh
grep '+++ dmd/.*' dmdDiff.patch | sed -e 's/.*+++ \([^	]*\).*/dos2unix \1/' >> patchDMD.sh
echo "patch -p0 -ui dmdDiff.patch" >> patchDMD.sh
