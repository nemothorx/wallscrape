#!/bin/bash

echo "Retrieving weekly photos from the atlantic"

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


# from #datahoarder  2017/dev/07
# 23:58 < tammy_> earthnative: https://paste.ubuntu.com/26132768/

# 0  5    * * 3   bkps    /poolsclosed/stuff/images/scripts/weekly_the_atlantic.sh
#
# can find older photo of the week pages within YYYY/MM pages starting here:
# https://www.theatlantic.com/photo/2011/02/
# ...noting that that's ALL photo pages, POTW specific started in 2015/05


