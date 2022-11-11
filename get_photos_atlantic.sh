#!/bin/bash

# The Atlantic's photo galleries begun at
# https://www.theatlantic.com/photo/2011/02/
# ...Picture Of The Week galleries begun in 2014/05


# This is a script to scrape those galleries:
# - saving high quality images
# - generating readable markdown for captions and credits



mainlog=$HOME/var/log/photos_atlantic.log
YEAR=$1
MONTH=$2
reportflag=$3

basedir=/srv/Images/AtlanticPhotos


LOGTAG=" "           # tag each log line for a given message with this.
do_log() {
    # if we're fed params, then echo that into ourselves
    if [ -n "$1" ] ; then
        echo $@ | do_log
    else
        # no param so assume stdin.
        # This logs per-line the output of other programs with multiline output
        cat /dev/stdin | while read line ; do
            if [ -t 1 ] ; then
                echo "$(date +"%FT%T")${LOGTAG}${line}" | tee -a $mainlog
            else
                echo "$(date +"%FT%T")${LOGTAG}${line}" >> $mainlog
            fi
        done
    fi
}

do_logcmd() {
    # logcmd logs a command to be run, then runs it
    # note: if command has a password, it could be __REDACTED__ here if known
    # eg, by piping through this before dolog: sed -e "s/$pw/__REDACTED__/g" 
    echo "$ $@" | do_log
    echo "$@" | bash 2>&1 | do_log
    #TODO: would be neat if this could detect non-zero exit and log to suit. 
    # ...but I think the pipe into do_log eats that. Test and solve?
}


# if these not set, we should assume the current month 

[ -z $YEAR ] && YEAR=$(date +%Y)
[ -z $MONTH ] && MONTH=$(date +%m)


################################################## MAIN
# 

# TODO: 
# - would be cool to have matching -gethtmlonly and -processhtml options
# - or maybe even to be smart, note the process steps are
#   monthhtml -> galleryhtml -> markdown -> images
# ..and have options like
#       * "endafter(monthhtml|galleryhtml|markdown)"
#           or "endbefore(galleryhtml|markdown|images)
#       * "startafter(monthhtml|galleryhtml|markdown)
#           or "startbefore(galleryhtml|markdown|images)
#   and "startwithhtml <path/to/specific.html>"
# .....though it seems a lot of work for rare use. debugging good tho?


monthdir="${basedir}/$YEAR/$MONTH"

    # TODO: make this better (currently goes to cron email)
if [ -n "$reportflag" ] ; then
    dirstats.sh $monthdir
    exit
fi






do_log "# Retrieving photos from the atlantic for $YEAR/$MONTH"

baseurl="https://www.theatlantic.com"

monthurl="${baseurl}/photo/$YEAR/$MONTH/"
do_logcmd "mkdir -pv $monthdir"
do_log ": $monthurl"
curl -S -s -D - "$monthurl" > $monthdir/${YEAR}-${MONTH}.html
do_logcmd "ls -l $monthdir/${YEAR}-${MONTH}.html"

allinmonth=$(cat $monthdir/${YEAR}-${MONTH}.html | grep "a data-omni-click=.inherit. href=./photo/$YEAR/$MONTH/" | cut -d'"' -f 4)
# TODO: save this allinmonth html to disk too

for link in $allinmonth ; do
    groupurl="${baseurl}${link}"
    do_log ": Processing $groupurl"
    groupdir=$basedir/$YEAR/$MONTH/$(echo "$groupurl" | cut -d/ -f 7)
#    do_log "+ creating: $groupdir"
    do_logcmd "mkdir -pv \"$groupdir\""
    cd "$groupdir"

    # get the URL and process it into markdown - which will be mostly the final
    # version but will have ALL image URLs within it. 
    #
    # We then do a second round of processing to obtain actual images and
    # finalise the markdown
    curl -S -s -D - "$groupurl"  > $groupdir/original.html
    do_logcmd "ls -l $groupdir/original.html"
#    continue        # TODO: this should be triggered by a "gethtmlonly" flag or
    do_log ": Processing original.html into tmp.md"

    cat $groupdir/original.html | awk -v URL="$groupurl" -v firstimg="waiting" -F'"' '

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
    ' | sed -e 's/\xC2\xA0/ /g' > tmp.md
    # above sed converts nonbreaking whitespace into regular space
    # ...it otherwise screws up `recode html..utf8` (even though that's been replaced by python)

    # the filename we want for our final markdown is going to be the directory the images are in, and we can now calculate that
    # original URLs are all in a path that includes "thumbor" so we're keying from that
    mdfile=$(cat tmp.md | grep thumbor | cut -d/ -f 12 | head -1).md
    do_log ": Processing tmp.md into $mdfile +image downloads"

#    cat tmp.md | recode html..utf8 | while read line ; do 
#    ...recode was catching too much stuff and causing errors. 
#       eg: turning  "Australia’s" into "Australiaâ  s"
#       see: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=748984 
#       workaround that works: | recode -d utf8..html | recode html..utf8
#    ...but this python does the right thing and isn't working around bugs. so:
    cat tmp.md | python3 -c 'import html,sys; print(html.unescape(sys.stdin.read()), end="")' | while read line ; do 
        case $line in
            *thumbor*)
                imgurl=$line
                imgtype=${imgurl##*.}
                imgname=$(echo "$imgurl" | cut -d/ -f 13)
                # TODO: imgname should be whatever matches the last string before original.suffix
                #   ...because in some gif cases, it's the 12th, not 13th
                #   /path/blah/etc/uniquename/original.sfx
                imgfinal="$imgname.$imgtype"
                do_log "> $imgurl"
                # these have no accurate mtime from http headers, so -O is OK
                do_logcmd "wget -nc -nv \"$imgurl\" -O $imgfinal"

                # note: this identify will exit1 if there are errors
                # ...however, I don't know if that exitcode travels back all the way to here
                # TODO: find that out. retry/log/whatever if it does
                do_log ": $(identify -regard-warnings $imgfinal)"
                
                # this is what embedded images in markdown look like 
                # note: no alt text since we've turned that into the header
                # for each block
                echo "!($imgfinal)" >> $mdfile
                ;;
            *)
                echo "$line" >> $mdfile
                ;;
        esac
    done

    wc -l $mdfile
    do_logcmd "ls -l $mdfile"
    # TODO: sanity checks:
    # * image download count vs images mentioned in markdown
    # * images are complete (imagemagick has some verify option)
    # rm tmp.md

#    sleep $((RANDOM%5+3)) # sleep for 3/4/5/6/7 seconds before looping to the next gallery
    sleep $((RANDOM%3+1)) # sleep for 2/3/4 seconds before looping

done

# TODO: some post-analysis of what has been gotten
# ...for logs and also maybe for send2pushover ?
