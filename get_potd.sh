#!/bin/bash

[ ! -d /srv/incoming ] && exit 1

# script to grab picture of the day from
# * wikipedia (en) 
# * commons.wikimedia
# by Nemo Thorx <wombat@nemo.house.cx>. 2012
#
# If you care, call this GPL v2

# I run this from cron, multiple times for a given month, to catch updates and fixed failed
    # picture of the day archives... 
    # 0 4     1 * *   /home/nemo/bin/get_potd.sh $(date -d 'now -1 months' "+\%Y \%m")
    # 0 4     8 * *   /home/nemo/bin/get_potd.sh $(date -d 'now -2 months' "+\%Y \%m")
    # 0 4     15  * * /home/nemo/bin/get_potd.sh
    # 0 4     29  * * /home/nemo/bin/get_potd.sh $(date -d 'now -12 months' "+\%Y \%m")
    #

# nagios settings
host=$(hostname)
service="get_potd"
nagiosfifo=/var/lib/nagios3/rw/nagios.cmd
nagiosfifo=/dev/null
NSCA_SVR=falcon.house.zz
nagcode=3        # 0 = OK, 1 = Warning, 2 = Critical, 3 = Unknown

LOGFILE=$HOME/var/log/potd.log
YEAR=$1
MONTH=$2

LOGTAG=""	    # tag each log line for a given message with this. 

# if these not set, we should assume the current month... 

[ -z $YEAR ] && YEAR=$(date +%Y)
[ -z $MONTH ] && MONTH=$(date +%m)


do_log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") $LOGTAG $1" >> $LOGFILE
}

tell_nagios() {
        code=$1
        shift
        if [ $code -eq 0 ]; then
                output="OK - $@"
        elif [ $code -eq 1 ]; then
                output="WARNING - $@"
        elif [ $code -eq 2 ]; then
                output="CRITICAL - $@"
        else
                code=3
                output="UNKNOWN - $@"
        fi
#    echo "[$(date +%s)] PROCESS_SERVICE_CHECK_RESULT;$host;$service;$code;$output" > $nagiosfifo
        echo -e "${host}\t${service}\t${code}\t${output}" | /usr/sbin/send_nsca -H $NSCA_SVR  >/dev/null
}

mk_logtag() {
    LOGTAG=$(echo $1 | md5sum | cut -c 1-5 | tr -d "\n")
}


