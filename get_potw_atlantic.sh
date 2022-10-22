#!/bin/bash

LOGFILE=$HOME/var/log/potw_atlantic.log
YEAR=$1
MONTH=$2

basedir=/srv/Images/AtlanticPOTW

LOGTAG=""           # tag each log line for a given message with this. 

# if these not set, we should assume the current month... 

[ -z $YEAR ] && YEAR=$(date +%Y)
[ -z $MONTH ] && MONTH=$(date +%m)


echo "Retrieving weekly photos from the atlantic for $YEAR/$MONTH"

baseurl="https://www.theatlantic.com"

monthurl="${baseurl}/photo/$YEAR/$MONTH/"
echo ": $monthurl"
allinmonth=$(curl -S -s "$monthurl" | grep "a data-omni-click=.inherit. href=./photo/$YEAR/$MONTH/" | cut -d'"' -f 4)

for link in $allinmonth ; do
    groupurl="${baseurl}${link}"
    echo ": $groupurl"
    groupdir=$basedir/$YEAR/$MONTH/$(echo "$groupurl" | cut -d/ -f 7)
    echo "> $groupdir"
    mkdir -p "$groupdir"
    cd "$groupdir"

    # get the URL and process it into markdown
    # ...this file will be mostly the final version, but we'll do a second round of processing to obtain the actual images
    curl -S -s "$groupurl" | awk -v URL="$groupurl" -v firstimg="waiting" -F'"' '

# Obtain the html title
/<title>/ {
    gsub(/ *<[^>]+> */," ",$0) 
    {print "# "$0""}
} 

# Obtain the article text. Expected to be one line since this is mostly about images
    # First, identify the tags that start and end the article
    # note: credits (img and page) are also in div, so ends the same way
/article-content/ { contentcredit="content" }  
/div>/ { contentcredit="done" }

    # And here we print the article text itself (removing leading spaces)
{ if ( contentcredit=="content" ) {
    gsub(/ *<[^>]+> */,"",$0) 
        print $0
    }
}

# There are multiples of each image. We capture the first and flag to ignore the rest (assumption is an ordering of best to worst resolution per image)
{ if ( /source data-srcset/ && firstimg=="waiting" ){
    imgurl=$2
    firstimg="done"
    }
}

    # unset the flag when we identify the last image
    # ...and capture the alt-text which is on this match
/img data-src.*lazyload/ {
    alttxt=$4
    firstimg="waiting"
}
    
# Get the description of the image. This is the proper info that appears in a normally rendered page, not the alt-text for the image itself
/<span>.*<\/span>$/ {
    gsub(/ *<[^>]+> */,"",$0) 
    imgtxt=$0
}
    
# For each image, we need to identify the photographer credit too
    # also set a flag for the multiline image block we output after this step
/div class=.credit/  {
    contentcredit="credit"
    finaliseimage="true"
}
{ if ( contentcredit=="credit" ) {
        gsub(/ *<[^>]+> */,"",$0) 
        gsub(/^[ \t]+/,"",$0) 
        credittxt=credittxt""$0
    }
}

# ...this is where we print EVERYTHING gathered for an image block
# imgurl line will be re-processed in stage two
{ if ( contentcredit!="credit" && finaliseimage=="true") {
    print "\n----"
    print "## "alttxt
    print "\n"""imgurl
    print "\n"imgtxt
    print "\n> "credittxt
    finaliseimage="false"
    credittxt=""
    }
}

# Finally, the end of the page for overall credit and cite
/c-footer__copyright/ { contentcredit="footer" }  
    # And here we print the article credit (the footer) itself
{ if ( contentcredit=="footer" ) {
        gsub(/ *<[^>]+> */," ",$0) 
        gsub(/^[ \t]+/," ",$0) 
        footertxt=footertxt""$0
    }
}

END {
    print "\n----"
    print "###" footertxt
    print ""
    print "- Processed from: "URL
}
    ' > tmp.md

    # the filename we want for our final markdown is going to be the directory the images are in, and we can now calculate that
    # original URLs are all in a path that includes "thumbor" so we're keying from that
    mdfile=$(cat tmp.md | grep thumbor | cut -d/ -f 12 | head -1).md
    echo ": Processing tmp to make $mdfile"

    cat tmp.md | while read line ; do 
        case $line in
            *thumbor*)
                imgurl=$line
                imgtype=${imgurl##*.}
                imgname=$(echo "$imgurl" | cut -d/ -f 13)
                imgfinal="$imgname.$imgtype"
                echo "> $imgurl -> $imgfinal"
                # these have no accurate mtime from http headers, so -O is OK
                wget -nv "$imgurl" -O $imgfinal
                echo "!($imgfinal)" >> $mdfile
                sleep 1
                ;;
            *)
                echo "$line" >> $mdfile
                ;;
        esac
    done

    wc -l $mdfile
    rm tmp.md

    sleep 5

    # TODO: parse that mid-stage markdown for images-to-download and create final markdown
    # ...images embedded or linked?

done

exit 5



# notes from 2020-05:
    # they changed from /w to /a in the last week of 2020 04
    # ...Unless it's a history thing? (written in first week of 2020 05)
#    curl -s -S $weekurl | grep jpg | grep "/[aw][0123]"
    # captions to be trawled... `grep -B1 "#img"`
    # name it something sane... based on the caption??

   

    # logging... grab from the get_potd.log stuff. 
    # ...perhaps fold this into that??


#
# can find older photo of the week pages within YYYY/MM pages starting here:
# https://www.theatlantic.com/photo/2011/02/
# ...noting that that's ALL photo pages, POTW specific started in 2014/05


