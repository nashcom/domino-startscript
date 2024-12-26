#!/bin/bash

# Generate Domino Download Server software list

# Remote server URL can be set to point to another server.
# SERVER_URL=
TABLE_STYLE=1


if [ "$CATALOG_BROSWING" = "no" ]; then
  exit 0
fi


if [ -z "$CATELOG_MAX_AGE_SEC" ]; then
  CATELOG_MAX_AGE_SEC=120
fi


INDEX_FILE=index.html
TARGET_DIR="/local/software"
HTML_DIR="$TARGET_DIR/html.update"

CATALOG_FILE="$TARGET_DIR/catalog.list"
CATALOG_JSON="$TARGET_DIR/catalog.json"
CATALOG_TEMP="$TARGET_DIR/catalog.tmp"


if [ "$1" = "-v" ]; then
  LOG_LEVEL=1
fi


LogTrace()
{
  if [ -z "$LOG_LEVEL" ]; then
    return 0
  fi

  echo "[$(printf "%02d" "$SECONDS")] $@"
}


html_begin()
{
  local FILE="$HTML_DIR/$1"

  if [ -z "$1" ]; then
    return 0
  fi

  if [ "$TABLE_STYLE" = "1" ]; then

    echo "<html><head><style>body {font-family: Arial, sans-serif;} .header {padding: 2px; padding-left: 20px; text-align: left; background: #000000; color: white; font-size: 20px;} table {border-collapse: collapse; width: 100%;} .c1 {width: 20%;} .c2 {width: 40%;} .c3 {width: 40%} .hash {font-family: 'Courier';} th, td {text-align: left; padding: 8px;} tr:nth-child(even) {background-color: #f2f2f2;} a.links:link {text-decoration: none; color:#0F52BA;} a.links:visited {text-decoration: none; color:#0F52BA;} a.links:hover {text-decoration: none; color:#0F52BA; font-weight: bold;} </style>" > "$FILE"
    echo "<title>$2</title></head><body> <div class=\"header\"><h1>$2</h1></div><br><table>" >> "$FILE"
    echo "<tr> <th class=\"c1\">$3</th> <th class=\"c2\">$4</th> <th class=\"c3\">$5</th> </tr>" >> "$FILE"

  else
    echo "<html><head><style>body {font-family: Arial, sans-serif;}</style><title>$2</title></head><body><h1>< <div class=\"header\"><h1>$2</h1></div>/h1><br>" > "$FILE"
  fi
}


html_end()
{
  local FILE="$HTML_DIR/$1"

  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$FILE" ]; then
    return 0
  fi

  if [ "$TABLE_STYLE" = "1" ]; then
    echo "<br></table></body></html>" >> "$FILE"
  else
    echo "<br></body></html>" >> "$FILE"
  fi
}


html_entry()
{
  local FILE="$HTML_DIR/$1"
	
  local LINK="$2"
  local TEXT="$3"
  local DESCRIPTION="$4"
  local HASH="$5"

  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$FILE" ]; then
    return 0
  fi

  if [ -n "$6" ]; then
    LINK="$6/$2"
  fi

  if [ -z "$TEXT" ]; then
    TEXT="$LINK"
  fi

  if [ "$TABLE_STYLE" = "1" ]; then

    echo "<tr> <td class=\"c1\"> <a class=\"links\" href=\"$LINK\">$TEXT</a> </td> <td class=\"c3\"> $DESCRIPTION </td> <td class=\"c3\"> <span class=\"hash\">$HASH</span> </td> </tr>" >> "$FILE"

  else

    if [ -z "$DESCRIPTION" ]; then
      echo "<a href=\"$LINK\">$TEXT</a><br>" >> "$FILE"
    else
      echo "<a href=\"$LINK\">$TEXT</a> $DESCRIPTION<br>" >> "$FILE"
    fi

  fi
}


check_file_older()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  local now=$(date +%s)
  local modified=$(date -r "$1" "+%s")
  local delta=$((now-modified))

  LogTrace "[$1] modified $delta seconds ago"

  if [ "$delta" -lt "$2" ]; then
    LogTrace "[$1] File still valid -> Skipping update"
    exit 0
  fi
}


check_file_smaller()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  local FILESIZE=$(stat -c%s "$1")

  LogTrace "[$1] file size (bytes): $FILESIZE"

  if [ "$FILESIZE" -lt "$2" ]; then
    LogTrace "[$1] file size too small -- Can't be valid -> Skipping update"
    exit 0
  fi
}


# --- Main ---

# Skip if MHS catalog data is still younger then max age
check_file_older "$CATALOG_JSON" "$CATELOG_MAX_AGE_SEC" 

