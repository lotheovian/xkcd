#!/bin/bash

function getComic() {
   NUM_TO_GET=$1
   COMIC_URL=$(curl https://xkcd.com/${NUM_TO_GET}/ 2> /dev/null | grep "Image URL (for hotlinking/embedding):" | sed "s/.*embedding):\(.*\)/\1/")
   COMIC_NAME=${COMIC_URL##*\/}
   echo "fetching comic ${NUM_TO_GET}:${COMIC_NAME%.*}"
   curl -o ${XKCD_DIR}/${NUM_TO_GET}_${COMIC_NAME} ${COMIC_URL} 2> /dev/null &
   let COMICS_FETCHED++
   [ "$COMICS_FETCHED" -le 5 ] && COMIC_URLS_FETCHED+="${COMIC_URL} "
}

function makeMailHeader() {
cat <<EOF
From: ${FROM_EMAIL}
Subject: The Daily Lolz
Mime-Version: 1.0
Content-Type: text/html

<html>
<body>
EOF
}

function isExcluded() {
   case ${1} in
        404) return 0;;  #Because 404
        1037) return 0;; #Because it doesn't have a link for whatever reason.
        1608) return 0;; #Because it's an awesome game 
        1663) return 0;; #Because it's not an image 
   esac
   return 1
}

COMIC_URLS_FETCHED=""
COMICS_FETCHED=0

XKCD_DIR="$(echo ~/Documents/xkcd/)"
XKCD_CONFIG="$(echo ~/Documents/xkcd_config)"
if [ ! -f $XKCD_CONFIG ]
then echo please make a config file with a FROM_EMAIL and MAILING_LIST in the file $XKCD_CONFIG
     exit 1
fi
source $XKCD_CONFIG
if [ -z "$FROM_EMAIL" ]
then echo please specific a FROM_EMAIL in $XKCD_CONFIG
     exit 1
fi
if [ -z "$MAILING_LIST" ]
then echo please specific a MAILING_LIST in $XKCD_CONFIG
     exit 1
fi

mkdir -p ${XKCD_DIR}
COMIC_COUNT="$(find ${XKCD_DIR} -maxdepth 1 -type f|wc -l|tr -d ' ')"
CURRENT_COMIC="$(curl https://xkcd.com 2> /dev/null | sed -e '/Permanent link to this comic:/!d;s/.*https\{0,1\}:\/\/xkcd.com\/\([0-9]*\)\/.*/\1/')"
printf "You currently have %s/%s (%s%%) xkcd comics.\n" ${COMIC_COUNT} ${CURRENT_COMIC} $((100*${COMIC_COUNT}/${CURRENT_COMIC}))

#Fetch new Comics
for COMIC_NUM in $(seq 1 ${CURRENT_COMIC})
do #Excludes
   isExcluded ${COMIC_NUM} && continue
   if ! compgen -G "${XKCD_DIR}/${COMIC_NUM}_*" &> /dev/null
   then getComic ${COMIC_NUM}
   fi
done

#Send out our daily lolz email
TMP="$(mktemp /tmp/XXXXX)"
makeMailHeader > ${TMP}

if [ "${COMICS_FETCHED}" != 0 ] # Send out the latest stuff
then for COMIC in ${COMIC_URLS_FETCHED}
     do printf "<br>Click <a href=\"%s\">here</a> for the comic.\n" "${COMIC}" >> $TMP
        printf "<br>Click <a href=\"%s\">here</a> for the explanation.\n" "https://www.explainxkcd.com/wiki/index.php/${COMIC##*/}" >> $TMP
        printf "<img src=\"%s\">" ${COMIC} >> $TMP
     done
else # Or pick 5 random comics   
     for RAND_COMIC in $(jot -r 5 1 $CURRENT_COMIC)
     do isExcluded ${RAND_COMIC} && continue
        RAND_COMIC_URL=$(curl https://xkcd.com/${RAND_COMIC}/ 2> /dev/null | grep "Image URL (for hotlinking/embedding):" | sed "s/.*embedding):\(.*\)/\1/")
        printf "<br>Click <a href=\"%s\">here</a> for the comic.\n" "https://xkcd.com/${RAND_COMIC}/" >> $TMP
        printf "<br>Click <a href=\"%s\">here</a> for the explanation.\n" "https://www.explainxkcd.com/wiki/index.php/${RAND_COMIC}" >> $TMP
        printf "<img src=\"%s\">\n" ${RAND_COMIC_URL} >> $TMP
     done
fi
printf "</body>\n</html>\n" >> $TMP
cat $TMP | sendmail "${MAILING_LIST}" # Send it
