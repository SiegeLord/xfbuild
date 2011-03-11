#!/bin/bash

xf=\.\.
extra=

while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: ldcBuild.sh [--help] [--xf /path/to/xf] [--extra args fo the compiler]"
            echo ""
            echo "Builds xfbuild usin the ldc compiler."
            echo ""
            echo "--xf            path of the xf library"
            echo ""
            exit 0
            ;;
        --xf)
	    shift
	    xf=$1
	    ;;
	--extra)
	    shift
	    extra=$*
	    break
	    ;;
        *)
            die "Unknown parameter '$1'."
            break
            ;;
    esac
    shift
done

sed -e "s|\.\.|$xf|" modList.lst | xargs ldc -g -d-version=MultiThreaded -of=xfbuild $extra