# If file is too small (32k), this isn't a valid JSON file
check_file_smaller "$CATALOG_JSON" 32768

# Touch file to lower the risk of race conditions for parallel requests
touch "$CATALOG_JSON"

LogTrace "Reading $CATALOG_JSON"
curl -sL https://my.hcltechsw.com/files/domino | jq .files[] > "$CATALOG_JSON"


LogTrace "Generating $CATALOG_FILE"

cat "$CATALOG_JSON"| jq -r '.locations[0] + "|" + .name + "|" + .description  + "|" + .checksums.sha256'  | sort -V | cut -d'/' -f2- > "$CATALOG_TEMP"

# Exclude software, which should not be listed
cat "$CATALOG_TEMP" | grep -v -e "12.0.1" -e "IBMi" -e "verse" -e "mobile" -e "voltscript" -e "appdev/" -e "caa/" -e "dlau/" -e "domino/11" -e "notes/11" -e "ccm/" -e "htmo/" -e "hei/11" -e "traveler/apnscerts" -e ".pdf" -e ".txt"  -e "consap/" -e "Early Access May 2023" -e "Early Access July 2023" -e "Early Access October 2023" -e "Early Access Sept 2024" -e "Early Access Dec 2024" > "$CATALOG_FILE"

rm -f "$CATALOG_TEMP"
LogTrace "Catalog entries generated: $(cat "$CATALOG_FILE" | wc -l | xargs)"



# Create4 temporary directory to store HTML files
mkdir -p "$HTML_DIR"

CATEGORY_TOP=$(cat "$CATALOG_FILE" | cut -f1 -d'/' | uniq)
CATEGORY_SUB=$(cat "$CATALOG_FILE" | cut -f1 -d'|' | uniq)

LogTrace "Generating $INDEX_FILE"

html_begin "$INDEX_FILE" "Domino Download Server" "Category"

for CATEGORY in $CATEGORY_TOP
do
  html_entry "$INDEX_FILE" "$CATEGORY.html" "$CATEGORY"
done

html_end "$INDEX_FILE"

LogTrace "Generating top categories"

for CATEGORY in $CATEGORY_TOP
do
  html_begin "$CATEGORY.html" "$CATEGORY" "Category"
done

for ENTRY in $CATEGORY_SUB
do
  CATEGORY=$(echo "$ENTRY" | cut -d'/' -f1)
  SUB=$(echo "$ENTRY" | cut -d'/' -f2)
  COMBINED=${CATEGORY}_${SUB}

  LogTrace "Generating: $COMBINED"

  html_entry "${CATEGORY}.html" "$COMBINED.html" "$SUB"
  html_begin "$COMBINED.html" "$CATEGORY $SUB" "File" "Description" "Hash"
done

LogTrace "Generating sub categories"

for CATEGORY in $CATEGORY_TOP
do
  html_end "$CATEGORY.html"
done

COUNT=0
COUNT_ENTRIES=$(cat "$CATALOG_FILE" | wc -l | xargs)
DONE_SECONDS=$SECONDS

LogTrace "Adding $COUNT_ENTRIES entries ..."

while read LINE; do

  ENTRY=$(echo "$LINE" | cut -d'|' -f1)
  CATEGORY=$(echo "$ENTRY" | cut -d'/' -f1)
  SUB=$(echo "$ENTRY" | cut -d'/' -f2)
  COMBINED=${CATEGORY}_${SUB}
  FILE=$(echo "$LINE" | cut -d'|' -f2)
  DESCRIPTION=$(echo "$LINE" | cut -d'|' -f3)
  HASH=$(echo "$LINE" | cut -d'|' -f4)

  html_entry "$COMBINED.html" "$FILE" "$FILE" "$DESCRIPTION" "$HASH" "$SERVER_URL"

  COUNT=$(expr $COUNT + 1)

  # Log every two seconds
  if [ -n "$LOG_LEVEL" ]; then
    if [ $(expr $SECONDS % 2) -eq 0 ]; then
      if [ "$DONE_SECONDS" != "$SECONDS" ]; then
        DONE_SECONDS=$SECONDS
        LogTrace "$(printf "%03d" "$COUNT") done"
      fi
    fi
  fi

done < "$CATALOG_FILE"

for ENTRY in $CATEGORY_SUB
do
  CATEGORY=$(echo "$ENTRY" | cut -d'/' -f1)
  SUB=$(echo "$ENTRY" | cut -d'/' -f2)
  COMBINED=${CATEGORY}_${SUB}

  html_end "$COMBINED.html"
done

rm -f "$TARGET_DIR"/*.html
mv  -f "$HTML_DIR"/*.html "$TARGET_DIR"
rmdir "$HTML_DIR"

