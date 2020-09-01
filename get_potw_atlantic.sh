#!/bin/bash

LOGFILE=$HOME/var/log/potw_atlantic.log
YEAR=$1
MONTH=$2

LOGTAG=""           # tag each log line for a given message with this. 

# if these not set, we should assume the current month... 

[ -z $YEAR ] && YEAR=$(date +%Y)
[ -z $MONTH ] && MONTH=$(date +%m)


echo "Retrieving weekly photos from the atlantic for $YEAR/$MONTH"

baseurl="https://www.theatlantic.com"

allthismonths=$(curl -S -s ${baseurl}/photo/$YEAR/$MONTH/ | grep -Po '"/photo/.*photos-of-the-week.*" ' | grep $YEAR/$MONTH | tr -d '"' | sort | uniq)

for week in $allthismonths ; do
    weekurl="${baseurl}${week}"
    echo ": $weekurl"
    # they changed from /w to /a in the last week of 2020 04
    # ...Unless it's a history thing? (written in first week of 2020 05)
    curl -s -S $weekurl | grep jpg | grep "/[aw][0123]"
    # captions to be trawled... `grep -B1 "#img"`
    # name it something sane... based on the caption??

    # logging... grab from the get_potd.log stuff. 
    # ...perhaps fold this into that??
done



# 
exit 1
# below here is the original draft, circa 2017 or something. Above based on this, more or less

url=$(curl -sS "https://www.theatlantic.com/photo/" | grep -Po '".*?"' | grep "photos-of-the-week-" | grep -v https | head -n 1 | sed -s 's/\"//g')
photos=$(curl -sS https://www.theatlantic.com$url | grep main_1500.jpg | sed -s "s_.*data-share-image=\"\(.*\)\".*_\1_g" | grep -v "<" | sort | uniq)
folder=/shared/Images/AtlanticPOTW/$(date +%F)/
mkdir -p $folder
cd $folder
count=0

while read -r line; do
    wget -nv "$line" -O image$count.jpg
    count=$((count+1))
    sleep $(($RANDOM%5+1))  # random sleep between 1 and 5 seconds
done <<< "$photos"

echo "$count files written!"


# from #datahoarder  2017/dec?/07
# 23:58 < tammy_> earthnative: https://paste.ubuntu.com/26132768/

# 0  5    * * 3   bkps    /poolsclosed/stuff/images/scripts/weekly_the_atlantic.sh
#
# can find older photo of the week pages within YYYY/MM pages starting here:
# https://www.theatlantic.com/photo/2011/02/
# ...noting that that's ALL photo pages, POTW specific started in 2014/05


