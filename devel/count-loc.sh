#!/bin/sh

egrep ".rb$"  Manifest.txt | xargs cat | grep -v "^ *$"|grep -v "^ *#"|grep -v "^ *end *$"|wc -l
