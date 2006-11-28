#!/bin/sh

find . -type f -name \*.rb | xargs cat | grep -v "^ *$"|grep -v "^ *#"|grep -v "^ *end *$"|wc -l