# this function is given two parameters. 
# $1 is a URL to get
# $2 is a local /path/to/file to save it to. 
do_webget() {
    url=$1
    outdir=$2
    outfilesize=0
    [ -t 1 ] && echo "… $url to $outdir"
    
    # get the file by urldecoding the link, and grabbing the last bit
    POTDTITLETMP=$(echo "$POTDLINK" | sed -n -e's/%\([0-9A-F][0-9A-F]\)/\\x\1/g' -e's/\(+\|_\)/ /g' -ep | xargs -0 echo -en )
    POTDFILE=${POTDTITLETMP##*/}
    outfile="$outdir/$POTDFILE"

    headers=$(curl -s --head $url | tr -d "\015")
    urllastmod=$(date -d "$(echo "$headers" | awk -F": " '{ if ($1 == "Last-Modified") print $2}')" +%s)
    urlsize=$(echo -e "$headers" | awk -F": " '{ if ($1 == "Content-Length") print $2}')
    urltimestamp=$(echo "$headers" | awk -F": " '{ if ($1 == "X-Timestamp") print $2}')

    urllastmod_h=$(date -d @$urllastmod +%Y-%m-%dT%H:%M:%S)
    do_log "… request URL size: $urlsize, lastmod: $urllastmod_h for $url"

    if [ -e "${outfile}" ] ; then
	# already have a file. Let's work out if we should do anything more
	outfilestats=$(stat "${outfile}" -c "%s %Y")	# size in bytes, modtime in seconds from epoch
	outfilesize=${outfilestats% *}
	outfilelastmod=${outfilestats#* }
	outfilelastmod_h=$(date -d @$outfilelastmod +%Y-%m-%dT%H:%M:%S)
	do_log "…  have local size: $outfilesize, lastmod: $outfilelastmod_h for $outfile"
    fi

    if [ $urlsize -gt $outfilesize ] ; then
	# new online file is bigger than what we have (or dont have). Get it!
	do_log "> getting URL (size: $urlsize) for $outfile"
	# TODO: wget to a temporary file which CAN be touched to the correct stamp, and then overwrite the previous :)
	(wget -N "${url}" -O "${outfile}" && echo "${outfile}" | tr "\n" "\0" | xargs -0 touch -d ${urllastmod_h} && do_log "+ Saved to $outfile" ) || do_log "! Fail on ${url} to ${outfile}"
    elif [ $urlsize -lt $outfilesize ] ; then
	# wtf, online file is smaller?
	do_log "! wtf, URL version smaller ($urlsize) than local $outfile ($outfilesize)"
    else
	# they're the SAME SIZE!
	do_log "_ ignoring URL (same size as local file)"
	if [ $urllastmod -lt $outfilelastmod ] ; then
	    echo "${outfile}" | tr "\n" "\0" | xargs -0 touch -d ${urllastmod_h} 
	    [ $? -eq 0 ] && do_log "~ retouched $outfile from $outfilelastmod_h to $urllastmod_h" || do_log "! attempted retouchy of $outfile to $urllastmod_h, but something error blargle"
	fi
    fi
}

# TODO: 
# * clean up commonspotd below
# * add in national geographic POTD?

do_commonspotd() {
    TDIR="/srv/Images/WikiPOTD/Commons/$YEAR-$MONTH"
    mkdir -p "$TDIR"
    cd  "$TDIR" 
    MINDEXPAGE="https://commons.wikimedia.org/wiki/Template:Potd/$YEAR-$MONTH"
    LOGTAG="----"
    do_log "# Processing commons for $YEAR $MONTH: $MINDEXPAGE"
    MINDEX=$(curl -s -S $MINDEXPAGE)
    DINDEX=$(echo "$MINDEX" | sed -n 's/.*magnify.*\(wiki\/File:.*\)" class.*/\1/p')
    echo "$DINDEX" | while read DAY ; do
       # echo "found $DAY, here is the image URL"
	POTDURL="https://commons.wikimedia.org/$DAY"
	mk_logtag $POTDURL
	do_log ": $POTDURL"
	POTDSRC=$(curl -s -S $POTDURL)
	POTDLINK=https:$(echo "$POTDSRC"| sed -n 's/.*fullMedia.*\(\/\/.*\)" class.*/\1/p')
	do_log ": $POTDLINK"
	if $(echo "$POTDLINK" | egrep -q "\.(og.|webm)$"); then
	    do_log "_ ignoring URL (Media of the Day)"
	elif $(echo "$POTDLINK" | egrep -q "/No.image\.svg$"); then
	    do_log "_ ignoring URL (No image.svg)"
	elif $(echo "$POTDLINK" | egrep -q "/Audio-card\.svg$"); then
	    do_log "_ ignoring URL (Audio-card.svg)"
	else
	    do_webget "$POTDLINK" "$TDIR"
	fi
    done
}


do_enwikipotd() {
    TDIR="/srv/Images/WikiPOTD/enwiki/$YEAR-$MONTH"
    mkdir -p "$TDIR"
    cd "$TDIR"
    LMONTH=$(date -d "$YEAR-$MONTH-01" +%B)
    MINDEXPAGE="https://en.wikipedia.org/wiki/Wikipedia:Picture_of_the_day/${LMONTH}_${YEAR}"
    LOGTAG="----"
    do_log "# Processing enwiki for $YEAR $MONTH: $MINDEXPAGE"
    MINDEX=$(curl -s -S $MINDEXPAGE)
    DINDEX=$(echo "$MINDEX" | sed -n 's/.*\/\(wiki.*\)\" class=.image.*/\1/p')
    echo "$DINDEX" | while read DAY ; do
#       echo "found $DAY, here is the image URL"
	POTDURL="https://en.wikipedia.org/$DAY"
	mk_logtag $POTDURL
	do_log ": $POTDURL"
	POTDSRC=https:$(curl -s -S $POTDURL)
	POTDLINK=https:$(echo "$POTDSRC" | sed -n 's/.*fullMedia.*\(\/\/.*\)" class.*/\1/p')
	do_log ": $POTDLINK"
	if $(echo "$POTDLINK" | egrep -q ".(og.|webm)$"); then
	    do_log "_ ignoring it as Media of the Day"
	elif $(echo "$POTDLINK" | egrep -q "/No.image\.svg$"); then
	    do_log "_ ignoring it as No image"
	else
	    [ -t 0 ] && echo "$POTDLINK"
	    do_webget "$POTDLINK" "$TDIR"
	fi
    done
}


cd /srv/Images/WikiPOTD/
startdu=$(du -sk */$YEAR-$MONTH/ 2>/dev/null | tr "\n" "\t")
startdutot=$(du -skc */$YEAR-$MONTH/ 2>/dev/null | tail -1 | cut -f 1)
starttime=$(date +%s)

do_commonspotd
do_enwikipotd

cd /srv/Images/WikiPOTD/
enddu=$(du -sk */$YEAR-$MONTH/ 2>/dev/null | tr "\n" "\t")
enddutot=$(du -skc */$YEAR-$MONTH/ 2>/dev/null | tail -1 | cut -f 1)
duration=$(($(date +%s)-$starttime))
do_log "$(tree -f */$YEAR-$MONTH/ | tail -1)"
do_log "was: $startdu (total: $startdutot)"
do_log "now: $enddu (total: $enddutot)"
do_log "duration: $duration seconds"

dudiff=$(($enddutot-$startdutot ))
rate=$(($dudiff/$duration))

logwtf=$( grep -c "$(date +"%Y-%m-%d") ..... . wtf" $LOGFILE )
logfail=$( grep -c "$(date +"%Y-%m-%d") ..... . wtf" $LOGFILE )


# warning if the total data is small (less than 100meg total), or the whole run was fast (less than 3 min). or any logged wtf/fails
# ...both small/fast are possible on a legit month, but rare. 
# (less than 100meg was common in 2004-2007, never since)
nagcode=0   # we made it this far. good. 
if [ $enddutot -lt 100000 ] || [ $duration -lt 180 ] || [ $logwtf -gt 0 ] ; then
	nagcode=1
fi
# critical if crazy small/fast
# (less than 30 meg occured a few times in 2004, and once in 2005)
if [ $enddutot -lt 30000 ] || [ $duration -lt 60 ] || [ $logfail -gt 0 ] ; then
	nagcode=2
fi
tell_nagios $nagcode "Got ${dudiff}k in $duration seconds (${rate}k/sec). $YEAR-$MONTH is now ${enddutot}k total size. Logs: $logwtf wtf, $logfail fails"

# find errors
errors=$(grep "$(date +"%Y-%m-%d") ..:..:.. .... \!" $LOGFILE)

if [ -t 1 ] ; then
#    echo "$errors" 
    echo ""
else
    if [ -n "$errors" ] ; then
    # parse each error line, pull out the filename being attempted, then grep that whole name out of the log - so I get every part leading up to the error
	echo "$errors" | while read DATE TIME TAG FLAG ERROR ; do
	    # At terminal, terse (non terminal is assumed to be captured by cron)
	    grep " $TAG " $LOGFILE
	done
    fi 
fi
