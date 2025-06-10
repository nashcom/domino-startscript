#!/bin/bash

# Generate Domino Download Server software list

# Remote server URL can be set to point to another server.
# SERVER_URL=


if [ "$CATALOG_BROSWING" = "no" ]; then
  exit 0
fi


if [ -z "$CATALOG_MAX_AGE_SEC" ]; then
  CATALOG_MAX_AGE_SEC=120
fi


INDEX_FILE=index.html

if [ -z "$SOFTWARE_DIR" ]; then
  TARGET_DIR="/local/software"
else
  TARGET_DIR="$SOFTWARE_DIR"
fi

HTML_DIR="$TARGET_DIR/html.update"

CATALOG_FILE="$TARGET_DIR/catalog.list"
CATALOG_JSON="$TARGET_DIR/catalog.json"
CATALOG_JSON_RAW="$TARGET_DIR/mhs_files_domino.json"
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


write_css()
{
  local FILE="$HTML_DIR/$1"

  if [ -z "$1" ]; then
    return 0
  fi

  echo "body {margin: 0px; font-family: Arial, sans-serif;}" > "$FILE"
  echo "table {border-collapse: collapse; width: 100%}" >> "$FILE"
  echo "th, td {text-align: left; margin: 0; padding: 8px; padding-left: 20px; padding-right: 20px;}" >> "$FILE"
  echo "tr:nth-child(even) {background-color: #f2f2f2;}" >> "$FILE"
  echo "a.links:link {text-decoration: none; color:#0F52BA;}" >> "$FILE"
  echo "a.links:visited {text-decoration: none; color:#0F52BA;}" >> "$FILE"
  echo "a.links:hover {text-decoration: none; color:#0F52BA; font-weight: bold;}" >> "$FILE"
  echo ".header {margin: -0px; border: 0px; padding: 1px; padding-left: 20px; text-align: left; background: #000000; color: white; font-size: 14px;}" >> "$FILE"
  echo ".hash {font-family: 'Courier';}" >> "$FILE"
  echo ".c1 {width: 20%;}" >> "$FILE"
  echo ".c2 {width: 40%;}" >> "$FILE"
  echo ".c3 {width: 40%}" >> "$FILE"
}


html_begin()
{
  local FILE="$HTML_DIR/$1"

  if [ -z "$1" ]; then
    return 0
  fi

  echo "<!DOCTYPE html>" > "$FILE"
  echo "<html>" >> "$FILE"
  echo "<head>" >> "$FILE"
  echo "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" >> "$FILE"
  echo "<link rel=\"stylesheet\" href=\"style.css\"/>" >> "$FILE"
  echo "<title>$2</title" >> "$FILE"
  echo "</head>" >> "$FILE"
  echo "<body>" >> "$FILE"
  echo "<div class=\"header\"><h1>$2</h1></div><br>" >> "$FILE"
  echo "<table>" >> "$FILE"
  echo "<tr> <th class=\"c1\">$3</th> <th class=\"c2\">$4</th> <th class=\"c3\">$5</th> </tr>" >> "$FILE"
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

  echo "<br></table>" >> "$FILE"
  echo "</body>" >> "$FILE"
  echo "</html>" >> "$FILE"
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

  echo "<tr> <td class=\"c1\"> <a class=\"links\" href=\"$LINK\">$TEXT</a> </td> <td class=\"c3\"> $DESCRIPTION </td> <td class=\"c3\"> <span class=\"hash\">$HASH</span> </td> </tr>" >> "$FILE"
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
check_file_older "$CATALOG_JSON" "$CATALOG_MAX_AGE_SEC"

# Touch file to lower the risk of race conditions for parallel requests
touch "$CATALOG_JSON"

LogTrace "Reading $CATALOG_JSON"
curl -sL https://my.hcltechsw.com/files/domino -o "$CATALOG_JSON_RAW"
cat "$CATALOG_JSON_RAW" | jq .files[] > "$CATALOG_JSON"

# If file is too small (32k), this isn't a valid JSON file
check_file_smaller "$CATALOG_JSON" 32768

# Read MHS the Domino catalog JSON data for providing it to other services
curl -sL https://my.hcltechsw.com/catalog/domino -o "$MHS_DOMINO_CATALOG"

LogTrace "Generating $CATALOG_FILE"

cat "$CATALOG_JSON"| jq -r '.locations[0] + "|" + .name + "|" + .description  + "|" + .checksums.sha256'  | sort -V | cut -d'/' -f2- > "$CATALOG_TEMP"

if [ -z "$CATALOG_EXCLUDE_PATTERN" ]; then
  CATALOG_EXCLUDE_PATTERN="12.0.1|IBMi|verse|mobile|versemobile|voltscript|appdev/|caa/|dlau/|domino/11|notes/11|ccm/|htmo/|hei/11|traveler/apnscerts|.pdf|.txt|consap/|14ea|14.5ea1|14.5ea2"
fi

# Exclude software, which should not be listed
cat "$CATALOG_TEMP" | grep -v -E "$CATALOG_EXCLUDE_PATTERN"  > "$CATALOG_FILE"

rm -f "$CATALOG_TEMP"
LogTrace "Catalog entries generated: $(cat "$CATALOG_FILE" | wc -l | xargs)"


# Create temporary directory to store HTML files
mkdir -p "$HTML_DIR"

CATEGORY_TOP=$(cat "$CATALOG_FILE" | cut -f1 -d'/' | uniq)
CATEGORY_SUB=$(cat "$CATALOG_FILE" | cut -f1 -d'|' | uniq)

write_css "style.css"

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
  IFS='/' read -r -a PARTS <<< "$ENTRY"
  CATEGORY=${PARTS[0]}
  SUB=${PARTS[1]}
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

  IFS='|' read -r -a PARTS <<< "$LINE"

  ENTRY=${PARTS[0]}
  FILE=${PARTS[1]}
  DESCRIPTION=${PARTS[2]}
  HASH=${PARTS[3]}

  IFS='/' read -r -a PARTS <<< "$ENTRY"

  CATEGORY=${PARTS[0]}
  SUB=${PARTS[1]}
  COMBINED=${CATEGORY}_${SUB}

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

  IFS='/' read -r -a PARTS <<< "$ENTRY"
  CATEGORY=${PARTS[0]}
  SUB=${PARTS[1]}
  COMBINED=${CATEGORY}_${SUB}

  html_end "$COMBINED.html"
done

LogTrace "Moving files and cleaning up"

# Move new files and remove older files not updated

touch "$HTML_DIR"/*.html
mv  -f "$HTML_DIR"/*.html "$TARGET_DIR"
mv  -f "$HTML_DIR"/style.css "$TARGET_DIR"

find "$TARGET_DIR" ! -newer "$CATALOG_JSON" -type f -name "*.html" -exec rm {} \;
rmdir "$HTML_DIR"

LogTrace "Completed"
