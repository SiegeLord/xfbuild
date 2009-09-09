#!/bin/bash

xf=\.\.

while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: ldcBuild.sh [--help] [--xf /path/to/xf]"
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

        *)
            die "Unknown parameter '$1'."
            break
            ;;
    esac
    shift
done

sed -e "s|\.\.|$xf|" modList.lst | xargs ldc -g -L=-ltango-user-ldc -of=xfbuild

